# Guardian — Implementación y estado actual

> Rama de implementación: `feat/bootstrap-guardian-20261107`. Ningún módulo está desplegado. El agente Windows existe como prototipo de evaluación basado en Python/OpenCV sin pruebas en hardware, sin liveness y sin instalador; macOS/Linux siguen pendientes. No afirmar que el equipo está protegido antes de verificar agente y bloqueo real.

## Autenticación y parametrización

Una única cuenta Guardian se utiliza en escritorio y móvil:

1. Registro `POST /api/v1/auth/register` con nombre, correo y contraseña de 12+ caracteres, procesada con BCrypt.
2. Correo verificado usando OTP de 6 dígitos, 10 minutos de vigencia y máximo 5 intentos; existe reenvío con separación de 60 segundos.
3. Inicio de sesión con email/contraseña. Tras 5 intentos incorrectos, la cuenta se bloquea 15 minutos.
4. Token opaco de acceso aleatorio de 256 bits (15 minutos) y refresh aleatorio (30 días), ambos almacenados exclusivamente como hashes en PostgreSQL.
5. Renovación rotativa del par de tokens; cierre de sesión revoca el registro de sesión; recuperación de contraseña revoca todas las sesiones del usuario.
6. Solicitud de recuperación por correo con código temporal de 6 dígitos y máximo 5 intentos. **Nunca** se envía una contraseña.
7. La aplicación guarda tokens con `flutter_secure_storage`; el backend se configura por URL HTTPS.
8. Antes de habilitar protección, el propietario registra equipos y configura política de ausencia; solo se consideran activos tras vincular un agente real.

Requisitos de producción adicionales: MFA de acceso, bloqueo anti-enumeración por IP, límites perimetrales de solicitud, auditoría de sesión, detección de robo de refresh tokens y emails diferidos con reintentos.

## PostgreSQL 17

Flyway:
- `V1__initial_guardian_schema.sql`: cuentas, dispositivos, incidentes, claves móviles, desafíos.
- `V2__accounts_devices_notifications.sql`: contraseñas, sesiones revocables, políticas, agent credential, notificaciones y registro push.
- `V3__recovery.sql`: códigos de recuperación y límites.

Las plantillas faciales no se guardan en PostgreSQL. Fotografías/eventos multimedia requerirán almacenamiento cifrado con retención configurable y control de acceso.

## Aprobación remota

1. El agente local envía una solicitud autenticada mediante su clave única.
2. Backend crea challenge aleatorio (nonce, UUID), que caduca en 45 s.
3. El móvil con sesión Guardian recibe el evento en bandeja y, si se configura Firebase, un push Android/iOS.
4. El usuario aprueba 5/15/30 min o rechaza. La app exige huella/Face ID.
5. La app firma con Ed25519 el texto canónico `guardian:v1:ID:NONCE:DECISION:MINUTOS`.
6. Backend comprueba firma de clave pública previamente registrada, propiedad del dispositivo móvil, estado pendiente, expiración y operación transaccional bloqueada.
7. El agente consulta la decisión y aplica localmente la excepción de monitoreo. **Aprobar no desbloquea el sistema operativo**.
8. Un reporte de intrusión confirmada cancela aprobaciones pendientes y aprobadas.

**Limitación:** el prototipo almacena clave Ed25519 en almacenamiento cifrado de Flutter; no se garantiza una clave hardware no exportable. Debe reemplazarse por Android Keystore/Secure Enclave y verificarse atestación para un producto de alta seguridad.

## API implementada

| Método | Ruta | Necesita |
|---|---|---|
| POST | /api/v1/auth/register | pública |
| POST | /api/v1/auth/verify | pública |
| POST | /api/v1/auth/resend-verification | pública |
| POST | /api/v1/auth/login | pública |
| POST | /api/v1/auth/refresh | pública |
| POST | /api/v1/auth/request-reset | pública |
| POST | /api/v1/auth/reset | pública |
| GET | /api/v1/auth/me | access token |
| POST | /api/v1/auth/logout | access token |
| GET/POST | /api/v1/devices | access token |
| PATCH | /api/v1/devices/{id}/policy | access token |
| DELETE | /api/v1/devices/{id} | access token |
| GET | /api/v1/approvals | access token |
| POST | /api/v1/approvals/{id}/decision | access token + firma móvil |
| POST/GET/DELETE | /api/v1/mobile/credentials | access token |
| GET | /api/v1/incidents | access token |
| GET | /api/v1/notifications | access token |
| POST | /api/v1/notifications/{id}/read | access token |
| POST | /api/v1/push/register | access token |
| POST | /api/v1/push/unregister | access token |
| POST | /api/v1/agent/{id}/activate | cabecera X-Guardian-Agent-Key |
| POST | /api/v1/agent/{id}/events | cabecera X-Guardian-Agent-Key |
| POST | /api/v1/agent/{id}/challenges | cabecera X-Guardian-Agent-Key |
| GET | /api/v1/agent/{id}/challenges/{challengeId} | cabecera X-Guardian-Agent-Key |

### Seguridad y reglas de despliegue

- Nunca publicar `.env`, credenciales Firebase, fotografías ni materiales biométricos.
- Configurar TLS con proxy inverso: los puertos de Docker se exponen solo en `127.0.0.1`.
- Completar SMTP seguro para verificación y recuperación; sin SMTP la cuenta no puede registrarse correctamente.
- Configurar FCM Admin y credenciales del proyecto Firebase para pushes reales. Sin Firebase la bandeja funciona cuando la app está abierta.
- `GUARDIAN_AUTH_PEPPER` es obligatorio, secreto, aleatorio de mínimo 32 caracteres y debe permanecer estable en reinstalaciones.
- Las políticas por dispositivo almacenadas en backend son configuraciones; solo el agente nativo pendiente podrá ejecutar bloqueo real.
- El registro de equipos entrega un `agentKey` una vez. Guardarlo en sistema seguro, no en documentos ni logs.
- La configuración de recuperación del dispositivo físico sigue siendo responsabilidad del sistema operativo.

## Diseño

Tema oscuro original de Guardian: fondo azul grafito, turquesa luminoso, azul para información, ámbar para verificación y rojo para incidentes críticos. Layout adaptativo con navegación lateral en escritorio e inferior en móvil; panel de estado, listas, aprobación biométrica, dispositivos, alertas y cuenta.

## Pruebas

En CI, solo `push` a `main` o lanzamiento manual ejecuta Maven y Flutter analyze/test. No hay Actions en PR. El backend actual tiene pruebas unitarias de política temporal, firma Ed25519 y normalización de cuentas; es obligatorio ampliar a tests de integración reales con PostgreSQL, SMTP, Firebase y hardware antes de producción.

No se hizo merge ni despliegue en este trabajo.

### Docker y Firebase

En Docker se puede configurar `GUARDIAN_FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` con el JSON de la cuenta de servicio codificado en Base64, guardado únicamente en `.env` y nunca en Git. Como alternativa, usa un fichero montado en el contenedor y `GUARDIAN_FIREBASE_SERVICE_ACCOUNT_PATH`. Las notificaciones externas se envían con texto genérico para evitar mostrar detalles sensibles en la pantalla bloqueada.

## Vinculación protegida de teléfonos

Antes de aceptar una solicitud, en Android/iOS se usa **Mi cuenta → Vincular este teléfono**.
El backend requiere un código de seis dígitos enviado al correo confirmado y ligado a la
sesión de registro; caduca a los 10 minutos, tiene máximo cinco intentos y limita
solicitudes a una por minuto y ocho por hora. La API relevante es
`POST /api/v1/mobile/credentials/challenge` seguida de
`POST /api/v1/mobile/credentials` con `verificationCode`.

**Riesgo residual:** la segunda verificación sigue dependiendo del correo electrónico
y de la seguridad de la sesión; para un producto comercial se requieren MFA más fuerte,
revisión de dispositivos vinculados, atestación móvil y firma no exportable por hardware.
El teléfono debe inscribirse antes de solicitar aprobaciones que caducan en 45 segundos.


## Seguridad reforzada — actualizaciones de noviembre de 2026

- Registrar una credencial móvil exige código OTP enviado al correo validado,
  vinculado a la sesión solicitante y de un solo uso (migración `V4`).
- El token de Firebase solo puede registrarse tras demostrar posesión de la
  clave Ed25519 del teléfono previamente vinculado (firma de
  `guardian:push:v1:CREDENTIAL_ID:FCM_TOKEN`).
- Revocar una clave móvil también revoca sus tokens push.
- El agente Windows tiene modo `observe` por defecto y `protect` opcional
  solamente para evaluación controlada. En protect solicita el bloqueo **antes**
  de esperar una respuesta del celular cuando hay actividad no verificable.
- La autorización temporal no desactiva la detección de otros rostros ni el
  bloqueo preventivo por ausencia. Se han separado y probado cuatro reglas
  unitarias puras de seguridad.
- La aplicación móvil presenta filtros de alertas (todas, críticas, solicitudes
  y estado de equipos), además de un detalle adaptativo de la notificación.
- `AuthenticationRateLimitFilter` reduce intentos de abuso SMTP/credenciales
  por IP en una sola instancia. Para despliegues distribuidos se necesita
  limitación también en proxy o almacén compartido.

### Validación ejecutada

- Comparación de cambios y verificación de archivos en GitHub.
- Revisión estática de balance de delimitadores en Java y Dart editados.
- Cuatro pruebas de decisiones puras de Guardian Policy ejecutadas en
  Python 3 (satisfactorias).
- Tests adicionales de presentación Flutter y rate limiting Java publicados
  para ejecutar con SDK/Maven en CI.

**Pendiente de validación real**: `mvn verify`, `flutter analyze`,
`flutter test`, Android/iOS con Firebase, integración PostgreSQL/SMTP,
Windows con cámara física/ONNX y verificación del bloqueo real.
La rama no se ha fusionado.
