# Guardian Agent — Windows (evaluación controlada)

Este prototipo ofrece **inscripción facial visible**, comparación local usando OpenCV YuNet/SFace, almacenamiento cifrado mediante Windows DPAPI, bloqueo de sesión con Win32, informes al backend y consultas de aprobación móvil.

**No es una versión de seguridad lista para producción.** Faltan pruebas en Windows real, anti-spoof/liveness, recuperación si falla el agente, detección de pantalla ya bloqueada, empaquetado/actualización firmada, instalación con tray visible y validación jurídica/comercial de los pesos ONNX.

## Requisitos

- Windows 10/11, cuenta interactiva y cámara autorizada.
- Python 3.11+ (Windows) y sus dependencias.
- Guardian backend accesible por HTTPS.
- Registro previo del computador en Guardian Flutter, con `deviceId` y `agentKey` creados una sola vez.
- Modelos ONNX separados: detector YuNet y reconocedor SFace, adquiridos **únicamente tras revisar licencias y derechos de uso**. No subir los pesos al repositorio.

```powershell
cd agent/windows
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt

python guardian_agent.py setup
python guardian_agent.py enroll --detector C:\modelos\yunet.onnx --recognizer C:\modelos\sface.onnx
python guardian_agent.py monitor --detector C:\modelos\yunet.onnx --recognizer C:\modelos\sface.onnx
```

En monitor aparece una ventana visible con estado y vídeo. La tecla `Q` detiene el prototipo. Ninguna instalación oculta ni capturas ocultas.

## Reglas

- Si se confirma repetidamente un rostro diferente en actividad, se solicita bloqueo nativo y se informa un posible intruso.
- Si el propietario deja de verse y no hay actividad, se solicita bloqueo tras la ausencia configurada.
- Si hay actividad con cara no verificable, se solicita autorización móvil y se bloquea si no hay respuesta válida.
- Si la red falla, el bloqueo local continúa y los eventos se encolan cifrados.
- Aprobar 5/15/30 minutos suspende temporalmente el monitoreo, nunca desbloquea Windows.
- Un retorno verdadero de `LockWorkStation()` únicamente confirma solicitud asíncrona de bloqueo, **no un bloqueo verificado**.

## Privacidad y límites

- Embeddings y evidencia JPEG guardados cifrados localmente por usuario Windows (DPAPI).
- Las fotos no se suben al backend en esta versión y no aparecen en móvil. El incidente sí se notifica con descripción.
- Modelo SFace sin detección de presencia real: una foto o vídeo podría suplantar al propietario. Se requiere liveness antes de uso comercial.
- El umbral predeterminado `0.42` es experimental, no una garantía de identidad. Recalibrar con métricas FAR/FRR por dispositivo.
- Una cámara movida, tapada o sin permisos produce `NOT_VERIFIABLE`, nunca identidad del intruso confirmada.
- Si el proceso termina, no sigue protegiendo. Requiere instalador firmado y supervisión por sesión para una versión final.
- La imagen puede contener terceros; informar y obtener consentimiento conforme a la ley aplicable.
