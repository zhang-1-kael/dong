# Pide a una IA que instale Dòng

Copia un bloque, pégalo en un asistente que pueda ejecutar comandos en tu Mac y listo.

> [!TIP]
> El prompt está escrito en inglés a propósito para que cualquier herramienta de IA lo entienda. Su última línea pide responder en español, así que todo lo que lees sigue en español.

## ① Recomendado — el prompt universal

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Spanish.
```

Copia el bloque completo. La IA descarga el DMG oficial, verifica el SHA256, instala la app y completa la confirmación única de macOS al abrirla por primera vez. La elección inicial de la app la haces tú.

## ② Alternativa — el prompt en español

```text
Instala Dòng, una app de fondo de pantalla animado para macOS, en este Mac.

Repositorio oficial: https://github.com/zhang-1-kael/dong
Sitio oficial: https://dongisgood.coze.site/en
Manual de instalación para IA: AI_INSTALL.md en ese repositorio; script: install.sh

Lee primero el manual y el script y sigue sus indicaciones: descarga desde el endpoint estable oficial, verifica el SHA256 de la API oficial, instala en /Applications, completa la confirmación única de macOS en el primer inicio, abre la app y dime el resultado y cómo usarla.
Usa solo los dominios oficiales indicados; nada de sudo, no borres ni sobrescribas mis archivos, no cambies ajustes de seguridad del sistema. Si no tienes acceso a la terminal, dame solo los comandos más cortos y no finjas haber instalado nada.
```

Si tu asistente entiende mejor el español, puedes usar este bloque.

## ③ Prefieres ejecutar tres comandos tú mismo

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

Añade --dry-run para una simulación: no descarga nada ni cambia el sistema.

---

## Todos los documentos en español

- [README.es.md](../../README.es.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
