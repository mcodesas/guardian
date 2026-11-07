# Arquitectura propuesta

## Límite de confianza

\`\`\`text
[SO Windows/macOS/Linux]   [Android/iOS]
       |                       |
   Agente local          App Flutter móvil
   - cámara/sensores     - biometría del SO
   - IA local            - clave no exportable
   - bloqueo nativo      - aprobar/rechazar
       |                       |
       +----- TLS + claves ----+
                   |
           Spring Boot API
           - cuentas/roles
           - vinculación equipos
           - desafíos remotos
           - registro de auditoría
           - notificación FCM/email
                   |
              PostgreSQL
                   |
        Evidencias cifradas (futuro)
\`\`\`

La app de escritorio Flutter solo configura y visualiza. El agente nativo ejecuta el monitoreo y debe respetar los permisos/sesión del SO. No hay reconocimiento biométrico en backend; ni fotografías ni embeddings se deben guardar en PostgreSQL. Las evidencias, si el usuario habilita su captura, se cifran y tienen retención limitada.

## Estados de identidad

- \`OWNER_CONFIRMED\`: coincidencia de confianza suficiente + controles anti-suplantación.
- \`UNKNOWN_PERSON\`: presencia de otra persona observada; decisión probabilística, no certeza absoluta.
- \`NOT_VERIFIABLE\`: no hay rostro/cámara disponible u observación inconclusa.
- \`OWNER_ABSENT\`: ausencia sostenida, según umbrales configurados.
- \`CAMERA_UNAVAILABLE\`: cámara desconectada, ocupada, tapada o denegada.

Se registra por separado la **actividad de la sesión** (no el contenido de teclas ni pantalla) y la **identidad**. Una ausencia no implica intrusión.

## Flujo propuesto: bloqueo por ausencia

1. Detección local de ausencia durante período configurable.
2. Advertencia visible al propietario, con ventana de gracia.
3. El agente solicita bloquear por la API nativa del SO; *no* cambia contraseñas.
4. Si falla el comando de bloqueo, se registra el error local; no se reporta éxito.
5. En ausencia de conectividad, la protección local continúa.

## Flujo propuesto: cara no verificable + actividad

1. Agente detecta actividad, pero la identidad no es verificable.
2. Según política, solicita el bloqueo preventivo de la sesión o abre una ventana breve para verificación.
3. Backend emite desafío de un solo uso, acotado a un dispositivo y con vencimiento corto.
4. Notificación push informa al móvil inscrito; el push **no es una credencial**.
5. App exige confirmación biométrica/PIN del SO para usar una clave privada no exportable.
6. Firma digitalmente el desafío con clave vinculada al dispositivo, sin compartirla.
7. Backend comprueba firma, usuario, sesión, desafío, vencimiento y no reutilización mediante operación transaccional.
8. Agente valida respuesta firmada/reconocida por backend para habilitar una **excepción temporal de monitoreo** de 5/15/30 minutos.
9. La aprobación no desbloquea Windows ni evita la contraseña del SO. Intrusión confirmada revoca la excepción.

## En caso de intruso

Se almacena evidencia solo si hay consentimiento y está habilitada, se bloquea la sesión inmediatamente y se envía un aviso. Una clasificación facial no debe desencadenar automáticamente una rotación de contraseña sin recuperación segura y autorización del propietario.

## APIs futuras (aún no disponibles)

- \`POST /api/v1/device-enrollments\` — vinculación criptográfica
- \`POST /api/v1/security-events\` — reporte autenticado de incidentes
- \`POST /api/v1/approval-challenges\` — desafío remoto
- \`POST /api/v1/approval-challenges/{id}/decision\` — decisión firmada
- \`GET /api/v1/me/devices\` — inventario y estado

**Estado actual:** únicamente backend base, esquema inicial y endpoint de salud. Ninguno de los endpoints anteriores está implementado.