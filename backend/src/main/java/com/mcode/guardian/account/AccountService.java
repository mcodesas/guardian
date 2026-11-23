package com.mcode.guardian.account;

import com.mcode.guardian.auth.AuthPrincipal;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Locale;
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
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** Account lifecycle. All account mutations are tied to the authenticated subject. */
@Service
public class AccountService {
    private static final SecureRandom RNG = new SecureRandom();
    private static final String GENERIC_CODE_ERROR = "Código incorrecto o vencido";
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwords;
    private final JavaMailSender mail;
    private final String from;
    private final String pepper;

    public AccountService(JdbcTemplate jdbc, PasswordEncoder passwords,
                          ObjectProvider<JavaMailSender> mail,
                          @Value("${guardian.auth.mail-from:}") String from,
                          @Value("${guardian.auth.pepper}") String pepper) {
        this.jdbc = jdbc;
        this.passwords = passwords;
        this.mail = mail.getIfAvailable();
        this.from = from;
        this.pepper = pepper;
    }

    public static String normalizedEmail(String email) {
        if (email == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Correo requerido");
        String result = email.strip().toLowerCase(Locale.ROOT);
        if (result.length() > 320 || !result.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Correo electrónico inválido");
        }
        return result;
    }

    private void requireActive(UUID id) {
        Integer active = jdbc.queryForObject("SELECT count(*) FROM guardian_account " +
                        "WHERE id = ? AND disabled_at IS NULL", Integer.class, id);
        if (active == null || active != 1) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Cuenta desactivada");
        }
    }

    private void validatePassword(String password) {
        if (password == null || password.length() < 12 || password.length() > 128) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "La contraseña debe tener entre 12 y 128 caracteres");
        }
    }

    private void passwordMatches(UUID accountId, String actual) {
        List<String> hashes = jdbc.query("SELECT password_hash FROM guardian_account WHERE id = ? " +
                "AND disabled_at IS NULL FOR UPDATE", (rs, index) -> rs.getString(1), accountId);
        if (hashes.isEmpty() || actual == null || !passwords.matches(actual, hashes.get(0))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Contraseña actual incorrecta");
        }
    }

    private void sendCode(String to, String subject, String code) {
        if (mail == null || from.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Configura SMTP para las operaciones de cuenta");
        }
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(to);
        message.setSubject("Guardian | " + subject);
        message.setText("Código de seguridad: " + code +
                "\nCaduca en 10 minutos. Nunca lo compartas. " +
                "Si no reconoces la solicitud, cambia tu contraseña.");
        try { mail.send(message); }
        catch (RuntimeException ex) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "No fue posible enviar el código de seguridad", ex);
        }
    }

    private String newCode() { return String.format("%06d", RNG.nextInt(1_000_000)); }
    private String encodeCode(String code) { return passwords.encode(code + pepper); }
    private boolean validCode(String code, String hash, Object expiry, Number attempts) {
        return code != null && code.matches("[0-9]{6}") && hash != null && expiry != null
                && attempts.intValue() < 5
                && Instant.now().isBefore(((java.sql.Timestamp)expiry).toInstant())
                && passwords.matches(code + pepper, hash);
    }
    private boolean canSend(Object previous) {
        return previous == null || !Instant.now().isBefore(
                ((java.sql.Timestamp)previous).toInstant().plusSeconds(60));
    }

    public Map<String,Object> profile(AuthPrincipal principal) {
        requireActive(principal.accountId());
        return jdbc.queryForObject("""
            SELECT id, email, display_name, phone_number, email_verified
            FROM guardian_account WHERE id = ?
            """, (rs, idx) -> {
                Map<String,Object> data = new java.util.LinkedHashMap<>();
                data.put("id", rs.getString("id"));
                data.put("email", rs.getString("email"));
                data.put("name", rs.getString("display_name"));
                data.put("phone", rs.getString("phone_number"));
                data.put("verified", rs.getBoolean("email_verified"));
                return data;
            }, principal.accountId());
    }

    @Transactional
    public Map<String,Object> updateProfile(AuthPrincipal principal, String name, String phone) {
        requireActive(principal.accountId());
        String trimmed = name == null ? "" : name.strip();
        String cleanedPhone = phone == null || phone.isBlank() ? null : phone.strip();
        if (trimmed.isEmpty() || trimmed.length() > 120
                || (cleanedPhone != null && (cleanedPhone.length() > 32 ||
                !cleanedPhone.matches("^[+0-9() .-]{7,32}$")))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Datos de perfil inválidos");
        }
        jdbc.update("UPDATE guardian_account SET display_name = ?, phone_number = ? WHERE id = ?",
                trimmed, cleanedPhone, principal.accountId());
        audit(principal.accountId(), principal.accountId(), "PROFILE_UPDATED");
        return profile(principal);
    }

    @Transactional
    public void changePassword(AuthPrincipal principal, String current, String proposed) {
        validatePassword(proposed);
        passwordMatches(principal.accountId(), current);
        if (passwords.matches(proposed, jdbc.queryForObject(
                "SELECT password_hash FROM guardian_account WHERE id = ?",
                String.class, principal.accountId()))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "La nueva contraseña debe ser diferente");
        }
        jdbc.update("UPDATE guardian_account SET password_hash = ? WHERE id = ?",
                passwords.encode(proposed), principal.accountId());
        revokeSessions(principal.accountId());
        audit(principal.accountId(), principal.accountId(), "PASSWORD_CHANGED");
    }

    public List<Map<String,Object>> sessions(AuthPrincipal principal) {
        requireActive(principal.accountId());
        return jdbc.query("""
            SELECT id, client_label, created_at, access_expires_at,
                   refresh_expires_at FROM auth_session
            WHERE guardian_account_id = ? AND revoked_at IS NULL
              AND refresh_expires_at > now() ORDER BY created_at DESC
            """, (rs, idx) -> Map.<String,Object>of(
                "id", rs.getString("id"),
                "clientLabel", rs.getString("client_label"),
                "createdAt", rs.getTimestamp("created_at").toInstant().toString(),
                "accessExpiresAt", rs.getTimestamp("access_expires_at").toInstant().toString(),
                "refreshExpiresAt", rs.getTimestamp("refresh_expires_at").toInstant().toString(),
                "current", principal.sessionId().equals(rs.getObject("id", UUID.class))
            ), principal.accountId());
    }

    @Transactional
    public void revokeSession(AuthPrincipal principal, UUID sessionId) {
        requireActive(principal.accountId());
        int n = jdbc.update("UPDATE auth_session SET revoked_at=now() WHERE id = ? " +
                "AND guardian_account_id = ? AND revoked_at IS NULL",
                sessionId, principal.accountId());
        if (n == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Sesión inexistente");
        audit(principal.accountId(), principal.accountId(), "SESSION_REVOKED");
    }

    @Transactional
    public void revokeOtherSessions(AuthPrincipal principal) {
        requireActive(principal.accountId());
        jdbc.update("UPDATE auth_session SET revoked_at=now() WHERE guardian_account_id=? " +
                "AND id<>? AND revoked_at IS NULL", principal.accountId(), principal.sessionId());
        audit(principal.accountId(), principal.accountId(), "OTHER_SESSIONS_REVOKED");
    }

    private void revokeSessions(UUID accountId) {
        jdbc.update("UPDATE auth_session SET revoked_at=now() WHERE guardian_account_id=? " +
                "AND revoked_at IS NULL", accountId);
    }

    @Transactional
    public void requestEmailChange(AuthPrincipal principal, String newEmail, String currentPassword) {
        requireActive(principal.accountId());
        passwordMatches(principal.accountId(), currentPassword);
        String email = normalizedEmail(newEmail);
        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT email, email_change_sent_at FROM guardian_account WHERE id = ? FOR UPDATE
            """, principal.accountId());
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        if (email.equals(rows.get(0).get("email"))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El correo ya está registrado");
        }
        Integer conflicts = jdbc.queryForObject("SELECT count(*) FROM guardian_account WHERE email = ?",
                Integer.class, email);
        if (conflicts != null && conflicts > 0)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Este correo ya tiene cuenta");
        if (!canSend(rows.get(0).get("email_change_sent_at"))) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Solicita otro código después de un minuto");
        }
        String code = newCode();
        jdbc.update("""
            UPDATE guardian_account SET email_change_to=?, email_change_code_hash=?,
               email_change_expires_at=?, email_change_attempts=0,
               email_change_sent_at=now() WHERE id=?
            """, email, encodeCode(code), Instant.now().plus(10, ChronoUnit.MINUTES),
                principal.accountId());
        sendCode(email, "Verificar nuevo correo", code);
        audit(principal.accountId(), principal.accountId(), "EMAIL_CHANGE_REQUESTED");
    }

    /** Returns false on invalid OTP so the failure counter can COMMIT. */
    @Transactional
    public boolean confirmEmailChange(AuthPrincipal principal, String code) {
        requireActive(principal.accountId());
        Map<String,Object> row = jdbc.queryForMap("""
            SELECT email_change_to, email_change_code_hash, email_change_expires_at,
                   email_change_attempts FROM guardian_account WHERE id=? FOR UPDATE
            """, principal.accountId());
        if (!validCode(code, (String)row.get("email_change_code_hash"),
                row.get("email_change_expires_at"),
                (Number)row.get("email_change_attempts"))) {
            jdbc.update("UPDATE guardian_account SET email_change_attempts=" +
                    "LEAST(email_change_attempts+1,5) WHERE id=? AND email_change_code_hash IS NOT NULL",
                    principal.accountId());
            return false;
        }
        String to = (String)row.get("email_change_to");
        if (to == null) return false;
        Integer exists = jdbc.queryForObject("SELECT count(*) FROM guardian_account WHERE email=?",
                Integer.class, to);
        if (exists != null && exists > 0) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "El correo ya se encuentra registrado");
        }
        jdbc.update("""
            UPDATE guardian_account SET email=?, email_verified=true,
              email_change_to=NULL, email_change_code_hash=NULL,
              email_change_expires_at=NULL, email_change_sent_at=NULL,
              email_change_attempts=0 WHERE id=?
            """, to, principal.accountId());
        revokeSessions(principal.accountId());
        audit(principal.accountId(), principal.accountId(), "EMAIL_CHANGED");
        return true;
    }

    @Transactional
    public void deactivate(AuthPrincipal principal, String password) {
        passwordMatches(principal.accountId(), password);
        UUID id=principal.accountId();
        jdbc.update("UPDATE guardian_account SET disabled_at=now() WHERE id=?", id);
        revokeSessions(id);
        jdbc.update("UPDATE mobile_credential SET revoked_at=now() WHERE guardian_account_id=? " +
                "AND revoked_at IS NULL", id);
        jdbc.update("UPDATE push_registration SET revoked_at=now(), token_ciphertext=NULL " +
                "WHERE guardian_account_id=?", id);
        jdbc.update("UPDATE agent_credential SET revoked_at=now() WHERE protected_device_id " +
                "IN (SELECT id FROM protected_device WHERE guardian_account_id=?)", id);
        jdbc.update("UPDATE approval_challenge SET state='CANCELLED', trust_until=NULL " +
                "WHERE state IN ('PENDING','APPROVED') AND protected_device_id " +
                "IN (SELECT id FROM protected_device WHERE guardian_account_id=?)", id);
        audit(id, id, "ACCOUNT_DEACTIVATED");
    }

    @Transactional
    public void requestReactivation(String emailRaw) {
        String email = normalizedEmail(emailRaw);
        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT id, reactivation_sent_at FROM guardian_account
            WHERE email=? AND disabled_at IS NOT NULL FOR UPDATE
            """, email);
        if (rows.isEmpty() || !canSend(rows.get(0).get("reactivation_sent_at"))) return;
        String code = newCode();
        jdbc.update("""
            UPDATE guardian_account SET reactivation_code_hash=?, reactivation_expires_at=?,
              reactivation_attempts=0, reactivation_sent_at=now() WHERE id=?
            """, encodeCode(code), Instant.now().plus(10, ChronoUnit.MINUTES),
                rows.get(0).get("id"));
        sendCode(email,"Reactivar tu cuenta",code);
    }

    @Transactional
    public boolean reactivate(String emailRaw, String code) {
        String email = normalizedEmail(emailRaw);
        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT id, reactivation_code_hash, reactivation_expires_at,
                   reactivation_attempts FROM guardian_account
            WHERE email=? AND disabled_at IS NOT NULL FOR UPDATE
            """, email);
        if(rows.isEmpty()) return false;
        Map<String,Object> row=rows.get(0);
        if(!validCode(code,(String)row.get("reactivation_code_hash"),
                row.get("reactivation_expires_at"),
                (Number)row.get("reactivation_attempts"))) {
            jdbc.update("UPDATE guardian_account SET reactivation_attempts=" +
                    "LEAST(reactivation_attempts+1,5) WHERE id=?", row.get("id"));
            return false;
        }
        jdbc.update("""
            UPDATE guardian_account SET disabled_at=NULL, reactivation_code_hash=NULL,
              reactivation_expires_at=NULL, reactivation_sent_at=NULL,
              reactivation_attempts=0 WHERE id=?
            """, row.get("id"));
        audit((UUID)row.get("id"), (UUID)row.get("id"), "ACCOUNT_REACTIVATED");
        // Device and mobile credentials remain revoked, must be re-enrolled.
        return true;
    }

    @Transactional
    public void requestDeletion(AuthPrincipal principal, String password) {
        passwordMatches(principal.accountId(), password);
        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT email, deletion_sent_at FROM guardian_account WHERE id=? FOR UPDATE
            """, principal.accountId());
        if(!canSend(rows.get(0).get("deletion_sent_at"))) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Solicita otro código después de un minuto");
        }
        String code=newCode();
        jdbc.update("""
            UPDATE guardian_account SET deletion_code_hash=?, deletion_expires_at=?,
              deletion_attempts=0, deletion_sent_at=now() WHERE id=?
            """, encodeCode(code),Instant.now().plus(10,ChronoUnit.MINUTES),
                principal.accountId());
        sendCode((String)rows.get(0).get("email"),"Confirmar eliminación definitiva",code);
        audit(principal.accountId(), principal.accountId(), "ACCOUNT_DELETION_REQUESTED");
    }

    /** Returns false for invalid attempts (rather than rolling back attempt counter). */
    @Transactional
    public boolean deleteAccount(AuthPrincipal principal, String code) {
        UUID id=principal.accountId();
        Map<String,Object> row=jdbc.queryForMap("""
            SELECT deletion_code_hash,deletion_expires_at,deletion_attempts,email
            FROM guardian_account WHERE id=? AND disabled_at IS NULL FOR UPDATE
            """,id);
        if(!validCode(code,(String)row.get("deletion_code_hash"),
                row.get("deletion_expires_at"),(Number)row.get("deletion_attempts"))) {
            jdbc.update("UPDATE guardian_account SET deletion_attempts=" +
                    "LEAST(deletion_attempts+1,5) WHERE id=?",id);
            return false;
        }
        // Explicit child-first deletion because V1-V4 FK constraints are not CASCADE.
        jdbc.update("""
            DELETE FROM notification_event WHERE guardian_account_id=?
              OR protected_device_id IN (SELECT id FROM protected_device WHERE guardian_account_id=?)
              OR approval_challenge_id IN (SELECT c.id FROM approval_challenge c
                   JOIN mobile_credential m ON m.id=c.decided_by_credential_id
                   WHERE m.guardian_account_id=?)
            """,id,id,id);
        jdbc.update("DELETE FROM push_registration WHERE guardian_account_id=? " +
                "OR mobile_credential_id IN " +
                "(SELECT id FROM mobile_credential WHERE guardian_account_id=?)",id,id);
        jdbc.update("""
            DELETE FROM approval_challenge WHERE protected_device_id IN
              (SELECT id FROM protected_device WHERE guardian_account_id=?)
              OR decided_by_credential_id IN
              (SELECT id FROM mobile_credential WHERE guardian_account_id=?)
            """,id,id);
        jdbc.update("DELETE FROM device_security_observation WHERE protected_device_id IN " +
                "(SELECT id FROM protected_device WHERE guardian_account_id=?)",id);
        jdbc.update("DELETE FROM security_incident WHERE protected_device_id IN " +
                "(SELECT id FROM protected_device WHERE guardian_account_id=?)",id);
        jdbc.update("DELETE FROM agent_credential WHERE protected_device_id IN " +
                "(SELECT id FROM protected_device WHERE guardian_account_id=?)",id);
        jdbc.update("DELETE FROM protected_device WHERE guardian_account_id=?",id);
        jdbc.update("DELETE FROM mobile_credential WHERE guardian_account_id=?",id);
        jdbc.update("DELETE FROM mobile_enrollment_challenge WHERE guardian_account_id=?",id);
        jdbc.update("DELETE FROM auth_session WHERE guardian_account_id=?",id);
        jdbc.update("DELETE FROM guardian_invitation WHERE owner_account_id=? OR " +
                "invited_by_account_id=? OR lower(email)=lower(?)",id,id,row.get("email"));
        jdbc.update("DELETE FROM guardian_membership WHERE owner_account_id=? OR member_account_id=?",id,id);
        jdbc.update("DELETE FROM guardian_account_audit WHERE owner_account_id=?",id);
        jdbc.update("DELETE FROM guardian_account WHERE id=?",id);
        // Client local DPAPI/Keychain biometric data and backups require separate erasure.
        return true;
    }

    void audit(UUID owner, UUID actor, String action) {
        jdbc.update("INSERT INTO guardian_account_audit(owner_account_id,actor_account_id,action) " +
                "VALUES (?,?,?)",owner,actor,action);
    }

    public static String invalidCodeMessage() { return GENERIC_CODE_ERROR; }
}
