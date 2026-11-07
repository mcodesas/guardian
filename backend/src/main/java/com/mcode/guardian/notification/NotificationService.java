package com.mcode.guardian.notification;

import com.mcode.guardian.auth.AuthPrincipal;
import jakarta.validation.constraints.NotBlank;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;

@Service
public class NotificationService {
    private final JdbcTemplate jdbc;
    private final JavaMailSender sender;
    private final String from;

    public NotificationService(JdbcTemplate jdbc, ObjectProvider<JavaMailSender> mail,
                               @Value("${guardian.auth.mail-from:}") String from) {
        this.jdbc = jdbc;
        this.sender = mail.getIfAvailable();
        this.from = from;
    }

    public void publish(UUID owner, UUID device, UUID challenge, UUID incident,
                        String type, String title, String body) {
        jdbc.update("""
            INSERT INTO notification_event (guardian_account_id, protected_device_id,
                approval_challenge_id, security_incident_id, type, title, body)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, owner, device, challenge, incident, type, title, body);
        // Email failures must not cause a security event to disappear or roll back.
        if (sender != null && !from.isBlank() && !"APPROVAL_DECIDED".equals(type)) {
            try {
                String email = jdbc.queryForObject(
                    "SELECT email FROM guardian_account WHERE id = ?", String.class, owner);
                SimpleMailMessage message = new SimpleMailMessage();
                message.setFrom(from);
                message.setTo(email);
                message.setSubject("Guardian | " + title);
                message.setText(body + "\nAbre Guardian para revisar la solicitud. " +
                    "No respondas al correo con tus contraseñas.");
                sender.send(message);
            } catch (RuntimeException e) {
                // TODO: move outbound notifications to an outbox worker, with retry/metrics.
                org.slf4j.LoggerFactory.getLogger(getClass()).warn(
                    "Correo de alerta fallido; la notificación en la base de datos se conservó");
            }
        }
    }

    public List<Map<String,Object>> inbox(UUID accountId) {
        return jdbc.query("""
            SELECT id, type, title, body, created_at, read_at, protected_device_id,
                   approval_challenge_id
            FROM notification_event
            WHERE guardian_account_id = ?
            ORDER BY created_at DESC LIMIT 100
            """, (rs, i) -> {
                Map<String,Object> m = new java.util.LinkedHashMap<>();
                m.put("id", rs.getString("id"));
                m.put("type", rs.getString("type"));
                m.put("title", rs.getString("title"));
                m.put("body", rs.getString("body"));
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                m.put("read", rs.getTimestamp("read_at") != null);
                m.put("deviceId", rs.getString("protected_device_id"));
                m.put("challengeId", rs.getString("approval_challenge_id"));
                return m;
            }, accountId);
    }

    public void markRead(UUID accountId, UUID notificationId) {
        jdbc.update("""
            UPDATE notification_event SET read_at = COALESCE(read_at, now())
            WHERE id = ? AND guardian_account_id = ?
            """, notificationId, accountId);
    }
}

@RestController
@RequestMapping("/api/v1/notifications")
class NotificationsController {
    private final NotificationService notifications;
    NotificationsController(NotificationService notifications) {
        this.notifications = notifications;
    }
    @GetMapping
    List<Map<String,Object>> list(@org.springframework.security.core.annotation.AuthenticationPrincipal
                                  AuthPrincipal principal) {
        return notifications.inbox(principal.accountId());
    }
    @PostMapping("/{id}/read")
    Map<String,Boolean> read(@org.springframework.security.core.annotation.AuthenticationPrincipal
                             AuthPrincipal principal, @PathVariable UUID id) {
        notifications.markRead(principal.accountId(), id);
        return Map.of("read",true);
    }
}