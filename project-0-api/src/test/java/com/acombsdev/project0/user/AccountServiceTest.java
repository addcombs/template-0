package com.acombsdev.project0.user;

import jakarta.persistence.EntityNotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AccountServiceTest {
    @Mock
    UserRepository repository;

    @InjectMocks
    AccountService service;

    @Test
    void missingAccountIsNotFound() {
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.empty());
        when(repository.findByEmailIgnoreCase("user@example.com")).thenReturn(Optional.empty());
        assertThrows(EntityNotFoundException.class, () -> service.find("subject", "user@example.com"));
    }

    @Test
    void createsUsingVerifiedIdentityAndTrimsInput() {
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.empty());
        when(repository.findByEmailIgnoreCase("user@example.com")).thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));
        AccountResponse response = service.save("subject", "user@example.com", new AccountRequest(" Jane ", " Doe ", " 123 "));
        assertEquals("user@example.com", response.email());
        assertEquals("Jane", response.firstName());
        assertEquals("Doe", response.lastName());
        assertEquals("123", response.phoneNumber());
        verify(repository).saveAndFlush(argThat(user ->
                "subject".equals(user.getCognitoSub()) && "subject".equals(user.getCreateUser())
                        && user.getCreateDate() != null));
    }

    @Test
    void associatesExistingUnlinkedRowUsingVerifiedEmail() {
        User user = new User();
        user.setEmail("User@example.com");
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.empty());
        when(repository.findByEmailIgnoreCase("user@example.com")).thenReturn(Optional.of(user));
        assertEquals("User@example.com", service.find("subject", "user@example.com").email());
        assertEquals("subject", user.getCognitoSub());
        verify(repository).save(user);
    }

    @Test
    void updatesOwnedAccountWithoutChangingEmailOrCreationAudit() {
        User user = new User();
        user.setEmail("user@example.com");
        user.setCognitoSub("subject");
        user.setCreateUser("original");
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.of(user));
        when(repository.saveAndFlush(user)).thenReturn(user);
        AccountResponse response = service.save("subject", "user@example.com", new AccountRequest("Jane", "Doe", " "));
        assertEquals("user@example.com", response.email());
        assertNull(response.phoneNumber());
        assertEquals("original", user.getCreateUser());
        assertEquals("subject", user.getUpdateUser());
        assertNotNull(user.getUpdateDate());
    }

    @Test
    void rejectsEmailAlreadyLinkedToAnotherIdentity() {
        User user = new User();
        user.setEmail("user@example.com");
        user.setCognitoSub("other");
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.empty());
        when(repository.findByEmailIgnoreCase("user@example.com")).thenReturn(Optional.of(user));
        assertThrows(ResponseStatusException.class, () -> service.find("subject", "user@example.com"));
        verify(repository, never()).save(any());
    }

    @Test
    void rejectsChangedEmailForAnExistingIdentity() {
        User user = new User();
        user.setEmail("original@example.com");
        user.setCognitoSub("subject");
        when(repository.findByCognitoSub("subject")).thenReturn(Optional.of(user));
        assertThrows(ResponseStatusException.class, () ->
                service.save("subject", "new@example.com", new AccountRequest("Jane", "Doe", null)));
        verify(repository, never()).saveAndFlush(any());
    }
}
