package com.mcode.guardian.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Small single-node safety net to limit account-related API abuse.
 * Does not rely on spoofable forwarded headers.
 *
 * In a horizontally scaled deployment, replace this with a distributed
 * limiter at the trusted reverse proxy, backed by Redis or PostgreSQL.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class AuthenticationRateLimitFilter extends OncePerRequestFilter {

    private static final long WINDOW_SECONDS = 60;
    private static final int MAX_STORED_WINDOWS = 50_000;
    private final Map<String, Window> windows = new ConcurrentHashMap<>();
    private final Clock clock;

    record Window(long epochWindow, int attempts) { }

    public AuthenticationRateLimitFilter() {
        this(Clock.systemUTC());
    }

    AuthenticationRateLimitFilter(Clock clock) {
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
        HttpServletResponse response, FilterChain chain) throws IOException, ServletException {
        if (!"POST".equals(request.getMethod())) {
            chain.doFilter(request, response);
            return;
        }
        int maximum = limitFor(request.getRequestURI());
        if (maximum < 1) {
            chain.doFilter(request, response);
            return;
        }

        String ip = request.getRemoteAddr();
        String key = request.getRequestURI() + ":" + (ip == null ? "unknown" : ip);
        long epochWindow = clock.instant().getEpochSecond() / WINDOW_SECONDS;
        Window updated = windows.compute(key, (ignored, existing) -> {
            if (existing == null || existing.epochWindow != epochWindow) {
                return new Window(epochWindow, 1);
            }
            return new Window(epochWindow, existing.attempts + 1);
        });
        if (windows.size() > MAX_STORED_WINDOWS) {
            windows.entrySet().removeIf(entry ->
                entry.getValue().epochWindow < epochWindow - 1);
        }
        if (updated.attempts > maximum) {
            response.setStatus(429);
            response.setHeader("Retry-After", String.valueOf(
                WINDOW_SECONDS - clock.instant().getEpochSecond() % WINDOW_SECONDS));
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"error\":\"Demasiadas solicitudes. Intenta más tarde.\"}");
            return;
        }
        chain.doFilter(request, response);
    }

    static int limitFor(String path) {
        if (path == null) return 0;
        return switch (path) {
            case "/api/v1/auth/register" -> 3;
            case "/api/v1/auth/login" -> 12;
            case "/api/v1/auth/verify", "/api/v1/auth/reset" -> 10;
            case "/api/v1/auth/resend-verification",
                 "/api/v1/auth/request-reset",
                 "/api/v1/mobile/credentials/challenge" -> 5;
            default -> 0;
        };
    }
}
