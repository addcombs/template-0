package com.acombsdev.project0.user;

import jakarta.persistence.EntityNotFoundException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Optional;

@Service
public class AccountService {
    private final UserRepository repository;

    public AccountService(UserRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public AccountResponse find(String subject, String email) {
        User user = findOwnedUser(subject, email)
                .orElseThrow(() -> new EntityNotFoundException("Account details not found."));
        if (user.getCognitoSub() == null) {
            user.setCognitoSub(subject);
            repository.save(user);
        }
        return AccountResponse.from(user);
    }

    @Transactional
    public AccountResponse save(String subject, String email, AccountRequest request) {
        Optional<User> existing = findOwnedUser(subject, email);
        User user = existing.orElseGet(User::new);
        OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        if (existing.isEmpty()) {
            user.setEmail(email);
            user.setCreateDate(now);
            user.setCreateUser(subject);
        } else {
            user.setUpdateDate(now);
            user.setUpdateUser(subject);
        }
        user.setCognitoSub(subject);
        user.setFirstName(request.firstName().trim());
        user.setLastName(request.lastName().trim());
        String phone = request.phoneNumber();
        user.setPhoneNumber(phone == null || phone.isBlank() ? null : phone.trim());
        return AccountResponse.from(repository.saveAndFlush(user));
    }

    private Optional<User> findOwnedUser(String subject, String email) {
        Optional<User> bySubject = repository.findByCognitoSub(subject);
        if (bySubject.isPresent()) {
            if (bySubject.get().getEmail() == null || !bySubject.get().getEmail().equalsIgnoreCase(email)) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "The account email does not match your verified Cognito email.");
            }
            return bySubject;
        }
        Optional<User> byEmail = repository.findByEmailIgnoreCase(email);
        if (byEmail.isPresent() && byEmail.get().getCognitoSub() != null
                && !byEmail.get().getCognitoSub().equals(subject)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This account is already linked to another identity.");
        }
        return byEmail;
    }
}
