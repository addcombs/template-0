package com.acombsdev.project0.user;

import com.acombsdev.project0.security.AccountSecurityConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(controllers = AccountController.class, properties = "app.cors.allowed-origins=https://app.example")
@Import(AccountSecurityConfig.class)
class AccountControllerTest {
    @Autowired MockMvc mvc;
    @MockitoBean AccountService service;
    @MockitoBean JwtDecoder decoder;

    private Jwt identity() {
        return Jwt.withTokenValue("valid").header("alg", "RS256").subject("subject")
                .audience(List.of("client")).claim("email", "user@example.com").build();
    }

    @Test
    void requiresAnAuthenticatedIdentity() throws Exception {
        mvc.perform(get("/api/account")).andExpect(status().isUnauthorized());
        when(decoder.decode("bad")).thenThrow(new BadJwtException("Invalid signature"));
        mvc.perform(get("/api/account").header("Authorization", "Bearer bad"))
                .andExpect(status().isUnauthorized());
        verifyNoInteractions(service);
    }

    @Test
    void allowsCrossOriginCallsOnlyFromConfiguredOrigins() throws Exception {
        mvc.perform(options("/api/account").header("Origin", "https://app.example")
                        .header("Access-Control-Request-Method", "PUT")
                        .header("Access-Control-Request-Headers", "authorization,content-type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "https://app.example"));
        mvc.perform(options("/api/account").header("Origin", "https://other.example")
                        .header("Access-Control-Request-Method", "PUT"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(service);
    }

    @Test
    void usesIdentityClaimsAndValidatesInput() throws Exception {
        when(decoder.decode("valid")).thenReturn(identity());
        when(service.save(eq("subject"), eq("user@example.com"), any()))
                .thenReturn(new AccountResponse("user@example.com", "Jane", "Doe", null));
        mvc.perform(put("/api/account").header("Authorization", "Bearer valid")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"attacker@example.com\",\"firstName\":\"Jane\",\"lastName\":\"Doe\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.email").value("user@example.com"));
        verify(service).save(eq("subject"), eq("user@example.com"), any());
        mvc.perform(put("/api/account").header("Authorization", "Bearer valid")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"firstName\":\" \",\"lastName\":\"Doe\"}"))
                .andExpect(status().isBadRequest());
        verifyNoMoreInteractions(service);
    }
}
