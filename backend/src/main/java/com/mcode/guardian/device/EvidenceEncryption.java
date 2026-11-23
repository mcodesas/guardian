package com.mcode.guardian.device;

import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Authenticated encryption. The key must come from protected server configuration. */
@Component
public final class EvidenceEncryption {
    private final byte[] key;
    private final SecureRandom random = new SecureRandom();

    public EvidenceEncryption(@Value("${GUARDIAN_EVIDENCE_KEY_BASE64:}") String b64) {
        if (b64 == null || b64.isBlank()) {
            this.key = null; // Locations without photos still work until evidence key is configured.
        } else {
            byte[] value = Base64.getDecoder().decode(b64);
            if (value.length != 32) throw new IllegalStateException("Evidence key must be 32 bytes");
            this.key = value;
        }
    }

    public boolean enabled() { return key != null; }

    public byte[] encrypt(byte[] input) {
        if (!enabled()) throw new IllegalStateException("Evidence encryption is not configured");
        try {
            byte[] nonce = new byte[12];
            random.nextBytes(nonce);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
            byte[] ciphertext = cipher.doFinal(input);
            byte[] joined = Arrays.copyOf(nonce, 12 + ciphertext.length);
            System.arraycopy(ciphertext, 0, joined, 12, ciphertext.length);
            return joined;
        } catch (Exception ex) {
            throw new IllegalStateException("Could not encrypt evidence", ex);
        }
    }

    public byte[] decrypt(byte[] bytes) {
        if (!enabled() || bytes == null || bytes.length < 29) {
            throw new IllegalStateException("Evidence cannot be decrypted");
        }
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"),
                    new GCMParameterSpec(128, Arrays.copyOf(bytes, 12)));
            return cipher.doFinal(bytes, 12, bytes.length - 12);
        } catch (Exception ex) {
            throw new IllegalStateException("Evidence authentication failed", ex);
        }
    }
}
