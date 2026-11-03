package com.acombsdev.project0.security;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidators;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class AccountSecurityConfigTest {
    private Jwt token(String type, String client, boolean verified) {
        return Jwt.withTokenValue("token").header("alg", "RS256")
                .subject("subject").audience(List.of(client))
                .expiresAt(Instant.now().plusSeconds(300))
                .claim("token_use", type).claim("email", "user@example.com")
                .claim("email_verified", verified).build();
    }

    @Test
    void acceptsOnlyVerifiedIdentityTokensForTheConfiguredClient() {
        var validator = AccountSecurityConfig.identityTokenValidator("client");
        assertFalse(validator.validate(token("id", "client", true)).hasErrors());
        assertTrue(validator.validate(token("access", "client", true)).hasErrors());
        assertTrue(validator.validate(token("id", "wrong", true)).hasErrors());
        assertTrue(validator.validate(token("id", "client", false)).hasErrors());
        Jwt noAudience = Jwt.withTokenValue("token").header("alg", "RS256")
                .subject("subject").claim("token_use", "id").claim("email", "user@example.com")
                .claim("email_verified", true).build();
        assertTrue(validator.validate(noAudience).hasErrors());
        Jwt noExpiry = Jwt.withTokenValue("token").header("alg", "RS256")
                .subject("subject").audience(List.of("client")).claim("token_use", "id")
                .claim("email", "user@example.com").claim("email_verified", true).build();
        assertTrue(validator.validate(noExpiry).hasErrors());
    }

    @Test
    void defaultValidatorRejectsWrongIssuerAndExpiredTokens() {
        var validator = JwtValidators.createDefaultWithIssuer("https://issuer.example");
        Jwt wrongIssuer = Jwt.withTokenValue("token").header("alg", "RS256")
                .issuer("https://other.example").expiresAt(Instant.now().plusSeconds(300)).build();
        Jwt expired = Jwt.withTokenValue("token").header("alg", "RS256")
                .issuer("https://issuer.example").expiresAt(Instant.now().minusSeconds(120)).build();
        assertTrue(validator.validate(wrongIssuer).hasErrors());
        assertTrue(validator.validate(expired).hasErrors());
    }

    @Test
    void decoderVerifiesSignatureAndAllIdentityClaims() throws Exception {
        RSAKey signingKey = new RSAKeyGenerator(2048).keyID("test").generate();
        RSAKey otherKey = new RSAKeyGenerator(2048).keyID("test").generate();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/.well-known/jwks.json", exchange -> {
            byte[] body = new JWKSet(signingKey.toPublicJWK()).toString().getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length);
            try (var stream = exchange.getResponseBody()) {
                stream.write(body);
            }
        });
        server.start();
        try {
            String issuer = "http://127.0.0.1:" + server.getAddress().getPort();
            var decoder = new AccountSecurityConfig().accountJwtDecoder(issuer, "client");
            JWTClaimsSet claims = new JWTClaimsSet.Builder().issuer(issuer).subject("subject")
                    .audience("client").expirationTime(Date.from(Instant.now().plusSeconds(300)))
                    .claim("token_use", "id").claim("email", "user@example.com")
                    .claim("email_verified", true).build();
            assertEquals("subject", decoder.decode(sign(claims, signingKey)).getSubject());
            assertThrows(JwtException.class, () -> decoder.decode(sign(claims, otherKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).issuer(issuer + "/wrong").build(), signingKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).audience("wrong").build(), signingKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).claim("token_use", "access").build(), signingKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).claim("email_verified", false).build(), signingKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).expirationTime(Date.from(Instant.now().minusSeconds(120))).build(), signingKey)));
            assertThrows(JwtException.class, () -> decoder.decode(sign(
                    new JWTClaimsSet.Builder(claims).expirationTime(null).build(), signingKey)));
        } finally {
            server.stop(0);
        }
    }

    private String sign(JWTClaimsSet claims, RSAKey key) throws Exception {
        SignedJWT token = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID("test").build(), claims);
        token.sign(new RSASSASigner(key));
        return token.serialize();
    }
}
