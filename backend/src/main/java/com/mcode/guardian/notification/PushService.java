package com.mcode.guardian.notification;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import com.google.firebase.messaging.AndroidConfig;
import com.mcode.guardian.auth.AuthPrincipal;
import com.mcode.guardian.auth.AuthService;
import jakarta.annotation.PostConstruct;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.stereotype.Service;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PushService {
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final String accountPath;
    private final byte[] encryptionKey;
    private FirebaseApp app;
    private final SecureRandom random = new SecureRandom();

    public PushService(JdbcTemplate jdbc, AuthService auth,
        @Value("${GUARDIAN_FIREBASE_SERVICE_ACCOUNT_PATH:}") String accountPath,
        @Value("${GUARDIAN_PUSH_ENCRYPTION_KEY_BASE64:}") String encryptionKey) {
        this.jdbc=jdbc;
        this.auth=auth;
        this.accountPath=accountPath;
        if (!encryptionKey.isEmpty()) {
            byte[] decoded = Base64.getDecoder().decode(encryptionKey);
            if(decoded.length != 32) throw new IllegalStateException(
                "GUARDIAN_PUSH_ENCRYPTION_KEY_BASE64 must contain 32 random bytes");
            this.encryptionKey=decoded;
        } else {
            this.encryptionKey=null;
        }
    }

    @PostConstruct
    public void init() {
        if (accountPath.isBlank()) return;
        if (encryptionKey==null) throw new IllegalStateException(
            "Configure the push encryption key before enabling Firebase");
        try (FileInputStream stream=new FileInputStream(accountPath)) {
            app=FirebaseApp.initializeApp(FirebaseOptions.builder()
                .setCredentials(GoogleCredentials.fromStream(stream))
                .build(),"guardian-fcm");
        } catch(Exception ex) {
            throw new IllegalStateException("Could not initialize Firebase service credentials",ex);
        }
    }

    private String encrypt(String token) {
        if (encryptionKey==null) throw new ResponseStatusException(
            HttpStatus.SERVICE_UNAVAILABLE,"Notificaciones push no configuradas");
        try {
            byte[] iv=new byte[12]; random.nextBytes(iv);
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(encryptionKey,"AES"),
                new GCMParameterSpec(128,iv));
            byte[] encrypted=cipher.doFinal(token.getBytes(StandardCharsets.UTF_8));
            byte[] joined=new byte[iv.length+encrypted.length];
            System.arraycopy(iv,0,joined,0,iv.length);
            System.arraycopy(encrypted,0,joined,iv.length,encrypted.length);
            return Base64.getEncoder().encodeToString(joined);
        } catch(Exception ex) {
            throw new IllegalStateException("Could not encrypt push token",ex);
        }
    }

    private String decrypt(String encrypted) {
        try {
            byte[] joined=Base64.getDecoder().decode(encrypted);
            if(joined.length<29) throw new IllegalArgumentException("Malformed token");
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(encryptionKey,"AES"),
                new GCMParameterSpec(128,java.util.Arrays.copyOf(joined,12)));
            return new String(cipher.doFinal(joined,12,joined.length-12),
                StandardCharsets.UTF_8);
        } catch(Exception ex) { throw new IllegalStateException("Invalid encrypted push token",ex); }
    }

    public void register(UUID accountId,String token,String platform) {
        if(app==null || encryptionKey==null) throw new ResponseStatusException(
            HttpStatus.SERVICE_UNAVAILABLE,"Configura las credenciales Firebase del servidor");
        if(token.length()>4096) throw new ResponseStatusException(
            HttpStatus.BAD_REQUEST,"Token inválido");
        if(!List.of("ANDROID","IOS").contains(platform)) throw new ResponseStatusException(
            HttpStatus.BAD_REQUEST,"Plataforma inválida");
        jdbc.update("""
            INSERT INTO push_registration
                (guardian_account_id, token_hash, token_ciphertext, platform)
            VALUES (?, ?, ?, ?)
            ON CONFLICT (token_hash) DO UPDATE SET
                guardian_account_id = EXCLUDED.guardian_account_id,
                token_ciphertext = EXCLUDED.token_ciphertext,
                platform = EXCLUDED.platform,
                revoked_at = NULL
            """,accountId,auth.digestForCredential(token),encrypt(token),platform);
    }

    public void unregister(UUID accountId,String token) {
        jdbc.update("""
            UPDATE push_registration SET revoked_at = now(), token_ciphertext = NULL
            WHERE guardian_account_id = ? AND token_hash = ?
            """,accountId,auth.digestForCredential(token));
    }

    public record Delivery(UUID owner, String type, String title, String body, UUID challengeId) {}

    @Async
    @TransactionalEventListener(phase=TransactionPhase.AFTER_COMMIT)
    public void send(Delivery delivery) {
        if(app==null || encryptionKey==null) return;
        List<String> encryptedTokens=jdbc.query("""
            SELECT token_ciphertext FROM push_registration
            WHERE guardian_account_id = ? AND revoked_at IS NULL
              AND token_ciphertext IS NOT NULL
            """,(rs,i)->rs.getString(1),delivery.owner());
        for(String encrypted:encryptedTokens) {
            try {
                String token=decrypt(encrypted);
                Message.Builder message=Message.builder()
                    .setToken(token)
                    .setNotification(Notification.builder()
                        .setTitle(delivery.title())
                        .setBody(delivery.body())
                        .build())
                    .setAndroidConfig(AndroidConfig.builder().setPriority(
                        AndroidConfig.Priority.HIGH).build())
                    .putData("type",delivery.type());
                if(delivery.challengeId()!=null)
                    message.putData("challengeId",delivery.challengeId().toString());
                FirebaseMessaging.getInstance(app).send(message.build());
            } catch(Exception e) {
                org.slf4j.LoggerFactory.getLogger(getClass()).warn(
                    "Error enviando push; la notificación permanece en Guardian");
            }
        }
    }
}

@EnableAsync
@org.springframework.context.annotation.Configuration
class GuardianAsyncConfiguration { }

@RestController
@RequestMapping("/api/v1/push")
class PushController {
    private final PushService push;
    PushController(PushService push) { this.push=push; }

    public record Registration(@NotBlank String token,@NotBlank String platform) {}
    public record Unregistration(@NotBlank String token) {}

    @PostMapping("/register")
    public Map<String,Boolean> register(
        @org.springframework.security.core.annotation.AuthenticationPrincipal
        AuthPrincipal principal,@Valid @RequestBody Registration data) {
        push.register(principal.accountId(),data.token(),data.platform());
        return Map.of("registered",true);
    }
    @PostMapping("/unregister")
    public Map<String,Boolean> unregister(
        @org.springframework.security.core.annotation.AuthenticationPrincipal
        AuthPrincipal principal,@Valid @RequestBody Unregistration data) {
        push.unregister(principal.accountId(),data.token());
        return Map.of("unregistered",true);
    }
}