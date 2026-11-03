package com.acombsdev.project0.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.time.Duration;
import java.util.List;

@Configuration
public class AccountSecurityConfig {
    @Bean
    @Order(1)
    SecurityFilterChain accountSecurity(HttpSecurity http) throws Exception {
        return http
                .securityMatcher("/api/account", "/api/account/**")
                .cors(Customizer.withDefaults())
                .authorizeHttpRequests(authorize -> authorize.anyRequest().authenticated())
                // Stateless bearer-token API: no session exists, so skip session-fixation protection.
                // (On AWS Lambda the serverless request does not support changeSessionId, and
                // the default protection fails every authenticated request there.)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                        .sessionFixation(fixation -> fixation.none()))
                .csrf(csrf -> csrf.disable())
                .oauth2ResourceServer(oauth -> oauth.jwt(Customizer.withDefaults()))
                .build();
    }

    @Bean
    @Order(2)
    SecurityFilterChain publicSecurity(HttpSecurity http) throws Exception {
        return http
                .cors(Customizer.withDefaults())
                .authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll())
                .csrf(csrf -> csrf.disable())
                .build();
    }

    // The deployed UI is served from a different host than the API, so the browser needs CORS
    // approval for the account and health calls. No origins configured means no cross-origin access.
    @Bean
    CorsConfigurationSource corsConfigurationSource(@Value("${app.cors.allowed-origins:}") List<String> allowedOrigins) {
        CorsConfiguration cors = new CorsConfiguration();
        cors.setAllowedOrigins(allowedOrigins.stream().map(String::trim).filter(origin -> !origin.isEmpty()).toList());
        cors.setAllowedMethods(List.of("GET", "PUT"));
        cors.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        cors.setMaxAge(Duration.ofHours(1));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/account", cors);
        source.registerCorsConfiguration("/api/account/**", cors);
        source.registerCorsConfiguration("/actuator/health", cors);
        return source;
    }

    @Bean
    JwtDecoder accountJwtDecoder(
            @Value("${app.cognito.issuer}") String issuer,
            @Value("${app.cognito.client-id}") String clientId
    ) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(issuer + "/.well-known/jwks.json").build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(issuer),
                identityTokenValidator(clientId)
        ));
        return decoder;
    }

    static OAuth2TokenValidator<Jwt> identityTokenValidator(String clientId) {
        OAuth2Error error = new OAuth2Error("invalid_token", "A verified Cognito identity token is required.", null);
        return jwt -> {
            String email = jwt.getClaimAsString("email");
            String subject = jwt.getSubject();
            if (!"id".equals(jwt.getClaimAsString("token_use"))
                    || jwt.getAudience() == null || !jwt.getAudience().contains(clientId)
                    || !Boolean.TRUE.equals(jwt.getClaims().get("email_verified"))
                    || email == null || email.isBlank()
                    || subject == null || subject.isBlank()
                    || jwt.getExpiresAt() == null) {
                return OAuth2TokenValidatorResult.failure(error);
            }
            return OAuth2TokenValidatorResult.success();
        };
    }
}
