package com.mcode.guardian.account;

import com.mcode.guardian.auth.AuthPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/account")
public class AccountController {
    private final AccountService accounts;
    private final AccountMembershipService membership;

    public AccountController(AccountService accounts, AccountMembershipService membership) {
        this.accounts=accounts;
        this.membership=membership;
    }

    public record ProfileUpdate(@NotBlank @Size(max=120) String name,
                                @Size(max=32) String phone) {}
    public record PasswordUpdate(@NotBlank String currentPassword,
                                 @NotBlank @Size(min=12,max=128) String newPassword) {}
    public record EmailChange(@Email @NotBlank String email,
                              @NotBlank String currentPassword) {}
    public record Code(@NotBlank String code) {}
    public record PasswordProof(@NotBlank String password) {}
    public record ReactivationRequest(@Email @NotBlank String email) {}
    public record ReactivationConfirm(@Email @NotBlank String email,@NotBlank String code) {}
    public record Invitation(@Email @NotBlank String email,@NotBlank String role) {}
    public record AcceptInvitation(@NotBlank String token) {}
    public record RoleUpdate(@NotBlank String role) {}

    @GetMapping
    public Map<String,Object> profile(@AuthenticationPrincipal AuthPrincipal principal) {
        return accounts.profile(principal);
    }

    @PatchMapping
    public Map<String,Object> update(@AuthenticationPrincipal AuthPrincipal principal,
                                      @Valid @RequestBody ProfileUpdate input) {
        return accounts.updateProfile(principal,input.name(),input.phone());
    }

    @PostMapping("/password")
    public Map<String,String> password(@AuthenticationPrincipal AuthPrincipal principal,
                                        @Valid @RequestBody PasswordUpdate input) {
        accounts.changePassword(principal,input.currentPassword(),input.newPassword());
        return Map.of("message","Contraseña cambiada. Inicia sesión nuevamente en tus dispositivos.");
    }

    @PostMapping("/email/change-request")
    public Map<String,String> requestEmail(@AuthenticationPrincipal AuthPrincipal principal,
                                            @Valid @RequestBody EmailChange input) {
        accounts.requestEmailChange(principal,input.email(),input.currentPassword());
        return Map.of("message","Comprueba el código enviado al nuevo correo.");
    }

    @PostMapping("/email/confirm")
    public Map<String,String> confirmEmail(@AuthenticationPrincipal AuthPrincipal principal,
                                            @Valid @RequestBody Code input) {
        if(!accounts.confirmEmailChange(principal,input.code())) throw invalidCode();
        return Map.of("message","Correo verificado. Vuelve a iniciar sesión.");
    }

    @GetMapping("/sessions")
    public List<Map<String,Object>> sessions(@AuthenticationPrincipal AuthPrincipal principal) {
        return accounts.sessions(principal);
    }

    @DeleteMapping("/sessions/{sessionId}")
    public Map<String,Boolean> revokeSession(@AuthenticationPrincipal AuthPrincipal principal,
                                              @PathVariable UUID sessionId) {
        accounts.revokeSession(principal,sessionId);
        return Map.of("revoked",true);
    }

    @PostMapping("/sessions/revoke-others")
    public Map<String,Boolean> revokeOthers(@AuthenticationPrincipal AuthPrincipal principal) {
        accounts.revokeOtherSessions(principal);
        return Map.of("revoked",true);
    }

    @PostMapping("/deactivate")
    public Map<String,String> deactivate(@AuthenticationPrincipal AuthPrincipal principal,
                                          @Valid @RequestBody PasswordProof proof) {
        accounts.deactivate(principal,proof.password());
        return Map.of("message","Cuenta desactivada. Sesiones y claves de dispositivo revocadas.");
    }

    @PostMapping("/reactivate/request")
    public Map<String,String> requestReactivation(@Valid @RequestBody ReactivationRequest input) {
        accounts.requestReactivation(input.email());
        return Map.of("message","Si la cuenta está desactivada, llegará un código.");
    }

    @PostMapping("/reactivate/confirm")
    public Map<String,String> confirmReactivation(@Valid @RequestBody ReactivationConfirm input) {
        if(!accounts.reactivate(input.email(),input.code())) throw invalidCode();
        return Map.of("message","Cuenta reactivada. Vincula de nuevo tus dispositivos.");
    }

    @PostMapping("/deletion/request")
    public Map<String,String> requestDeletion(@AuthenticationPrincipal AuthPrincipal principal,
                                               @Valid @RequestBody PasswordProof proof) {
        accounts.requestDeletion(principal,proof.password());
        return Map.of("message","Enviamos un código al correo registrado.");
    }

    @PostMapping("/deletion/confirm")
    public Map<String,String> delete(@AuthenticationPrincipal AuthPrincipal principal,
                                      @Valid @RequestBody Code input) {
        if(!accounts.deleteAccount(principal,input.code())) throw invalidCode();
        return Map.of("message","Cuenta y datos del servidor eliminados.");
    }

    @GetMapping("/members")
    public List<Map<String,Object>> members(@AuthenticationPrincipal AuthPrincipal principal) {
        return membership.members(principal);
    }

    @GetMapping("/invitations")
    public List<Map<String,Object>> invitations(@AuthenticationPrincipal AuthPrincipal principal) {
        return membership.invitations(principal);
    }

    @PostMapping("/invitations")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String,String> invite(@AuthenticationPrincipal AuthPrincipal principal,
                                      @Valid @RequestBody Invitation input) {
        membership.invite(principal,input.email(),input.role());
        return Map.of("message","Invitación enviada al correo.");
    }

    @PostMapping("/invitations/accept")
    public Map<String,String> accept(@AuthenticationPrincipal AuthPrincipal principal,
                                      @Valid @RequestBody AcceptInvitation input) {
        membership.accept(principal,input.token());
        return Map.of("message","Invitación aceptada.");
    }

    @DeleteMapping("/invitations/{id}")
    public Map<String,Boolean> revokeInvitation(@AuthenticationPrincipal AuthPrincipal principal,
                                                  @PathVariable UUID id) {
        membership.revokeInvitation(principal,id);
        return Map.of("revoked",true);
    }

    @PatchMapping("/members/{id}/role")
    public Map<String,Boolean> changeRole(@AuthenticationPrincipal AuthPrincipal principal,
                                           @PathVariable UUID id,
                                           @Valid @RequestBody RoleUpdate input) {
        membership.changeRole(principal,id,input.role());
        return Map.of("updated",true);
    }

    @DeleteMapping("/members/{id}")
    public Map<String,Boolean> removeMember(@AuthenticationPrincipal AuthPrincipal principal,
                                             @PathVariable UUID id) {
        membership.removeMember(principal,id);
        return Map.of("removed",true);
    }

    private static ResponseStatusException invalidCode() {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST,AccountService.invalidCodeMessage());
    }
}
