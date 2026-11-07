package com.mcode.guardian.device;

import com.mcode.guardian.auth.AuthService;
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
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/agent")
public class AgentController {
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final NotificationService notifications;
    private final SecureRandom random = new SecureRandom();

    public AgentController(JdbcTemplate jdbc, AuthService auth, NotificationService notifications) {
        this.jdbc = jdbc;
        this.auth = auth;
        this.notifications = notifications;
    }

    private Map<String,Object> authorized(UUID deviceId, String key) {
        if (key == null || key.length() < 40 || key.length() > 128)
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Agente no autorizado");
        List<Map<String,Object>> found = jdbc.queryForList("""
            SELECT d.guardian_account_id, d.display_name, d.allow_remote_approval,
                   d.registration_state
            FROM agent_credential k JOIN protected_device d ON d.id = k.protected_device_id
            WHERE d.id = ? AND k.secret_hash = ? AND d.revoked_at IS NULL
              AND k.revoked_at IS NULL
            """, deviceId, auth.digestForCredential(key));
        if (found.isEmpty()) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Agente no autorizado");
        return found.get(0);
    }

    public record EventRequest(@NotBlank String type, @NotBlank String reason) {}
    public record ChallengeRequest(@NotNull UUID deviceId) {}

    @GetMapping("/{deviceId}/policy")
    public Map<String,Object> policy(@PathVariable UUID deviceId,
        @RequestHeader(value="X-Guardian-Agent-Key", required=false) String key) {
        authorized(deviceId,key);
        return jdbc.queryForObject("""
            SELECT lock_on_away, away_timeout_seconds, allow_remote_approval
            FROM protected_device WHERE id = ? AND revoked_at IS NULL
            """, (rs, i) -> Map.<String,Object>of(
                "lockOnAway",rs.getBoolean("lock_on_away"),
                "awayTimeoutSeconds",rs.getInt("away_timeout_seconds"),
                "allowRemoteApproval",rs.getBoolean("allow_remote_approval")), deviceId);
    }

    @PostMapping("/{deviceId}/activate")
    public Map<String,Object> activate(@PathVariable UUID deviceId,
        @RequestHeader(value="X-Guardian-Agent-Key", required=false) String key) {
        authorized(deviceId, key);
        jdbc.update("""
            UPDATE protected_device SET registration_state = 'PAIRED', last_seen_at = now()
            WHERE id = ? AND revoked_at IS NULL
            """, deviceId);
        return Map.of("paired",true);
    }

    @PostMapping("/{deviceId}/events")
    @Transactional
    public Map<String,Object> event(@PathVariable UUID deviceId,
        @RequestHeader(value="X-Guardian-Agent-Key", required=false) String key,
        @Valid @RequestBody EventRequest body) {
        Map<String,Object> agent = authorized(deviceId,key);
        if (!"PAIRED".equals(agent.get("registration_state")))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Agente sin activar");
        String type = body.type();
        if (!List.of("UNKNOWN_PERSON","NOT_VERIFIABLE","OWNER_ABSENT",
            "CAMERA_UNAVAILABLE","LOCK_FAILURE").contains(type))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Evento desconocido");
        UUID incidentId = UUID.randomUUID();
        String safeReason = body.reason().substring(0, Math.min(body.reason().length(), 500));
        jdbc.update("""
            INSERT INTO security_incident(id, protected_device_id, incident_type, occurred_at, details)
            VALUES (?, ?, ?, now(), jsonb_build_object('reason', ?::text))
            """, incidentId, deviceId, type, safeReason);
        jdbc.update("UPDATE protected_device SET last_seen_at = now() WHERE id = ?", deviceId);
        if ("UNKNOWN_PERSON".equals(type)) {
            jdbc.update("""
                UPDATE approval_challenge SET state = 'CANCELLED'
                WHERE protected_device_id = ? AND state IN ('PENDING','APPROVED')
                """, deviceId);
        }
        String title = "UNKNOWN_PERSON".equals(type) ? "Posible intrusión detectada"
            : "LOCK_FAILURE".equals(type) ? "No se pudo bloquear el equipo"
            : "Revisar seguridad del dispositivo";
        notifications.publish((UUID)agent.get("guardian_account_id"),deviceId,null,incidentId,
            "UNKNOWN_PERSON".equals(type) ? "INTRUSION" : "DEVICE_ATTENTION",
            title, (String)agent.get("display_name") + ": " + safeReason);
        return Map.of("incidentId", incidentId.toString(), "received",true);
    }

    @PostMapping("/{deviceId}/challenges")
    @Transactional
    public Map<String,Object> challenge(@PathVariable UUID deviceId,
        @RequestHeader(value="X-Guardian-Agent-Key", required=false) String key) {
        Map<String,Object> agent = authorized(deviceId,key);
        if (!"PAIRED".equals(agent.get("registration_state"))
            || !Boolean.TRUE.equals(agent.get("allow_remote_approval")))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Aprobación remota desactivada");
        int existing = jdbc.queryForObject("""
            SELECT count(*) FROM approval_challenge WHERE protected_device_id = ?
              AND created_at > now() - interval '1 minute'
            """, Integer.class, deviceId);
        if (existing >= 3)
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Límite de solicitudes");
        UUID id = UUID.randomUUID();
        byte[] nonceBytes = new byte[24];
        random.nextBytes(nonceBytes);
        String nonce = Base64.getUrlEncoder().withoutPadding().encodeToString(nonceBytes);
        Instant expires = Instant.now().plus(45,ChronoUnit.SECONDS);
        jdbc.update("""
            INSERT INTO approval_challenge (id, protected_device_id, nonce_hash,
                challenge_nonce, expires_at) VALUES (?, ?, ?, ?, ?)
            """, id, deviceId, auth.digestForCredential(nonce), nonce, expires);
        notifications.publish((UUID)agent.get("guardian_account_id"), deviceId,id,null,
            "APPROVAL_REQUIRED","¿Autorizas este acceso?",
            "No se pudo verificar el rostro en " + agent.get("display_name") +
            ". Aprueba solo si reconoces la solicitud.");
        return Map.of("challengeId",id.toString(),"expiresAt",expires.toString());
    }

    @GetMapping("/{deviceId}/challenges/{challengeId}")
    public Map<String,Object> status(@PathVariable UUID deviceId, @PathVariable UUID challengeId,
        @RequestHeader(value="X-Guardian-Agent-Key", required=false) String key) {
        authorized(deviceId,key);
        List<Map<String,Object>> result = jdbc.queryForList("""
            SELECT state, trust_until, expires_at FROM approval_challenge
            WHERE id = ? AND protected_device_id = ?
            """,challengeId,deviceId);
        if (result.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Solicitud no encontrada");
        Map<String,Object> row = result.get(0);
        String state = (String)row.get("state");
        if ("PENDING".equals(state) &&
            !Instant.now().isBefore(((java.sql.Timestamp)row.get("expires_at")).toInstant()))
            state = "EXPIRED";
        Map<String,Object> status = new java.util.LinkedHashMap<>();
        status.put("state",state);
        status.put("trustUntil",row.get("trust_until") == null ? null :
            ((java.sql.Timestamp)row.get("trust_until")).toInstant().toString());
        return status;
    }
}