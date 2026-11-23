package com.mcode.guardian.account;

import com.mcode.guardian.auth.AuthPrincipal;
import com.mcode.guardian.auth.AuthService;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** Memberships are scoped to an owner workspace. No global administrators. */
@Service
public class AccountMembershipService {
    private static final SecureRandom RNG = new SecureRandom();
    private static final Set<String> ROLES = Set.of("ADMIN", "AUTHORIZED", "VIEWER");
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final JavaMailSender mail;
    private final String from;
    private final AccountService accounts;

    public AccountMembershipService(JdbcTemplate jdbc, AuthService auth,
                                    ObjectProvider<JavaMailSender> provider,
                                    @Value("${guardian.auth.mail-from:}") String from,
                                    AccountService accounts) {
        this.jdbc=jdbc;
        this.auth=auth;
        this.mail=provider.getIfAvailable();
        this.from=from;
        this.accounts=accounts;
    }

    private String requireRole(String role) {
        if(role == null || !ROLES.contains(role)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Rol inválido. Opciones: ADMIN, AUTHORIZED, VIEWER");
        }
        return role;
    }

    private void requireActiveOwner(AuthPrincipal principal) {
        Integer active=jdbc.queryForObject("SELECT count(*) FROM guardian_account " +
                "WHERE id=? AND disabled_at IS NULL",Integer.class,principal.accountId());
        if(active==null || active!=1) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,"La cuenta no está activa");
        }
    }

    public List<Map<String,Object>> members(AuthPrincipal principal) {
        requireActiveOwner(principal);
        return jdbc.query("""
            SELECT m.member_account_id, a.email, a.display_name, m.role,
                   m.joined_at FROM guardian_membership m JOIN guardian_account a
              ON a.id=m.member_account_id
            WHERE m.owner_account_id=? AND m.enabled=true
            ORDER BY m.joined_at DESC
            """,(rs,i)->Map.<String,Object>of(
                "id",rs.getString("member_account_id"),
                "email",rs.getString("email"),
                "name",rs.getString("display_name"),
                "role",rs.getString("role"),
                "joinedAt",rs.getTimestamp("joined_at").toInstant().toString()
            ),principal.accountId());
    }

    public List<Map<String,Object>> invitations(AuthPrincipal principal) {
        requireActiveOwner(principal);
        return jdbc.query("""
            SELECT id, email, role, created_at, expires_at, revoked_at, accepted_at
            FROM guardian_invitation
            WHERE owner_account_id=? ORDER BY created_at DESC LIMIT 100
            """,(rs,i)-> {
                Map<String,Object> v=new java.util.LinkedHashMap<>();
                v.put("id",rs.getString("id"));
                v.put("email",rs.getString("email"));
                v.put("role",rs.getString("role"));
                v.put("createdAt",rs.getTimestamp("created_at").toInstant().toString());
                v.put("expiresAt",rs.getTimestamp("expires_at").toInstant().toString());
                v.put("status",rs.getTimestamp("accepted_at")!=null?"ACCEPTED":
                        rs.getTimestamp("revoked_at")!=null?"REVOKED":
                        Instant.now().isBefore(rs.getTimestamp("expires_at").toInstant())?
                        "PENDING":"EXPIRED");
                return v;
            },principal.accountId());
    }

    @Transactional
    public void invite(AuthPrincipal principal,String rawEmail,String role) {
        requireActiveOwner(principal);
        String email=AccountService.normalizedEmail(rawEmail);
        String permission=requireRole(role);
        String ownerEmail=jdbc.queryForObject("SELECT email FROM guardian_account WHERE id=?",
                String.class,principal.accountId());
        if(email.equals(ownerEmail)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "No puedes invitar a la cuenta propietaria");
        }
        if(mail==null || from.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Configura SMTP para enviar invitaciones");
        }
        // Serializes per-owner invitations to ensure quotas apply across concurrent requests.
        jdbc.queryForObject("SELECT id FROM guardian_account WHERE id=? FOR UPDATE",
                UUID.class,principal.accountId());
        Integer recent=jdbc.queryForObject("""
            SELECT count(*) FROM guardian_invitation
            WHERE owner_account_id=? AND created_at>now()-interval '1 minute'
            """,Integer.class,principal.accountId());
        Integer hourly=jdbc.queryForObject("""
            SELECT count(*) FROM guardian_invitation
            WHERE owner_account_id=? AND created_at>now()-interval '1 hour'
            """,Integer.class,principal.accountId());
        if((recent!=null && recent>0) || (hourly!=null && hourly>=15)) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Límite de invitaciones alcanzado");
        }
        Integer existing=jdbc.queryForObject("""
            SELECT count(*) FROM guardian_invitation
            WHERE owner_account_id=? AND lower(email)=? AND expires_at>now()
              AND accepted_at IS NULL AND revoked_at IS NULL
            """,Integer.class,principal.accountId(),email);
        if(existing!=null && existing>0) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Ya existe una invitación pendiente");
        }
        byte[] bytes=new byte[32]; RNG.nextBytes(bytes);
        String token=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        jdbc.update("""
            INSERT INTO guardian_invitation
              (owner_account_id,invited_by_account_id,email,role,token_hash,expires_at)
            VALUES (?,?,?,?,?,?)
            """,principal.accountId(),principal.accountId(),email,permission,
                auth.digestForCredential(token),java.sql.Timestamp.from(Instant.now().plus(48,ChronoUnit.HOURS)));
        SimpleMailMessage message=new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(email);
        message.setSubject("Guardian | Te han invitado a un equipo");
        message.setText("Se te ha invitado como "+permission+" al espacio Guardian de " +
                ownerEmail+".\n\nAbre Guardian, inicia sesión con este correo " +
                "(o crea tu cuenta), ve a Usuarios autorizados > Aceptar invitación " +
                "y pega el siguiente código:\n"+token+"\n\nVigencia: 48 horas. " +
                "Si no reconoces la invitación, ignórala.");
        try { mail.send(message); }
        catch (RuntimeException ex) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "No fue posible enviar la invitación",ex);
        }
        accounts.audit(principal.accountId(),principal.accountId(),"MEMBER_INVITED");
    }

    @Transactional
    public void accept(AuthPrincipal principal,String token) {
        if(token==null || token.length()<40 || token.length()>128) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invitación inválida");
        }
        List<Map<String,Object>> rows=jdbc.queryForList("""
            SELECT i.id, i.owner_account_id, i.email, i.role
            FROM guardian_invitation i
            JOIN guardian_account a ON a.id=i.owner_account_id
            WHERE i.token_hash=? AND i.revoked_at IS NULL
              AND i.accepted_at IS NULL AND i.expires_at>now()
              AND a.disabled_at IS NULL FOR UPDATE OF i
            """,auth.digestForCredential(token));
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invitación inválida o vencida");
        Map<String,Object> invite=rows.get(0);
        List<String> myEmail=jdbc.query("""
            SELECT email FROM guardian_account WHERE id=? AND email_verified=true
              AND disabled_at IS NULL
            """,(rs,i)->rs.getString(1),principal.accountId());
        if(myEmail.isEmpty() || !invite.get("email").equals(myEmail.get(0))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Debes entrar con la cuenta del correo invitado y verificarla");
        }
        if(principal.accountId().equals(invite.get("owner_account_id"))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"No se permite invitarse a sí mismo");
        }
        jdbc.update("""
            INSERT INTO guardian_membership (owner_account_id,member_account_id,role,enabled)
            VALUES (?,?,?,true)
            ON CONFLICT (owner_account_id,member_account_id)
            DO UPDATE SET role=EXCLUDED.role,enabled=true,joined_at=now()
            """,invite.get("owner_account_id"),principal.accountId(),invite.get("role"));
        jdbc.update("UPDATE guardian_invitation SET accepted_at=now() WHERE id=?",
                invite.get("id"));
        accounts.audit((UUID)invite.get("owner_account_id"),principal.accountId(),
                "MEMBER_JOINED");
    }

    @Transactional
    public void revokeInvitation(AuthPrincipal principal,UUID invitationId) {
        requireActiveOwner(principal);
        int updated=jdbc.update("""
            UPDATE guardian_invitation SET revoked_at=now()
            WHERE id=? AND owner_account_id=? AND accepted_at IS NULL
              AND revoked_at IS NULL
            """,invitationId,principal.accountId());
        if(updated<1) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Invitación no encontrada");
        accounts.audit(principal.accountId(),principal.accountId(),"INVITATION_REVOKED");
    }

    @Transactional
    public void changeRole(AuthPrincipal principal,UUID memberId,String role) {
        requireActiveOwner(principal);
        String verifiedRole=requireRole(role);
        int updated=jdbc.update("""
            UPDATE guardian_membership SET role=? WHERE owner_account_id=?
              AND member_account_id=? AND enabled=true
            """,verifiedRole,principal.accountId(),memberId);
        if(updated<1) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Usuario autorizado no encontrado");
        accounts.audit(principal.accountId(),principal.accountId(),"MEMBER_ROLE_CHANGED");
    }

    @Transactional
    public void removeMember(AuthPrincipal principal,UUID memberId) {
        requireActiveOwner(principal);
        int updated=jdbc.update("""
            UPDATE guardian_membership SET enabled=false WHERE owner_account_id=?
              AND member_account_id=? AND enabled=true
            """,principal.accountId(),memberId);
        if(updated<1) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Usuario autorizado no encontrado");
        accounts.audit(principal.accountId(),principal.accountId(),"MEMBER_REMOVED");
    }

    public String role(UUID actor,UUID owner) {
        if(actor.equals(owner)) {
            Integer active=jdbc.queryForObject("SELECT count(*) FROM guardian_account WHERE " +
                    "id=? AND disabled_at IS NULL",Integer.class,owner);
            if(active!=null && active==1) return "OWNER";
        }
        List<String> rows=jdbc.query("""
            SELECT m.role FROM guardian_membership m
            JOIN guardian_account o ON o.id=m.owner_account_id
            JOIN guardian_account a ON a.id=m.member_account_id
            WHERE m.owner_account_id=? AND m.member_account_id=? AND m.enabled=true
              AND o.disabled_at IS NULL AND a.disabled_at IS NULL
            """,(rs,i)->rs.getString(1),owner,actor);
        return rows.isEmpty()?"NONE":rows.get(0);
    }

    public void requireWorkspaceRead(UUID actor,UUID owner) {
        if("NONE".equals(role(actor,owner))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Sin permiso para este espacio");
        }
    }

    public void requireWorkspaceManage(UUID actor,UUID owner) {
        String permission=role(actor,owner);
        if(!permission.equals("OWNER") && !permission.equals("ADMIN")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Solo propietario o administrador pueden cambiar políticas");
        }
    }
}
