# Guardian: Docker, promociones y despliegue

**Estado:** archivos de infraestructura versionados. Esto NO demuestra que Docker se haya ejecutado en el VPS ni que Guardian proteja dispositivos.

## Flujo obligatorio

`feature/* → dev → test → stage → main`, siempre mediante pull requests. La CI se ejecuta al **push en las ramas destino**, no al abrir PR para evitar gastos de Actions en PR. No promover si una validación real está fallida o pendiente.

- `dev`: Maven, pruebas de políticas del agente, Flutter analyze/test/build APK y Docker Compose smoke.
- `test`: repetir validaciones contra un entorno efímero nuevo.
- `stage`: repetir checks y comprobar configuración de preproducción.
- `main`: publicar `ghcr.io/mcodesas/guardian-api:<sha>` y desplegar en VPS **solo si** están los secretos de SSH y el servidor preparado. Si faltan credenciales, el job falla claramente, sin marcar despliegue exitoso.

La interfaz Flutter y el agente Windows **no son contenedores**: requieren compilación e instalación nativa en cada plataforma. Docker sirve para backend + PostgreSQL.

## Local

```bash
cp .env.example .env
# Generar valores aleatorios distintos para GUARDIAN_DB_PASSWORD y GUARDIAN_AUTH_PEPPER.
docker compose config
docker compose up -d --build
docker compose ps
curl -fsS http://127.0.0.1:8080/actuator/health
docker compose logs --tail=120 backend
```

`health UP` significa que backend/BD están accesibles, no que correo, Firebase, cámara, anti-spoofing o cierre remoto funcionen.

## VPS Ubuntu: /opt/guardian

Guardian funciona **aislado de BarLytics**: proyecto Compose, red privada, volumen PostgreSQL, puerto localhost `8283` y credenciales independientes.

```bash
sudo install -d -m 750 /opt/guardian
sudo cp deploy/guardian/docker-compose.prod.yml /opt/guardian/
sudo cp deploy/guardian/deploy.sh /opt/guardian/
sudo cp deploy/guardian/.env.production.example /opt/guardian/.env
sudo chmod 600 /opt/guardian/.env
sudo chmod 750 /opt/guardian/deploy.sh
sudo nano /opt/guardian/.env
```

Valores obligatorios: contraseña de base aleatoria, pepper de autenticación independiente, SMTP y una imagen etiquetada por SHA de 40 caracteres. Configura credenciales GHCR de solo lectura si la imagen es privada (`docker login ghcr.io`) y proxy inverso **HTTPS** de Guardian. El ejemplo Caddy es válido solo cuando Caddy corre en el mismo host (no en un contenedor separado).

```bash
/opt/guardian/deploy.sh SHA_GITHUB_DE_40_CARACTERES
curl -fsS http://127.0.0.1:8283/actuator/health
docker compose -f /opt/guardian/docker-compose.prod.yml ps
```

El script comprueba `docker compose config`, descarga imagen, levanta servicios, espera salud y revierte el **tag de la API** al último saludable si falla. **No revierte las migraciones de PostgreSQL**: antes de desplegar un esquema incompatible, hay que preparar estrategia de migración y copia de seguridad.

## Secretos GitHub faltantes para ejecutar despliegue automático

- `GUARDIAN_SSH_HOST`: hostname del VPS
- `GUARDIAN_SSH_USER`: usuario limitado que gestiona `/opt/guardian`
- `GUARDIAN_SSH_PRIVATE_KEY`: clave privada SSH dedicada
- `GUARDIAN_SSH_KNOWN_HOSTS`: clave pública del host SSH verificada

Estos secretos no se guardan ni inventan dentro de Git. La base y el SMTP deben estar configurados previamente en el VPS. No exponer públicamente ni PostgreSQL ni la API por HTTP.

## Validación de producto aún pendiente

- Ejecuciones completas Maven, Flutter y Docker green, y test end-to-end contra PostgreSQL.
- SMTP/Firebase reales, apertura de notificaciones con la app cerrada, pruebas de firmas y caducidad.
- Reconocimiento facial con liveness, pruebas FAR/FRR, cámara tapada, permisos y recuperación del propietario.
- Test de Windows LockWorkStation y de actualizaciones del agente en hardware real.
- Pruebas de aislamiento multiusuario, seguridad de tokens, accesibilidad y retención biométrica.

**La producción no estará lista solo porque el endpoint health responda 200.**
