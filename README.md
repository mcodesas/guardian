# Guardian by MCode

**Guardian** es una plataforma multiplataforma de seguridad para propietarios de dispositivos. La aplicación integra identidad, autorizaciones móviles, inventario de computadores, alertas y políticas de seguridad, con reconocimiento facial y bloqueo local planificados para el agente nativo.

> **Estado:** versión inicial de desarrollo. Las APIs de identidad/dispositivos/aprobaciones y la interfaz Flutter están implementadas en la rama de desarrollo. **Se incluye un prototipo evaluativo Windows del agente facial y bloqueo; aún no está validado, integrado ni listo para producción.** No usar como sustituto de las protecciones del sistema operativo.

## Diseño del producto

- **Autenticación:** una cuenta por propietario, verificación por email, contraseña BCrypt, tokens revocables con rotación y recuperación por código.
- **Backend:** Java 21, Spring Boot 3.5.7, PostgreSQL 17, Flyway, correo SMTP y Firebase Cloud Messaging opcional.
- **Cliente:** Flutter para Windows, macOS, Linux, Android e iOS (fuentes compartidas, corredores nativos generados con Flutter SDK).
- **Aprobación móvil:** huella/Face ID local, firma Ed25519 vinculada al celular, duración de 5/15/30 minutos y vencimiento.
- **Notificaciones:** bandeja visual centralizada, correo opcional y FCM optativo configurado por el propietario.
- **Proximidad y bloqueo:** primer prototipo Python Windows de cámara, bloqueo Win32 y aprobación remota; requiere modelos ONNX externos y pruebas en equipos reales.

## Primer arranque local (backend)

Instala Docker + Compose. Copia el ejemplo de entorno:

```bash
cp .env.example .env
```

Reemplaza:
- `GUARDIAN_DB_PASSWORD`: contraseña aleatoria distinta a desarrollo.
- `GUARDIAN_AUTH_PEPPER`: secreto aleatorio de mínimo 32 caracteres, estable en el servidor.
- `GUARDIAN_SMTP_HOST`, `GUARDIAN_SMTP_USERNAME`, `GUARDIAN_SMTP_PASSWORD`, `GUARDIAN_MAIL_FROM`: SMTP para verificación y recuperación.
- Opcional: Firebase service account con acceso únicamente al backend y clave AES 256 bits para tokens FCM.

```bash
docker compose up -d --build
curl http://localhost:8080/actuator/health
```

La API se publica únicamente en localhost; usa proxy inverso HTTPS y controles de firewall para acceso remoto. No subir `.env`.

## Cliente Flutter

En `apps/guardian_flutter`:

```bash
flutter create --project-name guardian_app --org com.mcode.guardian --platforms=android,ios,windows,macos,linux .
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=GUARDIAN_API_URL=https://TU_DOMINIO_SEGURO
```

Guía completa: [Flutter](apps/guardian_flutter/README.md). Prototipo de agente: [Windows](agent/windows/README.md).

## Documentación

- [Implementación y APIs](docs/IMPLEMENTATION.md)
- [Arquitectura](docs/ARCHITECTURE.md)
- [Seguridad](docs/SECURITY.md)
- [Restricciones por plataforma](docs/PLATFORMS.md)
- [Plan de fases](docs/ROADMAP.md)

**Organización:** MCode SAS. **Rama de implementación:** `feat/bootstrap-guardian-20261107`.

## Plan de desarrollo por pasos

Guardian está organizado en [4 fases y 20 pasos](docs/PLAN_20_PASOS.md). La [auditoría inicial](docs/QA_BASELINE_20261108.md) registra hallazgos y el estado real de las pruebas antes de continuar con el backend.
