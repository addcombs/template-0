package com.acombsdev.template0.user;

import com.acombsdev.template0.security.AccountSecurityConfig;
import org.springdoc.core.configuration.SpringDocConfiguration;
import org.springdoc.core.properties.SpringDocConfigProperties;
import org.springdoc.core.properties.SwaggerUiConfigProperties;
import org.springdoc.core.properties.SwaggerUiOAuthProperties;
import org.springdoc.webmvc.core.configuration.SpringDocWebMvcConfiguration;
import org.springdoc.webmvc.ui.SwaggerConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AccountController.class)
@ImportAutoConfiguration({SpringDocConfigProperties.class, SpringDocConfiguration.class,
        SpringDocWebMvcConfiguration.class, SwaggerUiConfigProperties.class,
        SwaggerUiOAuthProperties.class, SwaggerConfig.class})
@Import(AccountSecurityConfig.class)
class OpenApiDocumentationTest {
    @Autowired MockMvc mvc;
    @MockitoBean AccountService accountService;
    @MockitoBean JwtDecoder decoder;

    @Test
    void documentsAccountApiWithSecurity() throws Exception {
        mvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.info.title").value("template-0 API"))
                .andExpect(jsonPath("$.paths['/api/account'].get.summary").value("Get the current user's account"))
                .andExpect(jsonPath("$.paths['/api/account'].get.security[0].cognitoIdToken").isArray())
                .andExpect(jsonPath("$.paths['/api/account'].put.security[0].cognitoIdToken").isArray())
                .andExpect(jsonPath("$.paths['/api/account'].get.parameters").doesNotExist())
                .andExpect(jsonPath("$.paths['/actuator/health']").doesNotExist())
                .andExpect(jsonPath("$.components.securitySchemes.cognitoIdToken.scheme").value("bearer"));
    }

    @Test
    void servesSwaggerUi() throws Exception {
        mvc.perform(get("/swagger-ui.html"))
                .andExpect(status().isFound())
                .andExpect(redirectedUrl("/swagger-ui/index.html"));
    }

    @Test
    void servesSwaggerUiAssetsAsUtf8() throws Exception {
        mvc.perform(get("/swagger-ui/swagger-ui.css"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("text/css;charset=UTF-8"));
    }
}
