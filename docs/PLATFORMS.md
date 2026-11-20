# Capacidades según plataforma

| Plataforma | Agente facial mientras se usa el escritorio | Bloqueo nativo | Aprobar desde móvil |
|---|---|---|---|
| Windows | Viable con cámara y permisos | `LockWorkStation` en sesión interactiva | Sí, mediante aplicación móvil vinculada |
| macOS | Viable sujeto a permisos TCC | Integración de sesión nativa, por validar | Sí |
| Linux | Depende de Wayland/X11, sesión y permisos | Interfaz de sesión (p.ej. logind), por validar | Sí |
| Android | Vigilancia continua sobre otras apps **no garantizada**, fuertes límites de cámara en segundo plano | `DevicePolicyManager.lockNow` solo con privilegios/condiciones apropiados | Sí |
| iOS | Una app convencional no puede observar siempre otras apps con cámara | Una app ordinaria no bloquea la pantalla completa del iPhone | Sí, Face ID/Touch ID vía SO |

Guardian inicialmente prioriza **proteger computadores**, y en iOS/Android se dedica a autorizar, consultar incidentes y administrar dispositivos. Protección móvil propia solo en los contextos que el SO permita. No prometemos modificar la contraseña de inicio de sesión de sistemas o dispositivos móviles.