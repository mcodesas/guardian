# Guardian — sitio público
Página informativa estática responsive, en español, con la identidad aprobada y la imagen conceptual de la aplicación. Sin formularios de captura, analítica, dependencias externas ni promesas de disponibilidad comercial.

## Previsualizar localmente
```sh
cd apps/guardian_web
python -m http.server 8090 --bind 127.0.0.1
```
Abrir http://127.0.0.1:8090. También se puede servir con Caddy o Nginx mediante una raíz estática. No hay dominio ni publicación productiva configurados por este cambio.

El generador en `scripts/generate_brand_icons.py` crea favicon, iconos de acceso directo, App Store, Google Play, Android e iOS a partir del logo aprobado. Las imágenes WebP son versiones optimizadas del logo y mockup suministrados en la conversación. La imagen del teléfono se identifica como propuesta conceptual, no captura real. La página de privacidad es preliminar y requiere validación legal antes de distribuir.
