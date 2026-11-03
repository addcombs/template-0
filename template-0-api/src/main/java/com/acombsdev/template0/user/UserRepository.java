package com.acombsdev.template0.user;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Integer> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<User> findByCognitoSub(String cognitoSub);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<User> findByEmailIgnoreCase(String email);
}
