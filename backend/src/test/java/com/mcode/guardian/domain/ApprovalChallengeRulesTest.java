package com.mcode.guardian.domain;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class ApprovalChallengeRulesTest {

    @Test
    void onlyPendingUnexpiredChallengesCanBeConsidered() {
        Instant now = Instant.parse("2026-11-07T12:00:00Z");
        assertTrue(ApprovalChallengeRules.isPendingAndUnexpired(
                "PENDING", now.plusSeconds(30), now));
        assertFalse(ApprovalChallengeRules.isPendingAndUnexpired(
                "PENDING", now, now));
        assertFalse(ApprovalChallengeRules.isPendingAndUnexpired(
                "APPROVED", now.plusSeconds(30), now));
        assertFalse(ApprovalChallengeRules.isPendingAndUnexpired(
                "REJECTED", now.plusSeconds(30), now));
    }

    @Test
    void trustWindowOnlyAcceptsFiveFifteenOrThirtyMinutes() {
        assertTrue(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofMinutes(5)));
        assertTrue(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofMinutes(15)));
        assertTrue(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofMinutes(30)));
        assertFalse(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofMinutes(1)));
        assertFalse(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofSeconds(301)));
        assertFalse(ApprovalChallengeRules.isAllowedTrustDuration(Duration.ofMinutes(60)));
        assertFalse(ApprovalChallengeRules.isAllowedTrustDuration(null));
    }
}