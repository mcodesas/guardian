# Seguridad y privacidad: requisitos obligatorios

## Adversarios y riesgos

- Persona que conoce la contraseña del sistema.
- Usuario que tapa/desconecta la cámara.
- Foto, video o máscara usados para engañar al reconocimiento.
- Dispositivo móvil robado o sesión push comprometida.
- Repetición/reenvío de aprobaciones antiguas.
- Agente local detenido por una cuenta con permisos administrativos.
- Pérdida de conexión o error en el servidor.

## Controles

1. La inferencia facial se ejecutará en el equipo protegido. Embeddings en almacenamiento seguro del dispositivo, cifrados, no reversibles a nivel de protocolo y eliminables por el usuario.
2. La captura de fotografías será explícita, visible, con retención configurable y finalidad delimitada; no se subirán imágenes continuamente.
3. Liveness reduce suplantación pero no la elimina. Registrar confianza y permitir revisión; no afirmar certeza de identidad.
4. Un sensor ausente equivale a identidad no verificable; no debe causar rotación de contraseñas.
5. Las autorizaciones remotas requerirán desafío efímero, firma con credencial vinculada, autenticación biométrica local y verificación transaccional de un solo uso.
6. Toda comunicación usa TLS. Los tokens/secretos nunca se registran en logs ni repositorio; usar almacenes seguros del SO.
7. Un dispositivo móvil puede revocarse; su pérdida exige invalidar credenciales y desafíos pendientes.
8. Evidencias cifradas en reposo y acceso con autorización granular y auditoría.
9. Cuotas de notificaciones, rate limiting y protección contra solicitudes repetidas para prevenir spam de aprobación.
10. El bloqueo se hace mediante APIs soportadas, con comprobación de resultado; la app jamás intenta cambiar silenciosamente contraseñas de cuentas Microsoft, Apple ID o PIN de un móvil.
11. Procedimiento de recuperación fuera de banda: el usuario conserva acceso con las credenciales del SO incluso si Guardian deja de funcionar.
12. Cuando una persona con permisos administrativos controla la máquina, puede detener el agente. Guardian no ofrece protección absoluta contra administración hostil.
13. Consentimiento e información para toda persona autorizada; cumplir la regulación aplicable de biometría y datos personales, incluida Colombia (Ley 1581 de 2012).

## Política de bloqueo sugerida

- Propietario ausente: bloqueo preventivo tras período configurado.
- Cámara perdida: advertencia y verificación alternativa; no atribuir identidad.
- Intrusión confirmada: bloqueo inmediato y evidencia opcional.
- Sin red: política local de bloqueo activa. Desafíos remotos no permiten acceso hasta recibir respuesta válida.
- Aprobación vigente: excepción **solo de monitoreo** por 5, 15 o 30 minutos, revocable ante incidente confirmado.

## Revisión antes de producción

Análisis de impacto de datos biométricos, pruebas anti-spoof, modelado de amenazas, simulaciones de bloqueo indebido, testing de recuperación, revisión de permisos, auditoría de dependencias, análisis estático y revisión independiente.