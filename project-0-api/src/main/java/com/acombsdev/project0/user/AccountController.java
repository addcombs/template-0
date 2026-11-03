package com.acombsdev.project0.user;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/account")
@Tag(name = "Account", description = "Profile for the authenticated Cognito user")
@SecurityScheme(name = "cognitoIdToken", type = SecuritySchemeType.HTTP, scheme = "bearer",
        bearerFormat = "JWT", description = "Verified Cognito ID token")
@SecurityRequirement(name = "cognitoIdToken")
public class AccountController {
    private final AccountService service;

    public AccountController(AccountService service) {
        this.service = service;
    }

    @GetMapping
    @Operation(summary = "Get the current user's account",
            description = "Finds the account by Cognito subject or links an existing row by verified email. Returns 404 if absent.")
    public AccountResponse get(@Parameter(hidden = true) @AuthenticationPrincipal Jwt jwt) {
        return service.find(jwt.getSubject(), jwt.getClaimAsString("email"));
    }

    @PutMapping
    @Operation(summary = "Create or update the current user's account",
            description = "Uses the verified identity token for email and subject; the caller cannot change them. Conflicts return 409.")
    public AccountResponse save(@Parameter(hidden = true) @AuthenticationPrincipal Jwt jwt,
                                @Valid @RequestBody AccountRequest request) {
        return service.save(jwt.getSubject(), jwt.getClaimAsString("email"), request);
    }
}
