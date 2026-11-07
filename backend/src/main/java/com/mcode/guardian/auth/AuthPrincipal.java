package com.mcode.guardian.auth;

import java.util.UUID;

public record AuthPrincipal(UUID accountId, UUID sessionId, String email) { }