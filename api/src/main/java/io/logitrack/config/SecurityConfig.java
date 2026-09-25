package io.logitrack.config;

import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.time.Instant;
import java.time.Duration;
import java.util.stream.Collectors;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;

@Configuration
public class SecurityConfig {
    static final Set<String> ROLES=Set.of("VIEWER","OPERATOR","RECOVERY_OPERATOR","ADMIN");
    static final long ALLOWED_CLOCK_SKEW_SECONDS=60;
    static final long MAX_ACCESS_TOKEN_LIFETIME_SECONDS=3660;

    @Bean
    @ConditionalOnProperty(name="logitrack.security.enabled",havingValue="false",matchIfMissing=true)
    SecurityFilterChain localSecurity(HttpSecurity http)throws Exception{
        return http.csrf(csrf->csrf.ignoringRequestMatchers("/api/**")).cors(Customizer.withDefaults())
            .headers(headers->headers.contentSecurityPolicy(csp->csp.policyDirectives(SecurityHeadersFilter.CONTENT_SECURITY_POLICY)))
            .authorizeHttpRequests(auth->auth.anyRequest().permitAll()).build();
    }

    @Bean
    @ConditionalOnProperty(name="logitrack.security.enabled",havingValue="true")
    JwtDecoder jwtDecoder(
        @org.springframework.beans.factory.annotation.Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuer,
        @org.springframework.beans.factory.annotation.Value("${logitrack.security.client-id}") String clientId){
        NimbusJwtDecoder decoder=NimbusJwtDecoder.withIssuerLocation(issuer).jwsAlgorithm(SignatureAlgorithm.RS256).build();
        var issuerValidator=JwtValidators.createDefaultWithIssuer(issuer);
        decoder.setJwtValidator(jwt->{
            var standard=issuerValidator.validate(jwt);if(standard.hasErrors())return standard;
            return validateAccessToken(jwt,clientId,Instant.now());
        });
        return decoder;
    }

    static OAuth2TokenValidatorResult validateAccessToken(Jwt jwt,String clientId,Instant now){
        boolean valid="access".equals(jwt.getClaimAsString("token_use"))
            &&clientId.equals(jwt.getClaimAsString("client_id"))
            &&AuthenticatedOperatorFilter.isValidSubject(jwt.getSubject())
            &&jwt.getIssuedAt()!=null
            &&!jwt.getIssuedAt().isAfter(now.plusSeconds(ALLOWED_CLOCK_SKEW_SECONDS))
            &&jwt.getExpiresAt()!=null
            &&jwt.getExpiresAt().isAfter(jwt.getIssuedAt())
            &&Duration.between(jwt.getIssuedAt(),jwt.getExpiresAt()).getSeconds()<=MAX_ACCESS_TOKEN_LIFETIME_SECONDS;
        return valid?OAuth2TokenValidatorResult.success():OAuth2TokenValidatorResult.failure(
            new OAuth2Error("invalid_token","Token is not a current LogiTrack access token",null));
    }

    @Bean
    @ConditionalOnProperty(name="logitrack.security.enabled",havingValue="true")
    SecurityFilterChain oidcSecurity(HttpSecurity http,AuthenticatedOperatorFilter operatorFilter)throws Exception{
        return http.csrf(csrf->csrf.ignoringRequestMatchers("/api/**")).cors(Customizer.withDefaults())
            .headers(headers->headers.contentSecurityPolicy(csp->csp.policyDirectives(SecurityHeadersFilter.CONTENT_SECURITY_POLICY)))
            .sessionManagement(session->session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth->auth
                .requestMatchers("/actuator/health/**").permitAll()
                .requestMatchers("/api/operations/**").hasAnyRole("RECOVERY_OPERATOR","ADMIN")
                .requestMatchers("/api/alert-policies/**").hasRole("ADMIN")
                .requestMatchers(org.springframework.http.HttpMethod.POST,"/api/alerts/*/acknowledgement").hasAnyRole("OPERATOR","ADMIN")
                .requestMatchers(org.springframework.http.HttpMethod.POST,"/api/**").hasAnyRole("OPERATOR","ADMIN")
                .requestMatchers(org.springframework.http.HttpMethod.DELETE,"/api/**").hasRole("ADMIN")
                .requestMatchers(org.springframework.http.HttpMethod.GET,"/api/**").hasAnyRole("VIEWER","OPERATOR","RECOVERY_OPERATOR","ADMIN")
                .requestMatchers("/api/**").denyAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth->oauth.jwt(jwt->jwt.jwtAuthenticationConverter(jwtAuthenticationConverter())))
            .addFilterAfter(operatorFilter,BearerTokenAuthenticationFilter.class).build();
    }

    static JwtAuthenticationConverter jwtAuthenticationConverter(){
        var converter=new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(new RoleClaimConverter());
        return converter;
    }

    static final class RoleClaimConverter implements Converter<Jwt,Collection<GrantedAuthority>>{
        @Override public Collection<GrantedAuthority> convert(Jwt jwt){
            Object claim=jwt.getClaims().containsKey("cognito:groups")?jwt.getClaims().get("cognito:groups"):jwt.getClaims().get("roles");
            Collection<?> values=claim instanceof Collection<?> collection?collection:claim instanceof String text?List.of(text.split(",")):List.of();
            return values.stream().map(String::valueOf).map(String::trim).map(value->value.toUpperCase(Locale.ROOT))
                .filter(ROLES::contains).distinct().map(role->(GrantedAuthority)new SimpleGrantedAuthority("ROLE_"+role)).collect(Collectors.toUnmodifiableList());
        }
    }
}
