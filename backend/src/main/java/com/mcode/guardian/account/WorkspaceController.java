package com.mcode.guardian.account;

import com.mcode.guardian.auth.AuthPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** Isolated read/write access for explicitly selected owner workspaces. */
@RestController
@RequestMapping("/api/v1/workspaces")
public class WorkspaceController {
    private final JdbcTemplate jdbc;
    private final AccountMembershipService members;
    public WorkspaceController(JdbcTemplate jdbc,AccountMembershipService members) {
        this.jdbc=jdbc; this.members=members;
    }

    public record Policy(@NotNull Boolean lockOnAway,
                         @NotNull Integer awayTimeoutSeconds,
                         @NotNull Boolean allowRemoteApproval) { }

    @GetMapping
    public List<Map<String,Object>> list(@AuthenticationPrincipal AuthPrincipal principal) {
        List<Map<String,Object>> result=new ArrayList<>();
        String ownRole=members.role(principal.accountId(),principal.accountId());
        if(!ownRole.equals("NONE")) result.add(workspace(principal.accountId(),"OWNER"));
        result.addAll(jdbc.query("""
            SELECT o.id,o.email,o.display_name,m.role FROM guardian_membership m
            JOIN guardian_account o ON o.id=m.owner_account_id
            WHERE m.member_account_id=? AND m.enabled=true
              AND o.disabled_at IS NULL
            ORDER BY m.joined_at DESC
            """,(rs,i)->Map.<String,Object>of(
                "ownerId",rs.getString("id"),
                "name",rs.getString("display_name"),
                "email",rs.getString("email"),
                "role",rs.getString("role")),principal.accountId()));
        return result;
    }

    private Map<String,Object> workspace(UUID owner,String role) {
        return jdbc.queryForObject("""
            SELECT id,display_name,email FROM guardian_account WHERE id=?
            """,(rs,i)->Map.<String,Object>of(
                "ownerId",rs.getString("id"),
                "name",rs.getString("display_name"),
                "email",rs.getString("email"),
                "role",role),owner);
    }

    @GetMapping("/{ownerId}/devices")
    public List<Map<String,Object>> devices(@AuthenticationPrincipal AuthPrincipal principal,
                                              @PathVariable UUID ownerId) {
        members.requireWorkspaceRead(principal.accountId(),ownerId);
        return jdbc.query("""
            SELECT id,display_name,platform,registration_state,lock_on_away,
              away_timeout_seconds,allow_remote_approval,last_seen_at
            FROM protected_device WHERE guardian_account_id=? AND revoked_at IS NULL
            ORDER BY created_at DESC
            """,(rs,i)-> {
                Map<String,Object> d=new java.util.LinkedHashMap<>();
                d.put("id",rs.getString("id"));
                d.put("name",rs.getString("display_name"));
                d.put("platform",rs.getString("platform"));
                d.put("state",rs.getString("registration_state"));
                d.put("lockOnAway",rs.getBoolean("lock_on_away"));
                d.put("awayTimeoutSeconds",rs.getInt("away_timeout_seconds"));
                d.put("allowRemoteApproval",rs.getBoolean("allow_remote_approval"));
                d.put("lastSeenAt",rs.getTimestamp("last_seen_at") == null ? null :
                        rs.getTimestamp("last_seen_at").toInstant().toString());
                return d;
            },ownerId);
    }

    @GetMapping("/{ownerId}/incidents")
    public List<Map<String,Object>> incidents(@AuthenticationPrincipal AuthPrincipal principal,
                                                @PathVariable UUID ownerId) {
        members.requireWorkspaceRead(principal.accountId(),ownerId);
        return jdbc.query("""
            SELECT i.id,i.incident_type,i.occurred_at,d.display_name
            FROM security_incident i JOIN protected_device d ON d.id=i.protected_device_id
            WHERE d.guardian_account_id=? ORDER BY i.occurred_at DESC LIMIT 100
            """,(rs,i)->Map.<String,Object>of(
                "id",rs.getString("id"),"type",rs.getString("incident_type"),
                "occurredAt",rs.getTimestamp("occurred_at").toInstant().toString(),
                "deviceName",rs.getString("display_name")),ownerId);
    }

    @PatchMapping("/{ownerId}/devices/{deviceId}/policy")
    @Transactional
    public Map<String,Boolean> updatePolicy(@AuthenticationPrincipal AuthPrincipal principal,
                                              @PathVariable UUID ownerId,
                                              @PathVariable UUID deviceId,
                                              @Valid @RequestBody Policy policy) {
        members.requireWorkspaceManage(principal.accountId(),ownerId);
        int seconds=policy.awayTimeoutSeconds();
        if(seconds<5 || seconds>300) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "El tiempo permitido es de 5 a 300 segundos");
        }
        int changed=jdbc.update("""
            UPDATE protected_device SET lock_on_away=?,away_timeout_seconds=?,
              allow_remote_approval=? WHERE id=? AND guardian_account_id=? AND revoked_at IS NULL
            """,policy.lockOnAway(),seconds,policy.allowRemoteApproval(),deviceId,ownerId);
        if(changed!=1) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Dispositivo no encontrado");
        return Map.of("updated",true);
    }
}
