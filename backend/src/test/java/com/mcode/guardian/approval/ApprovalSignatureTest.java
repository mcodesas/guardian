package com.mcode.guardian.approval;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.interfaces.EdECPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class ApprovalSignatureTest {
    @Test
    void validEd25519SignatureIsVerifiedButTamperingIsRejected() throws Exception {
        KeyPair pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair();
        byte[] encoded = pair.getPublic().getEncoded();
        byte[] raw = Arrays.copyOfRange(encoded, encoded.length - 32, encoded.length);
        UUID challengeId = UUID.randomUUID();
        String canonical = ApprovalSignature.canonical(challengeId, "nonce", "APPROVED", 5);
        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(pair.getPrivate());
        signer.update(canonical.getBytes(StandardCharsets.UTF_8));
        String signed = Base64.getEncoder().encodeToString(signer.sign());
        ApprovalSignature verifier = new ApprovalSignature();
        String publicKey = Base64.getEncoder().encodeToString(raw);
        assertTrue(verifier.verify(publicKey, signed, canonical));
        assertFalse(verifier.verify(publicKey, signed,
            ApprovalSignature.canonical(challengeId, "nonce", "APPROVED", 30)));
        assertFalse(verifier.verify(publicKey, "AA==", canonical));
    }
}