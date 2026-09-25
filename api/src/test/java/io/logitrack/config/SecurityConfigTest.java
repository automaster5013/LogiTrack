package io.logitrack.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;

class SecurityConfigTest{
    @AfterEach void clearSecurity(){SecurityContextHolder.clearContext();}

    @Test void mapsOnlySupportedRolesFromJwt(){
        var jwt=Jwt.withTokenValue("token").header("alg","none").subject("operator-7")
            .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(60))
            .claim("roles",List.of("viewer","RECOVERY_OPERATOR","unknown","viewer")).build();
        assertThat(new SecurityConfig.RoleClaimConverter().convert(jwt)).extracting("authority")
            .containsExactly("ROLE_VIEWER","ROLE_RECOVERY_OPERATOR");
    }

    @Test void mapsCognitoGroupsBeforeGenericRoles(){
        var jwt=Jwt.withTokenValue("token").header("alg","none").subject("operator-8")
            .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(60))
            .claim("cognito:groups",List.of("ADMIN")).claim("roles",List.of("VIEWER")).build();
        assertThat(new SecurityConfig.RoleClaimConverter().convert(jwt)).extracting("authority").containsExactly("ROLE_ADMIN");
    }

    @Test void validatesAccessTokenPurposeClientAndIssuedAtBoundary(){
        var now=Instant.parse("2026-09-25T00:00:00Z");
        var valid=Jwt.withTokenValue("valid").header("alg","RS256").subject("operator")
            .issuedAt(now.plusSeconds(60)).expiresAt(now.plusSeconds(3600))
            .claim("token_use","access").claim("client_id","logitrack-client").build();
        var future=Jwt.withTokenValue("future").header("alg","RS256").subject("operator")
            .issuedAt(now.plusSeconds(61)).expiresAt(now.plusSeconds(3600))
            .claim("token_use","access").claim("client_id","logitrack-client").build();
        assertThat(SecurityConfig.validateAccessToken(valid,"logitrack-client",now).hasErrors()).isFalse();
        assertThat(SecurityConfig.validateAccessToken(future,"logitrack-client",now).hasErrors()).isTrue();
        assertThat(SecurityConfig.validateAccessToken(valid,"another-client",now).hasErrors()).isTrue();
        var oversizedSubject=Jwt.withTokenValue("oversized").header("alg","RS256").subject("x".repeat(121))
            .issuedAt(now).expiresAt(now.plusSeconds(3600)).claim("token_use","access")
            .claim("client_id","logitrack-client").build();
        assertThat(SecurityConfig.validateAccessToken(oversizedSubject,"logitrack-client",now).hasErrors()).isTrue();
        for(var invalidSubject:List.of(" operator","operator ","operator\nname","\ufeffoperator")){
            var malformedSubject=Jwt.withTokenValue("malformed").header("alg","RS256").subject(invalidSubject)
                .issuedAt(now).expiresAt(now.plusSeconds(3600)).claim("token_use","access")
                .claim("client_id","logitrack-client").build();
            assertThat(SecurityConfig.validateAccessToken(malformedSubject,"logitrack-client",now).hasErrors()).isTrue();
        }
        var reversedLifetime=mock(Jwt.class);
        when(reversedLifetime.getClaimAsString("token_use")).thenReturn("access");
        when(reversedLifetime.getClaimAsString("client_id")).thenReturn("logitrack-client");
        when(reversedLifetime.getSubject()).thenReturn("operator");
        when(reversedLifetime.getIssuedAt()).thenReturn(now.plusSeconds(30));
        when(reversedLifetime.getExpiresAt()).thenReturn(now.plusSeconds(29));
        var excessiveLifetime=Jwt.withTokenValue("excessive").header("alg","RS256").subject("operator")
            .issuedAt(now).expiresAt(now.plusSeconds(3661)).claim("token_use","access")
            .claim("client_id","logitrack-client").build();
        assertThat(SecurityConfig.validateAccessToken(reversedLifetime,"logitrack-client",now).hasErrors()).isTrue();
        assertThat(SecurityConfig.validateAccessToken(excessiveLifetime,"logitrack-client",now).hasErrors()).isTrue();
    }

    @Test void replacesSpoofedOperatorHeaderWithAuthenticatedSubject()throws Exception{
        var authentication=new TestingAuthenticationToken("oidc-subject-42","n/a");
        authentication.setAuthenticated(true);
        SecurityContextHolder.getContext().setAuthentication(authentication);
        var request=new MockHttpServletRequest();request.addHeader("X-Operator","spoofed-client");
        var chain=new MockFilterChain();
        new AuthenticatedOperatorFilter().doFilter(request,new MockHttpServletResponse(),chain);
        assertThat(((HttpServletRequest)chain.getRequest()).getHeader("X-Operator")).isEqualTo("oidc-subject-42");
    }

    @Test void rejectsAuthenticatedSubjectOutsideAuditBoundary()throws Exception{
        var authentication=new TestingAuthenticationToken("x".repeat(121),"n/a");authentication.setAuthenticated(true);
        SecurityContextHolder.getContext().setAuthentication(authentication);
        var response=new MockHttpServletResponse();var chain=new MockFilterChain();
        new AuthenticatedOperatorFilter().doFilter(new MockHttpServletRequest(),response,chain);
        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(chain.getRequest()).isNull();
    }

    @Test void rejectsPaddedOrControlCharacterAuditSubjects()throws Exception{
        for(var actor:List.of(" operator","operator ","operator\nname","\u00a0operator","operator\ufeff")){
            var authentication=new TestingAuthenticationToken(actor,"n/a");authentication.setAuthenticated(true);
            SecurityContextHolder.getContext().setAuthentication(authentication);
            var response=new MockHttpServletResponse();var chain=new MockFilterChain();
            new AuthenticatedOperatorFilter().doFilter(new MockHttpServletRequest(),response,chain);
            assertThat(response.getStatus()).isEqualTo(401);
            assertThat(chain.getRequest()).isNull();
        }
    }

    @Test void requiresAuthenticationForAnyPublicBrowserOrigin(){
        new SecurityBoundaryValidator(false,"http://localhost:3000,http://127.0.0.1:3000").validate();
        assertThatThrownBy(()->new SecurityBoundaryValidator(false,"https://staging.logitrack.kr").validate())
            .isInstanceOf(IllegalStateException.class).hasMessageContaining("SECURITY_ENABLED");
        new SecurityBoundaryValidator(true,"https://staging.logitrack.kr").validate();
    }
}
