# Guardian — Plan de entrega: 4 fases, 20 pasos

Fecha de referencia: 2026-11-08
Rama de trabajo: `feat/bootstrap-guardian-20261107`.
Regla: mantener los cambios fuera de `main`; PR/merge solo después de revisión/autorización explícita. Las acciones automáticas no deben ejecutarse por PR para limitar consumo.

## Fase 1 — Estabilización de la base (pasos 1–5)

- [x] **01. Auditoría inicial:** inspeccionar estructura, dependencias, seguridad y CI; publicar hallazgos y correcciones mínimas de configuración. Véase `QA_BASELINE_20261108.md`. **Esto no implica compilación aprobada.**
- [ ] **02. Backend verificable:** ejecutar `mvn verify`, resolver errores de compilación y tests Java.
- [ ] **03. Flutter verificable:** generar runners oficiales, ejecutar `flutter pub get`, `flutter analyze` y `flutter test`; corregir errores y revisar adaptabilidad básica.
- [ ] **04. PostgreSQL/identidad:** levantar Docker, verificar Flyway V1–V4, registro, verificación SMTP, autenticación, refresco, revocación y aislamiento entre cuentas.
- [ ] **05. Integración base y CI:** validar endpoints críticos, pipeline principal, fallos y arranque desde cero, sin activar workflows en PR.

**Salida de fase:** backend y cliente compilan y pasan pruebas automatizadas; migraciones y autenticación verificadas con PostgreSQL de prueba; informe de QA y reproducción.

## Fase 2 — Windows protegido (pasos 6–10)

- [ ] **06. Agente de sesión estable:** lifecycle, inicio al entrar al escritorio, configuración segura y supervisión explícita, sin vigilancia oculta.
- [ ] **07. Cámara y enrolamiento:** permisos, selección de cámara, consentimiento y plantillas faciales cifradas localmente.
- [ ] **08. Reconocimiento robusto:** calibración, liveness/anti-spoofing, falsos positivos/negativos y estados no verificables.
- [ ] **09. Ausencia y manipulación:** detección de ausencia, cámara desconectada/tapada, señal de actividad y verificación alternativa.
- [ ] **10. Bloqueo nativo:** pruebas reales de LockWorkStation, recuperación normal de Windows, evidencias cifradas y funcionamiento sin red.

**Salida de fase:** Windows bloquea de forma verificable, recuperable y con pruebas contra accesos indebidos. No rotar contraseñas por ausencia de cámara.

## Fase 3 — App móvil y autorizaciones (pasos 11–15)

- [ ] **11. Integración nativa Android/iOS:** runners, firma, permisos, navegación y misma cuenta Guardian.
- [ ] **12. Vinculación de confianza:** códigos de enrolamiento, claves no exportables de plataforma y biometría de sistema; revocación.
- [ ] **13. Aprobación remota:** aprobar 5/15/30 min o rechazar; firmas, vencimiento, protección contra repetición y bloqueos locales.
- [ ] **14. Push real:** Firebase/APNs, notificaciones privadas, apertura de detalle y sincronización cuando vuelve a abrir la app.
- [ ] **15. QA extremo a extremo:** móvil + computador real, pérdida de red, teléfono extraviado, cámara inválida, aprobaciones vencidas y reintentos.

**Salida de fase:** propietario recibe, revisa y responde en teléfono; la decisión no reemplaza la contraseña del SO.

## Fase 4 — Calidad y lanzamiento (pasos 16–20)

- [ ] **16. Interfaz premium:** diseño responsive consistente, onboarding, accesibilidad, animaciones discretas y vistas de incidentes.
- [ ] **17. Observabilidad y privacidad:** diagnóstico centralizado, sanitización, retención y consentimiento biométrico.
- [ ] **18. QA y auditoría de seguridad:** regresión completa y E2E, carga, recuperación, explotación de tokens, permisos y revisión independiente.
- [ ] **19. Distribución:** instaladores firmados, actualizaciones seguras, configuraciones por entorno, Docker de producción y backups.
- [ ] **20. Beta controlada:** despliegue, pruebas reales en usuarios autorizados, corrección de incidencias y proceso de publicación compatible por plataforma.

**Salida de fase:** lanzamiento controlado. La protección completa del sistema Android/iOS NO está prometida porque el SO restringe cámara de fondo y bloqueo general.

## Reglas transversales

1. Cada paso requiere evidencia verificable: archivos, pruebas ejecutadas y resultado documentado.
2. No presentar revisiones estáticas como pruebas ejecutadas.
3. No activar bloqueo experimental en el dispositivo de uso diario.
4. La biometría se procesa localmente y los datos requieren consentimiento explícito.
5. Priorizar Windows + Android/iOS antes de ampliar protección a macOS y Linux.
