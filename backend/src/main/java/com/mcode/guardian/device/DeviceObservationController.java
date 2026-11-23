package com.mcode.guardian.device;

import com.mcode.guardian.auth.AuthPrincipal;
import com.mcode.guardian.auth.AuthService;
import com.mcode.guardian.notification.NotificationService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/**
 * Owner-consented Windows locked-screen observation endpoint.
 * All event IDs are client-generated, replay-safe and scoped to a paired device.
 * Photos are encrypted before persistence and never included in API lists.
 */
@RestController
@RequestMapping("/api/v1")
public class DeviceObservationController {
    private static final int MAX_JPEG_BYTES = 550_000;
    private static final Set<String> TYPES = Set.of("FAILED_UNLOCK", "LOCKED_LOCATION");
    private static final Set<String> SOURCES = Set.of("WINDOWS_GEO", "CACHED", "UNAVAILABLE");
    private static final Set<String> PHOTOS = Set.of("CAPTURED", "UNAVAILABLE", "DISABLED", "FAILED", "NOT_REQUESTED");

    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final EvidenceEncryption evidence;
    private final NotificationService notifications;

    public DeviceObservationController(JdbcTemplate jdbc, AuthService auth,
                                       EvidenceEncryption evidence, NotificationService notifications) {
        this.jdbc = jdbc;
        this.auth = auth;
        this.evidence = evidence;
        this.notifications = notifications;
    }

    public record ObservationRequest(
            @NotNull UUID eventId,
            @NotBlank String eventType,
            @NotNull Instant occurredAt,
            Double latitude,
            Double longitude,
            Double accuracyMeters,
            @NotBlank String locationSource,
            Instant locationObservedAt,
            @NotBlank String photoStatus,
            String photoJpegBase64) { }

    private Map<String,Object> requireAgent(UUID deviceId, String key) {
        if (key == null || key.length() < 40 || key.length() > 128) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Agente no autorizado");
        }
        List<Map<String,Object>> rows = jdbc.queryForList("""
            SELECT d.guardian_account_id, d.display_name
            FROM agent_credential c
            JOIN protected_device d ON d.id = c.protected_device_id
            JOIN guardian_account a ON a.id = d.guardian_account_id
            WHERE d.id = ? AND c.secret_hash = ?
              AND d.registration_state = 'PAIRED'
              AND c.revoked_at IS NULL AND d.revoked_at IS NULL
              AND a.disabled_at IS NULL
            """, deviceId, auth.digestForCredential(key));
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Agente no autorizado");
        return rows.get(0);
    }

    @PostMapping("/agent/{deviceId}/security-observations")
    @Transactional
    public Map<String,Object> report(@PathVariable UUID deviceId,
                                     @RequestHeader(value = "X-Guardian-Agent-Key", required = false) String key,
                                     @Valid @RequestBody ObservationRequest request) {
        Map<String,Object> agent = requireAgent(deviceId, key);
        if (!TYPES.contains(request.eventType()) || !SOURCES.contains(request.locationSource())
                || !PHOTOS.contains(request.photoStatus())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Tipo de incidente inválido");
        }
        Instant now = Instant.now();
        if (request.occurredAt().isBefore(now.minus(60, ChronoUnit.DAYS))
                || request.occurredAt().isAfter(now.plus(5, ChronoUnit.MINUTES))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Marca temporal del evento inválida");
        }
        boolean hasCoordinates = request.latitude() != null && request.longitude() != null
                && request.accuracyMeters() != null;
        boolean noCoordinates = request.latitude() == null && request.longitude() == null
                && request.accuracyMeters() == null;
        if ((!hasCoordinates && !noCoordinates)
                || (hasCoordinates && (notBetween(request.latitude(),-90,90)
                || notBetween(request.longitude(),-180,180)
                || notBetween(request.accuracyMeters(),0,100_000)))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ubicación incompleta o inválida");
        }
        if ((hasCoordinates && (request.locationObservedAt() == null
                || request.locationSource().equals("UNAVAILABLE")))
                || (!hasCoordinates && !request.locationSource().equals("UNAVAILABLE"))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Falta fecha o fuente de ubicación");
        }
        if (request.locationObservedAt() != null && request.locationObservedAt().isAfter(now.plusSeconds(300))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fecha de ubicación inválida");
        }
        if (request.eventType().equals("LOCKED_LOCATION") && request.photoJpegBase64() != null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No se toman fotos en el seguimiento periódico");
        }
        byte[] encryptedLocation = null;
        if (hasCoordinates) {
            if (!evidence.enabled()) throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE, "Cifrado de ubicación no configurado");
            String canonical = String.format(Locale.ROOT, "%.7f,%.7f,%.2f",
                    request.latitude(), request.longitude(), request.accuracyMeters());
            encryptedLocation = evidence.encrypt(canonical.getBytes(StandardCharsets.UTF_8));
        }
        byte[] encrypted = null;
        if (request.photoJpegBase64() != null) {
            if (!request.photoStatus().equals("CAPTURED")
                    || request.photoJpegBase64().length() > MAX_JPEG_BYTES * 4 / 3 + 16) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fotografía inválida o demasiado grande");
            }
            byte[] raw;
            try { raw = Base64.getDecoder().decode(request.photoJpegBase64()); }
            catch (IllegalArgumentException ex) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Base64 inválido");
            }
            if (raw.length < 16 || raw.length > MAX_JPEG_BYTES
                    || (raw[0] & 0xFF) != 0xFF || (raw[1] & 0xFF) != 0xD8
                    || (raw[raw.length-2] & 0xFF) != 0xFF || (raw[raw.length-1] & 0xFF) != 0xD9) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El archivo no es una imagen JPEG válida");
            }
            if (!evidence.enabled()) throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE, "Cifrado de evidencias no configurado");
            encrypted = evidence.encrypt(raw);
        } else if (request.photoStatus().equals("CAPTURED")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fotografía omitida");
        }
        Integer recent = jdbc.queryForObject("""
            SELECT count(*) FROM device_security_observation
            WHERE protected_device_id=? AND received_at > now() - interval '1 hour'
            """, Integer.class, deviceId);
        if (recent != null && recent >= 200) throw new ResponseStatusException(
                HttpStatus.TOO_MANY_REQUESTS, "Demasiados eventos para este equipo");
        int inserted = jdbc.update("""
            INSERT INTO device_security_observation
                (id, protected_device_id, event_type, occurred_at, encrypted_location,
                 location_source, location_observed_at, photo_status,
                 encrypted_photo, photo_mime)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO NOTHING
            """, request.eventId(), deviceId, request.eventType(),
                java.sql.Timestamp.from(request.occurredAt()),
                encryptedLocation, request.locationSource(),
                request.locationObservedAt() == null ? null : java.sql.Timestamp.from(request.locationObservedAt()),
                request.photoStatus(), encrypted, encrypted == null ? null : "image/jpeg");
        if (inserted == 0) {
            Integer owned = jdbc.queryForObject("""
                SELECT count(*) FROM device_security_observation WHERE id=? AND protected_device_id=?
                """, Integer.class, request.eventId(), deviceId);
            if (owned == null || owned == 0) throw new ResponseStatusException(HttpStatus.CONFLICT, "ID de evento en uso");
        }
        if (inserted == 1 && "FAILED_UNLOCK".equals(request.eventType())) {
            notifications.publish((UUID) agent.get("guardian_account_id"), deviceId, null, null,
                    "INTRUSION", "Intento fallido de desbloqueo",
                    "Se detectó un intento de acceso en " + agent.get("display_name")
                    + ". Consulta la ubicación y la evidencia disponible en Guardian.");
        }
        return Map.of("accepted",true,"eventId",request.eventId().toString(),"duplicate", inserted == 0);
    }

    private boolean notBetween(double value, double min, double max) {
        return !Double.isFinite(value) || value < min || value > max;
    }

    @GetMapping("/devices/{deviceId}/security-observations")
    public List<Map<String,Object>> list(@AuthenticationPrincipal AuthPrincipal principal,
                                         @PathVariable UUID deviceId) {
        requireOwner(principal,deviceId);
        return jdbc.query("""
            SELECT id, event_type, occurred_at, received_at, encrypted_location,
                   location_source, location_observed_at, photo_status,
                   encrypted_photo IS NOT NULL AS has_photo
            FROM device_security_observation WHERE protected_device_id=?
            ORDER BY occurred_at DESC LIMIT 100
            """, (rs, i) -> observation(rs), deviceId);
    }

    @GetMapping("/devices/{deviceId}/last-location")
    public Map<String,Object> lastLocation(@AuthenticationPrincipal AuthPrincipal principal,
                                           @PathVariable UUID deviceId) {
        requireOwner(principal,deviceId);
        List<Map<String,Object>> results = jdbc.query("""
            SELECT id, event_type, occurred_at, received_at, encrypted_location,
                   location_source, location_observed_at, photo_status,
                   encrypted_photo IS NOT NULL AS has_photo
            FROM device_security_observation WHERE protected_device_id=? AND encrypted_location IS NOT NULL
            ORDER BY location_observed_at DESC LIMIT 1
            """, (rs,i) -> observation(rs), deviceId);
        if (results.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Todavía no se ha registrado una ubicación para el equipo");
        return results.get(0);
    }

    @GetMapping(value="/devices/{deviceId}/security-observations/{eventId}/photo", produces = MediaType.IMAGE_JPEG_VALUE)
    public ResponseEntity<byte[]> photo(@AuthenticationPrincipal AuthPrincipal principal,
                                        @PathVariable UUID deviceId,
                                        @PathVariable UUID eventId) {
        requireOwner(principal,deviceId);
        List<byte[]> matches = jdbc.query("""
            SELECT encrypted_photo FROM device_security_observation
            WHERE protected_device_id=? AND id=? AND encrypted_photo IS NOT NULL
            """, (rs,i) -> rs.getBytes(1), deviceId, eventId);
        if (matches.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Fotografía no disponible");
        return ResponseEntity.ok()
                .header(HttpHeaders.CACHE_CONTROL, "no-store, private")
                .header("X-Content-Type-Options", "nosniff")
                .contentType(MediaType.IMAGE_JPEG)
                .body(evidence.decrypt(matches.get(0)));
    }

    private void requireOwner(AuthPrincipal principal, UUID deviceId) {
        Integer count = jdbc.queryForObject("""
            SELECT count(*) FROM protected_device d JOIN guardian_account a
              ON a.id=d.guardian_account_id
            WHERE d.id=? AND d.guardian_account_id=? AND d.revoked_at IS NULL AND a.disabled_at IS NULL
            """, Integer.class, deviceId, principal.accountId());
        if (count == null || count == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Equipo no encontrado");
    }

    private Map<String,Object> observation(java.sql.ResultSet rs) throws java.sql.SQLException {
        Map<String,Object> value = new LinkedHashMap<>();
        value.put("id",rs.getString("id"));
        value.put("type",rs.getString("event_type"));
        value.put("occurredAt",rs.getTimestamp("occurred_at").toInstant().toString());
        value.put("receivedAt",rs.getTimestamp("received_at").toInstant().toString());
        byte[] encryptedCoordinates = rs.getBytes("encrypted_location");
        if (encryptedCoordinates == null) {
            value.put("latitude", null);
            value.put("longitude", null);
            value.put("accuracyMeters", null);
        } else {
            String[] coordinates = new String(evidence.decrypt(encryptedCoordinates),
                    StandardCharsets.UTF_8).split(",", -1);
            if (coordinates.length != 3) throw new IllegalStateException("Malformed encrypted location");
            value.put("latitude", Double.parseDouble(coordinates[0]));
            value.put("longitude", Double.parseDouble(coordinates[1]));
            value.put("accuracyMeters", Double.parseDouble(coordinates[2]));
        }
        value.put("locationSource",rs.getString("location_source"));
        value.put("locationObservedAt",rs.getTimestamp("location_observed_at") == null ? null :
                rs.getTimestamp("location_observed_at").toInstant().toString());
        value.put("photoStatus",rs.getString("photo_status"));
        value.put("hasPhoto",rs.getBoolean("has_photo"));
        return value;
    }
}
