package com.mcode.guardian.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthService auth;
    public AuthController(AuthService auth) { this.auth = auth; }

    public record RegisterRequest(@Email @NotBlank String email,
                                  @NotBlank @Size(min=12,max=128) String password,
                                  @NotBlank @Size(max=120) String name) {}
    public record VerifyRequest(@Email @NotBlank String email,
                                @NotBlank String code) {}
    public record LoginRequest(@Email @NotBlank String email,
                               @NotBlank String password,
                               @Size(max=120) String clientLabel) {}
    public record RefreshRequest(@NotBlank String refreshToken) {}

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String,String> register(@Valid @RequestBody RegisterRequest request) {
        auth.register(request.email, request.password, request.name);
        return Map.of("message","Revisa tu correo para activar la cuenta");
    }

    @PostMapping("/verify")
    public Map<String,String> verify(@Valid @RequestBody VerifyRequest request) {
        if (!auth.verifyCode(request.email, request.code))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Código inválido o vencido");
        return Map.of("message","Cuenta verificada");
    }

    @PostMapping("/login")
    public Map<String,Object> login(@Valid @RequestBody LoginRequest request) {
        Map<String,Object> result = auth.login(request.email, request.password, request.clientLabel);
        if (result.containsKey("authenticationFailed")) throw AuthService.unauthenticated();
        if (result.containsKey("verificationRequired"))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Verifica primero tu correo");
        return result;
    }

    @PostMapping("/refresh")
    public Map<String,Object> refresh(@Valid @RequestBody RefreshRequest request) {
        return auth.refresh(request.refreshToken);
    }

    @GetMapping("/me")
    public Map<String,Object> me(@AuthenticationPrincipal AuthPrincipal principal) {
        return auth.me(principal);
    }

    @PostMapping("/logout")
    public Map<String,String> logout(@AuthenticationPrincipal AuthPrincipal principal) {
        auth.logout(principal);
        return Map.of("message","Sesión cerrada");
    }
}