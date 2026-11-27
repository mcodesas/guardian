# Guardian — identidad visual aprobada
- `guardian-logo.webp`: logo aprobado, optimizado a 1024 px.
- `app-mockup.webp`: propuesta visual aprobada para la aplicación móvil; no es una captura de producto.
- Paleta: azul noche, azul eléctrico y platino.
- No se rediseñó la geometría. La conversión a WebP usa compresión de alta calidad y conserva la apariencia.
- Generar todas las resoluciones de distribución: `python -m pip install Pillow` y `python scripts/generate_brand_icons.py`.
- Ejecutar con `--apply` después de `flutter create` para instalar iconos en los runners Android/iOS/Windows y en la web. Validar el icono final en dispositivos reales. Los PNG derivados se generan de forma reproducible y no duplican los archivos fuente en Git.
