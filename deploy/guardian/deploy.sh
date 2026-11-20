#!/usr/bin/env bash
# Guarded manual/CI deployment; VPS must have Docker, secrets and GHCR access.
set -Eeuo pipefail
umask 077

ROOT="${GUARDIAN_DEPLOY_ROOT:-/opt/guardian}"
COMPOSE="$ROOT/docker-compose.prod.yml"
ENV_FILE="$ROOT/.env"
STATE="$ROOT/.last-verified-image"
TAG="${1:-}"

if [[ ! "$TAG" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: se exige un SHA de 40 caracteres de imagen verificada." >&2
  exit 2
fi
for file in "$ENV_FILE" "$COMPOSE"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: archivo requerido no existe: $file" >&2
    exit 2
  fi
done

if ! command -v docker >/dev/null; then
  echo "ERROR: Docker no está instalado en este servidor." >&2
  exit 2
fi
docker compose version >/dev/null
if [[ ! -w "$ROOT" ]]; then
  echo "ERROR: no se puede escribir $ROOT" >&2
  exit 2
fi

previous=""
if [[ -f "$STATE" ]]; then previous="$(tr -d '\r\n' < "$STATE")"; fi

dc() {
  GUARDIAN_IMAGE_TAG="$TAG" docker compose \
    --project-name guardian --env-file "$ENV_FILE" -f "$COMPOSE" "$@"
}

echo "[Guardian] Validando Docker Compose..."
dc config --quiet
echo "[Guardian] Descargando imagen $TAG..."
dc pull
echo "[Guardian] Levantando contenedores..."
dc up -d --remove-orphans

health() {
  local response
  response="$(curl -fsS --max-time 5 http://127.0.0.1:8283/actuator/health)" || return 1
  [[ "$response" == *'"status":"UP"'* ]]
}
healthy=0
for attempt in $(seq 1 30); do
  if health; then healthy=1; break; fi
  sleep 3
done

if [[ "$healthy" != 1 ]]; then
  echo "ERROR: smoke test falló. Guardian NO está saludable." >&2
  dc ps >&2 || true
  dc logs --tail=100 api >&2 || true
  if [[ "$previous" =~ ^[0-9a-f]{40}$ && "$previous" != "$TAG" ]]; then
    echo "[Guardian] Intentando rollback..."
    TAG="$previous"
    dc up -d --remove-orphans || true
    if ! health; then
      echo "ERROR CRÍTICO: falló también el healthcheck tras el rollback." >&2
    fi
  fi
  exit 1
fi

printf '%s\n' "$TAG" > "$STATE"
echo "[Guardian] API comprobada: http://127.0.0.1:8283/actuator/health"
dc ps
echo "[Guardian] Despliegue OK: $TAG"
