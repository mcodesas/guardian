# Guardian Flutter — Escritorio y móvil

Una interfaz Flutter con un solo sistema de cuenta para Windows, macOS, Linux, Android e iOS.

## Inicio rápido

Usa Flutter 3.41+ (Dart 3.11+) desde el equipo de desarrollo. Como este repositorio contiene fuentes sin los archivos generados nativos, ejecuta **una vez** desde este directorio:

```bash
flutter create --project-name guardian_app --org com.mcode.guardian --platforms=android,ios,windows,macos,linux .
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=GUARDIAN_API_URL=https://TU_SERVIDOR
```

En Android, iOS o macOS se deben usar las herramientas oficiales y permisos específicos de cada plataforma; en iOS se requiere macOS/Xcode para compilar. En Android emulador durante desarrollo puede usarse `http://10.0.2.2:8080` con las políticas de red de depuración habilitadas. En producción es obligatorio HTTPS.

### Permisos móviles

- Android: INTERNET y notificaciones (Android 13+); `local_auth` requiere una `FlutterFragmentActivity` y la configuración apropiada de AndroidX; consultar la guía del plugin para la versión usada.
- iOS: incluir `NSFaceIDUsageDescription` en Info.plist y habilitar push notifications / APNs cuando se integre Firebase.
- macOS: Keychain y permisos apropiados de la aplicación.
- Escritorio: requiere agente nativo **independiente**, aún no disponible.

## Push (optativo)

1. Crear proyecto Firebase y registrar las apps Android/iOS con identificador propio.
2. Ejecutar `dart pub global activate flutterfire_cli`, luego `flutterfire configure`.
3. Agregar configuraciones nativas Android/iOS proporcionadas por Firebase (no publicar secretos de servidor).
4. Preparar Firebase Admin en el servidor y una clave aleatoria AES-256 en `GUARDIAN_PUSH_ENCRYPTION_KEY_BASE64`.
5. En iOS, configurar APNs, capacidades de firma y permisos.

Si falta Firebase, Guardian sigue funcionando con **bandeja de alertas dentro de la aplicación y actualización por sondeo cuando está abierta**. No se entregan pushes en segundo plano sin configuración. La interfaz muestra el estado real de esta función.

### Limitaciones de seguridad pendientes

- Las claves de aprobación Ed25519 quedan cifradas mediante almacenamiento seguro del dispositivo, pero no están garantizadas como no exportables/hardware-backed.
- Para seguridad comercial de alta confianza se requiere firma mediante Android Keystore o Secure Enclave y controles anti-fraude adicionales.
- Todavía no existen pantalla de captura facial, motor ONNX ni agente de bloqueo del sistema operativo.
