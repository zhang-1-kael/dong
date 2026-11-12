# Dòng — Guía técnica y del proyecto

> El resto de la información del proyecto, en español.

## Arquitectura

Cuatro flujos independientes: ventanas en la capa del escritorio con `AVPlayerLayer`, transcodificación yt-dlp + ffmpeg, panel y biblioteca dibujados a mano en AppKit, y arranque automático / vigilancia de carpetas / estadísticas anónimas con LaunchAgent.

## Detalles clave de implementación

- Cada ventana es 24 pt mayor que la pantalla para ocultar las esquinas redondeadas y los bordes al cambiar de escritorio.
- La firma `--deep` rompe las firmas de recursos anidados: no usar.
- El audio en bucle se mezcla con tres seeks; con uno solo queda un clic.
- El panel de la barra de menús se dibuja por completo a mano para cubrir el cristal esmerilado del sistema.

## Depuración por línea de comandos

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

Las variables de entorno (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) están en la sección 9 del original chino.

## Licencia y uso comercial

Código y documentación bajo **GPL-3.0**; el texto legalmente vinculante es el [LICENSE](../../LICENSE) en inglés. Para productos de código cerrado hay una licencia comercial aparte: [COMMERCIAL.md](../../COMMERCIAL.md).

## Marca y recursos

El nombre «Dòng», `AppIcon.icns` y `BrandMark*.png` son signos de marca. Los vídeos de `presets/` y `bili/` y los binarios de ffmpeg / yt-dlp no están en este repo.

## Contribuir y política de IA

Se agradecen issues y PR; las plantillas están en `.github/` y la CI compila la app. Las contribuciones asistidas por IA deben declararse y revisarse línea por línea — [AI_POLICY.md](../../AI_POLICY.md).

## Privacidad

Las estadísticas anónimas están activadas por defecto y se desactivan en Ajustes. Si haces un fork, cambia el valor por defecto de `isEnabled` en `Analytics.swift` a `false`.

Artículo técnico completo en chino: [技术原理.md](../../技术原理.md).

---

## Todos los documentos en español

- [README.es.md](../../README.es.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
