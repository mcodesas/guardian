package com.mcode.guardian.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.Objects;
import java.util.Set;

/**
 * Pure policy predicates only. These are NOT an approval API or an authentication layer.
 * Future signed decisions must also verify registered credentials atomically.
 */
public final class ApprovalChallengeRules {

    private static final Set<Long> TRUST_MINUTES = Set.of(5L, 15L, 30L);

    private ApprovalChallengeRules() {
    }

    public static boolean isPendingAndUnexpired(
            String state, Instant expiresAt, Instant now) {
        Objects.requireNonNull(state, "state");
        Objects.requireNonNull(expiresAt, "expiresAt");
        Objects.requireNonNull(now, "now");
        return "PENDING".equals(state) && now.isBefore(expiresAt);
    }

    public static boolean isAllowedTrustDuration(Duration duration) {
        return duration != null
                && duration.getSeconds() > 0
                && duration.getSeconds() % 60 == 0
                && TRUST_MINUTES.contains(duration.toMinutes());
    }
}