# Guardian by MCode

**Guardian** es un proyecto de seguridad multiplataforma para ayudar al propietario a proteger sus dispositivos mediante presencia, reconocimiento facial local, bloqueo de sesión, incidentes y aprobación remota desde Android o iOS.

> **Estado: prototipo de arquitectura y backend base. No protege ningún dispositivo todavía.** No uses esta versión para sustituir el bloqueo del sistema operativo ni la autenticación multifactor.

## Componentes

- \`apps/mobile/\`: cliente Flutter Android/iOS para alertas y aprobación remota (pendiente de implementación).
- \`apps/desktop/\`: panel Flutter Windows/macOS/Linux (pendiente de implementación).
- \`agent/\`: agente nativo de seguridad para el bloqueo local, sensores y reconocimiento (pendiente).
- \`backend/\`: Spring Boot 3.5 + Java 21, acceso inicial restringido y esquema PostgreSQL.
- \`docs/\`: arquitectura, restricciones por plataforma, amenazas y plan de implementación.

## Arranque del backend (desarrollo)

Requisitos: Docker con Compose. Desde la raíz:

\`\`\`bash
cp .env.example .env
# Cambia GUARDIAN_DB_PASSWORD en .env antes de levantar el entorno
docker compose up --build -d
docker compose ps
curl http://localhost:8080/actuator/health
\`\`\`

El servicio expone inicialmente solo el endpoint de salud. El resto de las rutas HTTP devuelve acceso denegado deliberadamente hasta implementar autenticación fuerte, vinculación de dispositivos y autorización.

## Documentos de diseño

- [Arquitectura](docs/ARCHITECTURE.md)
- [Modelo de seguridad](docs/SECURITY.md)
- [Restricciones por plataforma](docs/PLATFORMS.md)
- [Hoja de ruta](docs/ROADMAP.md)

## Principios de seguridad

- Reconocimiento facial **local**, sin subir plantillas biométricas al servidor.
- Si no se ve el rostro, el estado es **no verificable**, no un intruso confirmado.
- Los sistemas operativos siguen siendo la autoridad para el bloqueo y el desbloqueo.
- La aprobación móvil debe comprobar biometría local, una credencial criptográfica vinculada al dispositivo y un desafío efímero de un solo uso.
- Nunca enviar contraseñas ni credenciales por correo; no rotar contraseñas automáticamente por fallos de cámara.
- No activar cámaras de manera oculta ni prometer vigilancia permanente donde el sistema operativo la impida.

Proyecto de MCode SAS. Uso restringido al propietario o administradores con autorización y consentimiento.