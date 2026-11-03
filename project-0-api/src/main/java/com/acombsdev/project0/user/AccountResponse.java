package com.acombsdev.project0.user;

public record AccountResponse(String email, String firstName, String lastName, String phoneNumber) {
    static AccountResponse from(User user) {
        return new AccountResponse(user.getEmail(), user.getFirstName(), user.getLastName(), user.getPhoneNumber());
    }
}
