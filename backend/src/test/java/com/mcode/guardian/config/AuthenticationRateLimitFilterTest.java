package com.mcode.guardian.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class AuthenticationRateLimitFilterTest {

    @Test
    void registrationLimitsAreStricterThanLogin() {
        assertEquals(3, AuthenticationRateLimitFilter.limitFor("/api/v1/auth/register"));
        assertEquals(12, AuthenticationRateLimitFilter.limitFor("/api/v1/auth/login"));
        assertEquals(0, AuthenticationRateLimitFilter.limitFor("/api/v1/devices"));
    }

    @Test
    void excessiveRegistrationsReturn429WithoutCallingApplication() throws Exception {
        Clock now = Clock.fixed(Instant.parse("2026-11-07T16:00:00Z"), ZoneOffset.UTC);
        AuthenticationRateLimitFilter filter = new AuthenticationRateLimitFilter(now);
        for (int i = 0; i < 4; i++) {
            MockHttpServletRequest request = new MockHttpServletRequest("POST",
                "/api/v1/auth/register");
            request.setRemoteAddr("192.0.2.30");
            MockHttpServletResponse response = new MockHttpServletResponse();
            filter.doFilter(request, response, new MockFilterChain());
            if (i < 3) assertEquals(200, response.getStatus());
            else {
                assertEquals(429, response.getStatus());
                assertTrue(response.getHeader("Retry-After") != null);
            }
        }
    }
}
