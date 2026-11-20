# Guardian Native Agent

Agente local planeado con adaptadores por sistema operativo.

Responsabilidades:
- detectar presencia/ausencia y eventos de actividad de sesión (sin almacenar teclas);
- leer cámara de forma visible y autorizada;
- ejecutar inferencia facial local y controles anti-suplantación;
- bloquear mediante APIs nativas y verificar el resultado;
- recibir excepciones de monitoreo firmadas y con duración finita;
- registrar incidentes en cola cifrada offline.

**Todavía no hay agente ejecutable.** La arquitectura debe distinguir `UNKNOWN_PERSON` de `NOT_VERIFIABLE`; la pérdida de cámara no confirma intrusión.