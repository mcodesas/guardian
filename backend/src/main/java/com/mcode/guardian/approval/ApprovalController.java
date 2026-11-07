package com.mcode.guardian.approval;

import com.mcode.guardian.auth.AuthPrincipal;
import com.mcode.guardian.notification.NotificationService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1")
public class ApprovalController {
    private final JdbcTemplate jdbc;
    private final ApprovalSignature verifier;
    private final NotificationService notifications;

    public ApprovalController(JdbcTemplate jdbc, ApprovalSignature verifier,
                              NotificationService notifications) {
        this.jdbc = jdbc;
        this.verifier = verifier;
        this.notifications = notifications;
    }

    public record CredentialRequest(@NotBlank String publicKey, @NotBlank String platform,
                                    @NotBlank String label) {}
    public record DecisionRequest(@NotNull UUID credentialId, @NotBlank String decision,
                                  @NotNull Integer trustMinutes, @NotBlank String signature) {}

    @PostMapping("/mobile/credentials")
    @Transactional
    public Map<String,String> registerCredential(@AuthenticationPrincipal AuthPrincipal principal,
                                                 @Valid @RequestBody CredentialRequest body) {
        if (!List.of("ANDROID","IOS").contains(body.platform()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Registra la clave desde un móvil");
        try {
            if (Base64.getDecoder().decode(body.publicKey()).length != 32) throw new Exception();
        } catch (Exception ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Clave pública Ed25519 inválida");
        }
        UUID id = UUID.randomUUID();
        jdbc.update("""
            INSERT INTO mobile_credential (id, guardian_account_id, credential_id, public_key, platform)
            VALUES (?, ?, ?, ?, ?)
            """, id, principal.accountId(), id.toString(), body.publicKey(), body.platform());
        return Map.of("credentialId", id.toString());
    }

    @GetMapping("/mobile/credentials")
    public List<Map<String,Object>> credentials(@AuthenticationPrincipal AuthPrincipal principal) {
        return jdbc.query("""
            SELECT id, platform, created_at FROM mobile_credential
            WHERE guardian_account_id = ? AND revoked_at IS NULL ORDER BY created_at DESC
            """, (rs, row) -> Map.<String,Object>of(
                "id", rs.getString("id"), "platform", rs.getString("platform"),
                "createdAt", rs.getTimestamp("created_at").toInstant().toString()),
            principal.accountId());
    }

    @DeleteMapping("/mobile/credentials/{id}")
    public Map<String,Boolean> revoke(@AuthenticationPrincipal AuthPrincipal principal,
                                      @PathVariable UUID id) {
        int n = jdbc.update("""
            UPDATE mobile_credential SET revoked_at = now() WHERE id = ?
            AND guardian_account_id = ? AND revoked_at IS NULL
            """, id, principal.accountId());
        if (n == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Credencial no encontrada");
        return Map.of("revoked", true);
    }

    @GetMapping("/approvals")
    public List<Map<String,Object>> approvals(@AuthenticationPrincipal AuthPrincipal principal) {
        return jdbc.query("""
            SELECT c.id, c.challenge_nonce, c.state, c.expires_at, c.created_at, c.trust_until,
                   d.display_name, d.platform
            FROM approval_challenge c JOIN protected_device d ON d.id = c.protected_device_id
            WHERE d.guardian_account_id = ? AND d.revoked_at IS NULL
            ORDER BY c.created_at DESC LIMIT 100
            """, (rs, i) -> {
                Map<String,Object> m = new java.util.LinkedHashMap<>();
                m.put("id", rs.getString("id"));
                m.put("nonce", rs.getString("challenge_nonce"));
                m.put("state", rs.getString("state"));
                m.put("expiresAt", rs.getTimestamp("expires_at").toInstant().toString());
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                m.put("trustUntil", rs.getTimestamp("trust_until") == null ?
                    null : rs.getTimestamp("trust_until").toInstant().toString());
                m.put("deviceName", rs.getString("display_name"));
                m.put("platform", rs.getString("platform"));
                return m;
            }, principal.accountId());
    }

    @PostMapping("/approvals/{challengeId}/decision")
    @Transactional
    public Map<String,Object> decide(@AuthenticationPrincipal AuthPrincipal principal,
                                     @PathVariable UUID challengeId,
                                     @Valid @RequestBody DecisionRequest body) {
        if (!List.of("APPROVED", "REJECTED").contains(body.decision()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Decisión inválida");
        int minutes = body.trustMinutes();
        if ("APPROVED".equals(body.decision()) && !List.of(5,15,30).contains(minutes))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Duración no permitida");
        if ("REJECTED".equals(body.decision()) && minutes != 0)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Rechazar no permite duración");

        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT c.challenge_nonce, c.state, c.expires_at, c.protected_device_id,
                   d.display_name FROM approval_challenge c
            JOIN protected_device d ON d.id = c.protected_device_id
            WHERE c.id = ? AND d.guardian_account_id = ? AND d.revoked_at IS NULL FOR UPDATE OF c
            """, challengeId, principal.accountId());
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Solicitud no encontrada");
        Map<String,Object> challenge = rows.get(0);
        if (!"PENDING".equals(challenge.get("state")) ||
            !Instant.now().isBefore(((java.sql.Timestamp)challenge.get("expires_at")).toInstant())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Solicitud vencida o decidida");
        }
        List<String> keys = jdbc.query("""
            SELECT public_key FROM mobile_credential WHERE id = ? AND guardian_account_id = ?
            AND revoked_at IS NULL
            """, (rs, i) -> rs.getString(1), body.credentialId(), principal.accountId());
        if (keys.isEmpty()) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Móvil no autorizado");
        String canonical = ApprovalSignature.canonical(challengeId,
            (String) challenge.get("challenge_nonce"), body.decision(), minutes);
        if (!verifier.verify(keys.get(0), body.signature(), canonical))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Firma inválida");
        Instant until = "APPROVED".equals(body.decision())
            ? Instant.now().plus(minutes, ChronoUnit.MINUTES) : null;
        jdbc.update("""
            UPDATE approval_challenge SET state = ?, decided_at = now(),
                decided_by_credential_id = ?, trust_until = ? WHERE id = ?
            """, body.decision(), body.credentialId(), until, challengeId);
        notifications.publish(principal.accountId(), (UUID)challenge.get("protected_device_id"),
            challengeId, null, "APPROVAL_DECIDED",
            "APPROVED".equals(body.decision()) ? "Acceso autorizado" : "Acceso rechazado",
            "Decisión registrada para " + challenge.get("display_name"));
        Map<String,Object> result = new java.util.LinkedHashMap<>();
        result.put("state", body.decision());
        result.put("trustUntil", until == null ? null : until.toString());
        return result;
    }
}