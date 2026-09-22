package io.logitrack.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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

    @Test void requiresAuthenticationForAnyPublicBrowserOrigin(){
        new SecurityBoundaryValidator(false,"http://localhost:3000,http://127.0.0.1:3000").validate();
        assertThatThrownBy(()->new SecurityBoundaryValidator(false,"https://staging.logitrack.kr").validate())
            .isInstanceOf(IllegalStateException.class).hasMessageContaining("SECURITY_ENABLED");
        new SecurityBoundaryValidator(true,"https://staging.logitrack.kr").validate();
    }
}
