# Guardian — Cuentas, equipos bloqueados, ubicación e intentos fallidos

**Paquete de integración local, 23 de noviembre de 2026.** Destino: repositorio privado `mcodesas/guardian`, rama temporal a partir de `dev`. **Integración iniciada en GitHub (cuenta M Code).** La validación de compilación y despliegue todavía es necesaria. Tampoco se dispone aquí de Flutter, Maven, Docker, cámara Windows ni credenciales de producción.

## Archivos incluidos

- `backend/.../V5__account_administration.sql`: usuarios, miembros, roles, invitaciones, cambio de correo, desactivación y eliminación.
- `backend/.../account/`: controladores y servicios de cuentas/miembros/espacios. Autorizaciones separadas por propietario.
- `backend/.../V6__locked_device_observations.sql`: incidentes de acceso, ubicaciones cifradas y fotografías cifradas.
- `backend/.../device/`: endpoint de recepción de incidentes, consulta de últimos lugares y evidencias, retención automática y AES-256-GCM.
- `agent/windows/guardian_locked_security.py`: segundo monitor Windows, *opt-in*, que audita desbloqueos fallidos y posición durante sesión bloqueada.
- `apps/guardian_flutter/lib/ui/`: Centro de cuenta, espacios compartidos, geolocalización y evidencia de incidentes.
- `scripts/apply_guardian_patch.py`: aplica los nuevos archivos al clon *sin sustituir versiones desconocidas*. Ajusta rutas del backend y menú Flutter, y agrega la clave de cifrado a Compose.

## Entrega en rama dev

Este paquete no hace `git push` ni merge. Una vez restablecida la conexión y revisados los cambios:

```bash
# En un clon actualizado del repositorio
cd guardian
git checkout dev
git pull --ff-only origin dev
git checkout -b feature/cuentas-ubicacion-equipo-bloqueado-20261123

# Vista previa y aplicación segura (usa la ruta real del paquete)
python /ruta/guardian_patch_20261123/scripts/apply_guardian_patch.py .
python /ruta/guardian_patch_20261123/scripts/apply_guardian_patch.py . --apply

git diff --stat
```

Si existen migraciones V5/V6 o implementaciones de cuenta distintas, **el aplicador se detiene** para evitar perder cambios del equipo. Es necesario reconciliar primero las diferencias, no sobrescribir.

## Backend y Docker

La instalación agrega a `.env.example` y `docker-compose.yml`:

```
GUARDIAN_EVIDENCE_KEY_BASE64=<una clave base64 de 32 bytes aleatorios>
```

Generar **en entorno seguro**, por ejemplo:

```bash
openssl rand -base64 32
```

**La clave no debe guardarse en Git, correos, WhatsApp o logs.** Debe almacenarse de forma persistente en un gestor de secretos/almacenamiento protegido. Perderla impide descifrar fotos y ubicaciones anteriores. Si se cambia, se requiere migración de datos cifrados.

```bash
cd backend
mvn -B -ntp verify
cd ..
docker compose config
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 backend
curl http://localhost:8080/actuator/health
```

Las migraciones **V1–V6** deben ejecutarse en orden, especialmente V5 para desactivación de cuentas y V6 para observaciones. Nunca correr sobre datos reales sin respaldo previo.

### API de cuentas

`GET/PATCH /api/v1/account` · `POST /api/v1/account/password` · `POST /api/v1/account/email/change-request` · `POST /api/v1/account/email/confirm` · `GET /api/v1/account/sessions` · `DELETE /api/v1/account/sessions/{id}` · `POST /api/v1/account/sessions/revoke-others` · `POST /api/v1/account/deactivate` · `POST /api/v1/account/reactivate/request` · `POST /api/v1/account/reactivate/confirm` · `POST /api/v1/account/deletion/request` · `POST /api/v1/account/deletion/confirm` · `GET /api/v1/account/members` · `POST /api/v1/account/invitations` · `POST /api/v1/account/invitations/accept` · `PATCH /api/v1/account/members/{id}/role` · `DELETE /api/v1/account/members/{id}` · `GET /api/v1/workspaces`.

Roles: `OWNER` (implícito), `ADMIN` (gestiona políticas del espacio compartido), `AUTHORIZED`, `VIEWER`. **No significa que un invitado ya haya sido inscrito en el reconocimiento facial ni pueda desbloquear Windows**. Es un conjunto de permisos de la aplicación/espacio.

Cambio de correo exige contraseña actual y validación del correo nuevo. Eliminación exige contraseña y código temporal enviado al correo; elimina ubicaciones/evidencias del servidor antes de borrar dispositivos, además de los demás datos de usuario. Las copias de seguridad y el almacenamiento biométrico local requieren una política independiente de borrado.

### API de ubicación/observaciones

- `POST /api/v1/agent/{deviceId}/security-observations` autenticado por `X-Guardian-Agent-Key`; acepta `eventId`, `eventType: FAILED_UNLOCK|LOCKED_LOCATION`, `occurredAt`, coordenadas, `accuracyMeters`, `locationSource`, `locationObservedAt`, `photoStatus` y JPEG Base64 opcional.
- `GET /api/v1/devices/{deviceId}/security-observations` solo propietario.
- `GET /api/v1/devices/{deviceId}/last-location` solo propietario: devuelve ubicación registrada, timestamp, precisión y fuente, nunca la presenta como posición actual cuando es antigua.
- `GET /api/v1/devices/{deviceId}/security-observations/{eventId}/photo` solo propietario, bajo token Guardian. Control `Cache-Control: no-store`.

La base de datos almacena **coordenadas/fotografías cifradas con AES-256-GCM**; no están en texto claro. Se eliminan fotos pasados 7 días y eventos/ubicaciones después de 90 días. La notificación push/correo informa del incidente sin divulgar coordenadas ni adjuntos en la pantalla bloqueada del móvil.

## Windows: antes de instalar

El propietario debe aceptar explícitamente seguimiento de ubicación y captura de incidentes. Registrar consentimiento en onboarding/política de privacidad. Configurar los permisos de Cámara y Ubicación de Windows, y permitir que las aplicaciones de escritorio utilicen esos recursos. Asegurarse de que el proceso no sea detenido cuando Windows bloquee la **sesión existente**.

### Auditoría de Windows

Abrir `secpol.msc` → Configuración avanzada de directiva de auditoría → Inicio/cierre de sesión:

- **Audit Logon:** registrar fallos, necesario para evento `4625`.
- **Audit Other Logon/Logoff Events:** registrar éxitos, necesario para `4800` (bloqueo) y `4801` (desbloqueo).

La lectura del registro `Security` requiere privilegios adecuados (administrador o permisos de lectura del registro asignados por el SO). No desactivar UAC ni modificar ACL de Windows de forma insegura. Comprobar eventos reales en Visor de Eventos, no asumir que todos los PIN/Windows Hello generan 4625.

### Instalación controlada

```powershell
cd agent\windows
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install -r requirements_locked_windows.txt
# Previamente vincular con el backend (guarda AgentKey cifrada con DPAPI)
python guardian_agent.py setup
# Activar SOLO después de permisos/consentimiento configurados
python guardian_locked_security.py --monitor --track-location --capture-failed-unlock
```

`--track-location` permite ubicación; `--capture-failed-unlock` permite intento de foto cuando Windows registra un fallo de desbloqueo. Si un permiso está denegado, el dispositivo no tiene hardware/servicio de geolocalización, se apaga, pierde red o Windows impide usar cámara bloqueada, el reporte incluye **no disponible** o última ubicación conocida, con fecha. No se inventan coordenadas ni se fuerza el acceso a la cámara. La foto se intenta **después de registrar el fallo**: no puede garantizarse que muestre a la persona que intentó acceder.

El monitor usa el mismo backend que el agente principal. Si no hay conexión, almacena eventos protegidos con **Windows DPAPI** y los envía cuando la red vuelve, con una cola de tamaño limitado. Las muestras cifradas en servidor requieren TLS para el transporte.

En Windows el agente de usuario puede seguir funcionando durante un bloqueo de su sesión, pero **no funciona antes de que ese usuario inicie sesión después de arrancar**, no tiene acceso garantizado a cámara/pantalla de bienvenida, y el registro de eventos podría no incluir todos los intentos biométricos.

### Pruebas necesarias antes de usarlo realmente

1. Ejecutar `python -m unittest discover -s agent/windows -p 'test_guardian_locked_security.py' -v` (cinco pruebas puras).
2. `python -m py_compile agent/windows/guardian_locked_security.py`.
3. Verificar permisos del Registro de eventos Windows y que 4800/4801 y 4625 tipo 7 aparecen en el equipo.
4. Probar cámara y ubicación antes/después de bloqueo, con y sin red, y en equipos sin GPS.
5. Verificar que nadie distinto del propietario pueda consultar ubicaciones ni fotos.
6. Validar borrado/cifrado y recuperación de clave, consentimiento, notificaciones y no filtración de información sensible.
7. Compilar/analisar Flutter y backend y probar Android/iOS reales.

## Restricciones de Android y iOS

Este paquete implementa seguimiento **de computadores Windows**. Android/iOS no permiten a una aplicación corriente tomar fotografías arbitrariamente desde la pantalla bloqueada ni vigilar toda la actividad del sistema con cámara en segundo plano. El uso de localización en segundo plano depende de permisos expresos y políticas del sistema, y necesitará módulos específicos. No se promete esta función para los móviles como dispositivos protegidos.
