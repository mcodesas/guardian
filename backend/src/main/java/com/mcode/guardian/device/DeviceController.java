package com.mcode.guardian.device;

import com.mcode.guardian.auth.AuthPrincipal;
import com.mcode.guardian.auth.AuthService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.security.SecureRandom;
import java.time.Instant;
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
@RequestMapping("/api/v1/devices")
public class DeviceController {
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final SecureRandom random = new SecureRandom();

    public DeviceController(JdbcTemplate jdbc, AuthService auth) {
        this.jdbc = jdbc;
        this.auth = auth;
    }

    public record CreateDevice(@NotBlank @Size(max=160) String name, @NotBlank String platform) {}
    public record PolicyUpdate(@NotNull Boolean lockOnAway, @NotNull Integer awayTimeoutSeconds,
                               @NotNull Boolean allowRemoteApproval) {}

    @GetMapping
    public List<Map<String,Object>> list(@AuthenticationPrincipal AuthPrincipal principal) {
        return jdbc.query("""
            SELECT id, display_name, platform, registration_state, lock_on_away,
                   away_timeout_seconds, allow_remote_approval, last_seen_at
            FROM protected_device
            WHERE guardian_account_id = ? AND revoked_at IS NULL ORDER BY created_at DESC
            """, (rs, i) -> Map.<String,Object>of(
                "id", rs.getString("id"),
                "name", rs.getString("display_name"),
                "platform", rs.getString("platform"),
                "state", rs.getString("registration_state"),
                "lockOnAway", rs.getBoolean("lock_on_away"),
                "awayTimeoutSeconds", rs.getInt("away_timeout_seconds"),
                "allowRemoteApproval", rs.getBoolean("allow_remote_approval"),
                "lastSeenAt", rs.getTimestamp("last_seen_at") == null
                    ? "" : rs.getTimestamp("last_seen_at").toInstant().toString()),
            principal.accountId());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Map<String,Object> create(@AuthenticationPrincipal AuthPrincipal principal,
                                     @Valid @RequestBody CreateDevice body) {
        String platform = body.platform().toUpperCase(java.util.Locale.ROOT);
        if (!List.of("WINDOWS", "MACOS", "LINUX").contains(platform))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Solo se registran computadores protegidos en esta fase");
        UUID id = UUID.randomUUID();
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String secret = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        jdbc.update("""
            INSERT INTO protected_device(id, guardian_account_id, display_name, platform)
            VALUES (?, ?, ?, ?)
            """, id, principal.accountId(), body.name().trim(), platform);
        jdbc.update("""
            INSERT INTO agent_credential(protected_device_id, secret_hash)
            VALUES (?, ?)
            """, id, auth.digestForCredential(secret));
        return Map.of("id", id.toString(), "state", "UNPAIRED",
            "agentKey", secret, "message",
            "Guarda la clave en el almacén seguro del agente. No volverá a mostrarse.");
    }

    @PatchMapping("/{id}/policy")
    public Map<String,Object> policy(@AuthenticationPrincipal AuthPrincipal principal,
                                     @PathVariable UUID id, @Valid @RequestBody PolicyUpdate body) {
        if (body.awayTimeoutSeconds() < 5 || body.awayTimeoutSeconds() > 300)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Intervalo entre 5 y 300 segundos");
        int updated = jdbc.update("""
            UPDATE protected_device SET lock_on_away = ?, away_timeout_seconds = ?,
                allow_remote_approval = ?
            WHERE id = ? AND guardian_account_id = ? AND revoked_at IS NULL
            """, body.lockOnAway(), body.awayTimeoutSeconds(), body.allowRemoteApproval(),
            id, principal.accountId());
        if (updated != 1) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Dispositivo no encontrado");
        return Map.of("updated",true);
    }

    @DeleteMapping("/{id}")
    @Transactional
    public Map<String,Object> revoke(@AuthenticationPrincipal AuthPrincipal principal, @PathVariable UUID id) {
        int updated = jdbc.update("""
            UPDATE protected_device SET revoked_at = now(), registration_state = 'REVOKED'
            WHERE id = ? AND guardian_account_id = ? AND revoked_at IS NULL
            """, id, principal.accountId());
        if (updated != 1) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Dispositivo no encontrado");
        jdbc.update("UPDATE agent_credential SET revoked_at = now() WHERE protected_device_id = ?", id);
        jdbc.update("""
            UPDATE approval_challenge SET state = 'CANCELLED'
            WHERE protected_device_id = ? AND state = 'PENDING'
            """, id);
        return Map.of("revoked",true);
    }
}