package com.mcode.guardian.device;

import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Short-lived sensitive evidence; bounded audit metadata retention. */
@Component
public class ObservationRetention {
    private final JdbcTemplate jdbc;
    public ObservationRetention(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Scheduled(cron = "0 25 3 * * *", zone = "UTC")
    public void cleanup() {
        // Remove photo content after 7 days, keeping the event and location timeline.
        jdbc.update("""
            UPDATE device_security_observation
            SET encrypted_photo=NULL, photo_mime=NULL, photo_status='UNAVAILABLE'
            WHERE encrypted_photo IS NOT NULL AND received_at < now() - interval '7 days'
            """);
        // User-visible location history is retained no longer than 90 days.
        jdbc.update("""
            DELETE FROM device_security_observation
            WHERE received_at < now() - interval '90 days'
            """);
    }
}

@Configuration
@EnableScheduling
class GuardianObservationSchedule { }
