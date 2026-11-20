package com.mcode.guardian.notification;

import com.mcode.guardian.auth.AuthPrincipal;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/incidents")
public class IncidentController {
    private final JdbcTemplate jdbc;
    public IncidentController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @GetMapping
    public List<Map<String,Object>> list(@AuthenticationPrincipal AuthPrincipal principal) {
        return jdbc.query("""
            SELECT i.id, i.incident_type, i.occurred_at, i.details, d.display_name
            FROM security_incident i JOIN protected_device d ON d.id = i.protected_device_id
            WHERE d.guardian_account_id = ? ORDER BY i.occurred_at DESC LIMIT 100
            """, (rs, row) -> Map.<String,Object>of(
                "id",rs.getString("id"),
                "type",rs.getString("incident_type"),
                "occurredAt",rs.getTimestamp("occurred_at").toInstant().toString(),
                "deviceName",rs.getString("display_name"),
                "details",rs.getString("details")
            ), principal.accountId());
    }
}