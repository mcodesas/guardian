package com.mcode.guardian.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int ACCESS_MINUTES = 15;
    private static final int REFRESH_DAYS = 30;
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final JavaMailSender sender;
    private final String pepper;
    private final String mailFrom;

    public AuthService(JdbcTemplate jdbc, PasswordEncoder passwordEncoder,
                       ObjectProvider<JavaMailSender> mailSender,
                       @Value("${guardian.auth.pepper}") String pepper,
                       @Value("${guardian.auth.mail-from:}") String mailFrom) {
        if (pepper.length() < 32) throw new IllegalStateException("GUARDIAN_AUTH_PEPPER must contain at least 32 characters");
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.sender = mailSender.getIfAvailable();
        this.pepper = pepper;
        this.mailFrom = mailFrom;
    }

    public static String normalizedEmail(String email) {
        return email.trim().toLowerCase(java.util.Locale.ROOT);
    }

    private String token() {
        byte[] value = new byte[32];
        RANDOM.nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    private String digest(String value) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(pepper.getBytes(StandardCharsets.UTF_8));
            md.update((byte) 0);
            md.update(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(md.digest());
        } catch (Exception e) {
            throw new IllegalStateException("Could not hash secret", e);
        }
    }

    public String digestForCredential(String credential) { return digest(credential); }

    private String newCode() {
        return String.format("%06d", RANDOM.nextInt(1_000_000));
    }

    private void sendCode(String email, String code) {
        if (sender == null || mailFrom.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Correo SMTP no configurado. Define GUARDIAN_SMTP_HOST y GUARDIAN_MAIL_FROM.");
        }
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(mailFrom);
        message.setTo(email);
        message.setSubject("Guardian | Verifica tu cuenta");
        message.setText("Tu código de Guardian es: " + code +
            "\nVence en 10 minutos. Si no solicitaste este registro, ignora el mensaje.");
        try {
            sender.send(message);
        } catch (RuntimeException ex) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "No se pudo enviar el código de verificación", ex);
        }
    }

    @Transactional
    public void register(String emailRaw, String password, String name) {
        String email = normalizedEmail(emailRaw);
        if (password.length() < 12 || password.length() > 128) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "La contraseña debe tener entre 12 y 128 caracteres");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM guardian_account WHERE email = ?",
                Integer.class, email) > 0) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "El correo ya está registrado");
        }
        String code = newCode();
        jdbc.update("""
            INSERT INTO guardian_account(email, display_name, password_hash,
              verification_code_hash, verification_expires_at, verification_sent_at)
            VALUES (?, ?, ?, ?, ?, now())
            """, email, name.trim(), passwordEncoder.encode(password),
            passwordEncoder.encode(code + pepper), Instant.now().plus(10, ChronoUnit.MINUTES));
        sendCode(email, code);
    }

    @Transactional
    public void verify(String emailRaw, String code) {
        String email = normalizedEmail(emailRaw);
        List<Map<String,Object>> found = jdbc.queryForList("""
            SELECT id, verification_code_hash, verification_expires_at,
                   verification_attempts, email_verified
            FROM guardian_account WHERE email = ? FOR UPDATE
            """, email);
        if (found.isEmpty()) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Código inválido o vencido");
        Map<String,Object> row = found.get(0);
        if (Boolean.TRUE.equals(row.get("email_verified"))) return;
        Instant expiry = row.get("verification_expires_at") == null
            ? Instant.EPOCH : ((java.sql.Timestamp) row.get("verification_expires_at")).toInstant();
        int attempts = ((Number) row.get("verification_attempts")).intValue();
        UUID accountId = (UUID) row.get("id");
        if (attempts >= 5 || !Instant.now().isBefore(expiry)
            || row.get("verification_code_hash") == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Código inválido o vencido");
        }
        if (!passwordEncoder.matches(code + pepper, (String) row.get("verification_code_hash"))) {
            jdbc.update("UPDATE guardian_account SET verification_attempts = verification_attempts + 1 WHERE id = ?", accountId);
            return; // The controller signals an error outside the transaction to preserve attempt tracking.
        }
        jdbc.update("""
            UPDATE guardian_account SET email_verified = true, verification_code_hash = NULL,
                verification_expires_at = NULL, verification_attempts = 0 WHERE id = ?
            """, accountId);
    }

    @Transactional
    public boolean verifyCode(String email, String code) {
        // Using a boolean prevents marking a failed attempt as rolled back by an exception.
        String normalized = normalizedEmail(email);
        List<Map<String,Object>> found = jdbc.queryForList("""
            SELECT id, verification_code_hash, verification_expires_at,
                   verification_attempts, email_verified
            FROM guardian_account WHERE email = ? FOR UPDATE
            """, normalized);
        if (found.isEmpty()) return false;
        Map<String,Object> row = found.get(0);
        if (Boolean.TRUE.equals(row.get("email_verified"))) return true;
        if (row.get("verification_code_hash") == null || row.get("verification_expires_at") == null
            || ((Number) row.get("verification_attempts")).intValue() >= 5) return false;
        if (!Instant.now().isBefore(((java.sql.Timestamp) row.get("verification_expires_at")).toInstant())) return false;
        UUID accountId = (UUID)row.get("id");
        if (!passwordEncoder.matches(code + pepper, (String)row.get("verification_code_hash"))) {
            jdbc.update("UPDATE guardian_account SET verification_attempts = verification_attempts + 1 WHERE id = ?", accountId);
            return false;
        }
        jdbc.update("""
            UPDATE guardian_account SET email_verified = true, verification_code_hash = NULL,
                verification_expires_at = NULL, verification_attempts = 0 WHERE id = ?
            """, accountId);
        return true;
    }

    @Transactional
    public Map<String,Object> login(String emailRaw, String password, String clientLabel) {
        String email = normalizedEmail(emailRaw);
        List<Map<String,Object>> found = jdbc.queryForList("""
            SELECT id, password_hash, email_verified, display_name, failed_login_attempts, locked_until
            FROM guardian_account WHERE email = ? FOR UPDATE
            """, email);
        if (found.isEmpty()) throw unauthenticated();
        Map<String,Object> row = found.get(0);
        UUID id = (UUID)row.get("id");
        boolean locked = row.get("locked_until") != null
            && Instant.now().isBefore(((java.sql.Timestamp)row.get("locked_until")).toInstant());
        boolean valid = passwordEncoder.matches(password, (String)row.get("password_hash"));
        if (locked || !valid) {
            if (!locked) {
                int failures = ((Number)row.get("failed_login_attempts")).intValue() + 1;
                jdbc.update("UPDATE guardian_account SET failed_login_attempts = ?, locked_until = ? WHERE id = ?",
                    failures, failures >= 5 ? Instant.now().plus(15, ChronoUnit.MINUTES) : null, id);
            }
            return Map.of("authenticationFailed", true);
        }
        if (!Boolean.TRUE.equals(row.get("email_verified"))) {
            return Map.of("verificationRequired", true);
        }
        jdbc.update("UPDATE guardian_account SET failed_login_attempts = 0, locked_until = NULL WHERE id = ?", id);
        return issueTokens(id, clientLabel);
    }

    private Map<String,Object> issueTokens(UUID id, String clientLabel) {
        String access = token();
        String refresh = token();
        Instant accessExpiry = Instant.now().plus(ACCESS_MINUTES, ChronoUnit.MINUTES);
        Instant refreshExpiry = Instant.now().plus(REFRESH_DAYS, ChronoUnit.DAYS);
        jdbc.update("""
            INSERT INTO auth_session (guardian_account_id, access_token_hash,
                refresh_token_hash, access_expires_at, refresh_expires_at, client_label)
            VALUES (?, ?, ?, ?, ?, ?)
            """, id, digest(access), digest(refresh), accessExpiry, refreshExpiry,
            clientLabel == null ? "" : clientLabel.substring(0, Math.min(clientLabel.length(), 120)));
        return Map.of("accessToken", access, "refreshToken", refresh,
            "accessExpiresAt", accessExpiry.toString());
    }

    @Transactional
    public Map<String,Object> refresh(String oldRefresh) {
        List<Map<String,Object>> found = jdbc.queryForList("""
            SELECT id, guardian_account_id FROM auth_session
            WHERE refresh_token_hash = ? AND revoked_at IS NULL AND refresh_expires_at > now()
            FOR UPDATE
            """, digest(oldRefresh));
        if (found.isEmpty()) throw unauthenticated();
        UUID sessionId = (UUID) found.get(0).get("id");
        UUID accountId = (UUID) found.get(0).get("guardian_account_id");
        String access = token(), refresh = token();
        Instant accessExpiry = Instant.now().plus(ACCESS_MINUTES, ChronoUnit.MINUTES);
        Instant refreshExpiry = Instant.now().plus(REFRESH_DAYS, ChronoUnit.DAYS);
        jdbc.update("""
            UPDATE auth_session SET access_token_hash = ?, refresh_token_hash = ?,
                access_expires_at = ?, refresh_expires_at = ?
            WHERE id = ?
            """, digest(access), digest(refresh), accessExpiry, refreshExpiry, sessionId);
        return Map.of("accessToken", access, "refreshToken", refresh,
            "accessExpiresAt", accessExpiry.toString(), "accountId", accountId.toString());
    }

    public Optional<AuthPrincipal> findPrincipal(String access) {
        if (access == null || access.length() > 128) return Optional.empty();
        List<AuthPrincipal> matches = jdbc.query("""
            SELECT s.id session_id, a.id account_id, a.email
            FROM auth_session s JOIN guardian_account a ON a.id = s.guardian_account_id
            WHERE s.access_token_hash = ? AND s.access_expires_at > now()
              AND s.revoked_at IS NULL AND a.email_verified = true
            """, (rs, i) -> new AuthPrincipal(
                rs.getObject("account_id", UUID.class),
                rs.getObject("session_id", UUID.class),
                rs.getString("email")), digest(access));
        return matches.stream().findFirst();
    }

    public Map<String,Object> me(AuthPrincipal principal) {
        return jdbc.queryForObject("""
            SELECT id, email, display_name, email_verified FROM guardian_account WHERE id = ?
            """, (rs, i) -> Map.<String,Object>of(
                "id", rs.getString("id"), "email", rs.getString("email"),
                "name", rs.getString("display_name"), "verified", rs.getBoolean("email_verified")),
            principal.accountId());
    }

    @Transactional
    public void logout(AuthPrincipal principal) {
        jdbc.update("UPDATE auth_session SET revoked_at = now() WHERE id = ? AND guardian_account_id = ?",
            principal.sessionId(), principal.accountId());
    }

    public static ResponseStatusException unauthenticated() {
        return new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Credenciales inválidas");
    }
}