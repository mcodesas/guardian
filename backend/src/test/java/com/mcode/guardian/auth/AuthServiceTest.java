package com.mcode.guardian.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;

class AuthServiceTest {
    @Test
    void normalizeEmailWithoutChangingLocalAlias() {
        assertEquals("user+guardian@example.com",
            AuthService.normalizedEmail(" User+Guardian@Example.COM "));
    }
}