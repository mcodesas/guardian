# Hoja de ruta

## Fase 0 — Inicio del proyecto (esta rama)

- [x] Repositorio y rama de desarrollo.
- [x] Arquitectura, amenazas, matriz de plataformas y límites funcionales.
- [x] Backend mínimo Spring Boot + PostgreSQL/Flyway con acceso restringido.
- [x] Política pura y pruebas unitarias para validez de aprobación temporal.
- [ ] Ejecutar compilación/pruebas en CI o entorno con Maven.
- [ ] Definir marca visual y experiencia de registro.

## Fase 1 — Windows local

- [ ] Crear agente Windows con API de bloqueo real, señales de inactividad y recuperación de fallos.
- [ ] Implementar cámara local, detección facial, embeddings y anti-spoofing.
- [ ] Asistente Flutter para inscripción explícita del propietario.
- [ ] Protección por ausencia y modo solo alerta; logs estructurados.
- [ ] Pruebas de falsos positivos, cámara obstruida, ausencia de red y desinstalación.

## Fase 2 — Identidad y móvil

- [ ] Autenticación de usuarios en backend, vinculación de agentes y móviles.
- [ ] Claves no exportables, desafío firmado, validez de un solo uso y revocación.
- [ ] App Flutter Android/iOS para aprobar o rechazar con huella/Face ID.
- [ ] Aprobación temporal de 5/15/30 minutos; siempre revocable.
- [ ] FCM, email seguro, cola local offline y deduplicación.

## Fase 3 — Evidencias y expansión

- [ ] Evidencias cifradas y política de retención; historial y auditoría.
- [ ] macOS, Linux con pruebas por gestor de sesión.
- [ ] Capacidades de Android compatibles con su modelo de permisos.
- [ ] Seguridad avanzada y gestión de rotación de credenciales **solo en cuentas compatibles**, con recuperación segura opt-in.

## Criterios mínimos de aceptación

No liberar el producto como seguridad activa hasta verificar bloqueos reales en hardware, ausencia de evasión obvia, retención y consentimiento, alta/baja de dispositivos, vencimiento y revocación de aprobaciones y recuperación de propietario.