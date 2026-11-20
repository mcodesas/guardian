# Guardian — Auditoría inicial del repositorio (Paso 01/20)

Fecha: 2026-11-08. Referencia auditada: `feat/bootstrap-guardian-20261107`.

## Evidencias inspeccionadas

- Repositorio privado de GitHub: 61 archivos iniciales y 26 commits en la rama, sin merge a `main`.
- Backend: Spring Boot 3.5.7 + Java 21; dependencia Firebase Admin 9.11.0, PostgreSQL 17, Flyway V1–V4, tests Java y configuración Docker.
- Flutter: fuentes compartidas y pruebas; todavía no hay proyectos generados `android/`, `ios/`, `windows/`, `macos/`, `linux/`.
- Agente Windows: prototipo Python/OpenCV con modo `observe` predeterminado, modo `protect` experimental, policy tests.
- CI: workflow en `main` y ejecución manual, sin trigger para pull requests.

## Hallazgos y acciones del Paso 01

### A1 · Seguridad de respuestas internas — CORREGIDO EN CÓDIGO

`server.error.include-message` estaba en `always`. Se cambió a `never` para reducir filtración de detalles en errores estándar del servidor. Los controladores deben seguir devolviendo respuestas funcionales deliberadamente redactadas.

### A2 · Archivo de test generado por Flutter — PREVENCIÓN IMPLEMENTADA

El proyecto aún no contiene runners nativos. Al ejecutar `flutter create .` puede generarse un `test/widget_test.dart` de plantilla que busca una clase `MyApp` inexistente. Se ha incluido un `test/widget_test.dart` propio que prueba el logo real de Guardian, evitando esa discrepancia.

### A3 · Compilación y dependencias — PENDIENTE

Las versiones declaradas se revisaron contra documentación pública de los proveedores, pero no equivalen a un `flutter pub get` o `mvn verify` exitoso. El entorno de la auditoría dispone de Java y Python pero carece de Flutter, Dart y Maven. La compilación completa es Paso 02/03.

### A4 · Integraciones externas — PENDIENTE

No se han configurado credenciales SMTP/Firebase reales ni claves de producción. Sin SMTP no se completa registro/verificación y sin Firebase no hay push en segundo plano. Ningún secreto se debe añadir a Git.

### A5 · Seguridad biométrica — PENDIENTE

El agente usa OpenCV con modelos ONNX externos, no aporta detección de vida certificada ni un instalador nativo supervisado. El modo de protección se conserva experimental y el bloqueo real debe verificarse en Windows de pruebas.

## Comprobaciones de aceptación del paso 01

- [x] Rama y archivos auditados.
- [x] Dependencias principales y flujo de autenticación identificados.
- [x] Configuración de mensajes de error endurecida.
- [x] Test de plantilla de Flutter adaptado al nombre real de Guardian.
- [x] CI sigue sin ejecutar Actions por PR.
- [ ] Compilación real con Maven (Paso 02).
- [ ] Análisis/test real Flutter (Paso 03).
- [ ] SQL y Docker contra base real (Paso 04).

## Siguiente paso

**02. Backend verificable:** conseguir un entorno Maven Java 21, ejecutar `cd backend && mvn -B -ntp verify`, corregir el código que falle y documentar el resultado. No se declara superado antes de ejecutar tests.
