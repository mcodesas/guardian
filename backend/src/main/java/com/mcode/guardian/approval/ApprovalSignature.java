package com.mcode.guardian.approval;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.stereotype.Component;

@Component
public class ApprovalSignature {
    private static final byte[] ED25519_PREFIX =
        HexFormat.of().parseHex("302a300506032b6570032100");

    public static String canonical(UUID challenge, String nonce, String decision, int minutes) {
        return "guardian:v1:" + challenge + ":" + nonce + ":" + decision + ":" + minutes;
    }

    public boolean verify(String publicKeyB64, String signatureB64, String canonical) {
        try {
            byte[] raw = Base64.getDecoder().decode(publicKeyB64);
            byte[] signature = Base64.getDecoder().decode(signatureB64);
            if (raw.length != 32 || signature.length != 64) return false;
            byte[] encoded = new byte[ED25519_PREFIX.length + raw.length];
            System.arraycopy(ED25519_PREFIX, 0, encoded, 0, ED25519_PREFIX.length);
            System.arraycopy(raw, 0, encoded, ED25519_PREFIX.length, raw.length);
            KeyFactory factory = KeyFactory.getInstance("Ed25519");
            Signature verifier = Signature.getInstance("Ed25519");
            verifier.initVerify(factory.generatePublic(new X509EncodedKeySpec(encoded)));
            verifier.update(canonical.getBytes(StandardCharsets.UTF_8));
            return verifier.verify(signature);
        } catch (Exception ex) {
            return false;
        }
    }
}