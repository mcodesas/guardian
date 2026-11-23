package com.mcode.guardian.device;

import static org.junit.jupiter.api.Assertions.*;
import java.security.SecureRandom;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import org.junit.jupiter.api.Test;

class EvidenceEncryptionTest {
    private static EvidenceEncryption encryption() {
        byte[] secret = new byte[32];
        new SecureRandom().nextBytes(secret);
        return new EvidenceEncryption(Base64.getEncoder().encodeToString(secret));
    }

    @Test void evidenceRoundTripsWithAuthenticatedEncryption() {
        EvidenceEncryption service = encryption();
        byte[] input = "4.57123,-74.23456,35.00".getBytes(StandardCharsets.UTF_8);
        byte[] encrypted = service.encrypt(input);
        assertFalse(Arrays.equals(input, encrypted));
        assertArrayEquals(input,service.decrypt(encrypted));
    }

    @Test void tamperedEvidenceIsRejected() {
        EvidenceEncryption service = encryption();
        byte[] encrypted = service.encrypt("sample".getBytes(StandardCharsets.UTF_8));
        encrypted[15] ^= 1;
        assertThrows(IllegalStateException.class, () -> service.decrypt(encrypted));
    }

    @Test void noSecretRejectsPhotoOperations() {
        EvidenceEncryption service = new EvidenceEncryption("");
        assertFalse(service.enabled());
        assertThrows(IllegalStateException.class,
                () -> service.encrypt("test".getBytes(StandardCharsets.UTF_8)));
    }
}
