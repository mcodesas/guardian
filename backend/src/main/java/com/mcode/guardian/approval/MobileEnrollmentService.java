package com.mcode.guardian.approval;

import com.mcode.guardian.auth.AuthPrincipal;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Secondary verification for enrolling new mobile signing credentials.
 *
 * Enrollment codes are tied to the logged-in SESSION, so a code from one
 * device cannot be replayed from a different authenticated session.
 * Failed attempts commit in a distinct transaction before the controller
 * returns an error, preventing rollback of the attempt counter.
 */
@Service
public class MobileEnrollmentService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwords;
    private final JavaMailSender sender;
    private final String from;
    private final String pepper;

    public MobileEnrollmentService(JdbcTemplate jdbc, PasswordEncoder passwords,
            ObjectProvider<JavaMailSender> mailProvider,
            @Value("${guardian.auth.mail-from:}") String from,
            @Value("${guardian.auth.pepper}") String pepper) {
        this.jdbc = jdbc;
        this.passwords = passwords;
        this.sender = mailProvider.getIfAvailable();
        this.from = from;
        this.pepper = pepper;
    }

    @Transactional
    public void sendEnrollmentCode(AuthPrincipal principal) {
        if (sender == null || from.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Configura SMTP antes de vincular un móvil");
        }
        List<String> emailRows = jdbc.query("""
                SELECT email FROM guardian_account
                WHERE id = ? AND email_verified = true FOR UPDATE
                """, (rs, index) -> rs.getString(1), principal.accountId());
        if (emailRows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Cuenta no verificada");
        }

        Integer recent = jdbc.queryForObject("""
                SELECT count(*) FROM mobile_enrollment_challenge
                WHERE guardian_account_id = ?
                  AND requested_at > now() - interval '60 seconds'
                """, Integer.class, principal.accountId());
        if (recent != null && recent > 0) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Ya solicitaste un código. Intenta de nuevo después de un minuto");
        }
        Integer hourly = jdbc.queryForObject("""
                SELECT count(*) FROM mobile_enrollment_challenge
                WHERE guardian_account_id = ?
                  AND requested_at > now() - interval '1 hour'
                """, Integer.class, principal.accountId());
        if (hourly != null && hourly >= 8) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Límite de vinculaciones alcanzado temporalmente");
        }

        String code = String.format("%06d", RANDOM.nextInt(1_000_000));
        jdbc.update("""
                INSERT INTO mobile_enrollment_challenge
                    (guardian_account_id, requested_by_session, code_hash, expires_at)
                VALUES (?, ?, ?, ?)
                """, principal.accountId(), principal.sessionId(),
                passwords.encode(code + pepper), Instant.now().plus(10, ChronoUnit.MINUTES));

        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(emailRows.get(0));
        message.setSubject("Guardian | Autorizar nuevo teléfono");
        message.setText("""
                Se ha solicitado vincular un teléfono que podrá aprobar accesos a tus computadores.

                Código de verificación: %s

                Vence en 10 minutos. No lo compartas. Si no reconoces la solicitud,
                cambia tu contraseña Guardian y revisa las sesiones activas.
                """.formatted(code));
        try {
            sender.send(message);
        } catch (RuntimeException ex) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "No se pudo enviar el código; verifica el SMTP", ex);
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean consumeCode(AuthPrincipal principal, String code) {
        if (code == null || !code.matches("[0-9]{6}")) return false;
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, code_hash, expires_at, attempts
                FROM mobile_enrollment_challenge
                WHERE guardian_account_id = ? AND requested_by_session = ?
                  AND consumed_at IS NULL
                ORDER BY requested_at DESC LIMIT 1 FOR UPDATE
                """, principal.accountId(), principal.sessionId());
        if (rows.isEmpty()) return false;
        Map<String, Object> row = rows.get(0);
        if (((Number)row.get("attempts")).intValue() >= 5) return false;
        Instant expiry = ((java.sql.Timestamp)row.get("expires_at")).toInstant();
        if (!Instant.now().isBefore(expiry)) return false;

        UUID challengeId = (UUID)row.get("id");
        if (!passwords.matches(code + pepper, (String)row.get("code_hash"))) {
            jdbc.update("""
                    UPDATE mobile_enrollment_challenge SET attempts = attempts + 1
                    WHERE id = ? AND attempts < 5
                    """, challengeId);
            return false;
        }
        return jdbc.update("""
                UPDATE mobile_enrollment_challenge SET consumed_at = now()
                WHERE id = ? AND consumed_at IS NULL
                """, challengeId) == 1;
    }
}
