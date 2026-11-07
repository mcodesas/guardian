# Guardian

Guardian by MCode es una plataforma multiplataforma de protección de dispositivos: detección local de presencia y reconocimiento facial, bloqueo por ausencia, identificación de accesos sospechosos y autorización remota desde un móvil.

> **Estado:** proyecto en fase inicial de arquitectura. No es todavía un producto de seguridad operativo.

## Principios

- Privacidad por diseño: el reconocimiento facial se realiza localmente siempre que sea posible.
- Cualquier bloqueo utiliza las APIs oficiales y permisos del sistema operativo.
- Si la identidad no se puede verificar, la aplicación solicita autorización alternativa en lugar de asumir que existe un intruso.
- Las credenciales del sistema operativo no se envían por correo y nunca se rotan sin recuperación previamente configurada.

Propiedad de MCode SAS.
