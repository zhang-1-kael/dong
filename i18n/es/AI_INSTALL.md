# Dòng — Manual de instalación

> Versión legible para personas. Los agentes de IA deben usar el AI_INSTALL.md en inglés de la raíz del repo.

## Direcciones oficiales

| Elemento | Dirección |
|---|---|
| Repo oficial | `https://github.com/zhang-1-kael/dong` |
| Sitio oficial | `https://dongisgood.coze.site/en` |
| DMG estable | `https://dongisgood.coze.site/api/download?channel=stable` |
| Versión + SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| Script de instalación | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Reglas que no se pueden romper

- **GitHub Releases ya tiene la v3.31** (`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`): `Dong-3.31.dmg` y el paquete completo de la versión. Úsalo como alternativa si el sitio oficial falla; verifica siempre el SHA256. No inventes URLs de otras versiones.
- **No fijes la URL del almacenamiento de objetos.** `/api/download` redirige a una URL firmada que caduca.
- **El DMG tiene firma ad-hoc y no está notarizado.** Limpiar `com.apple.quarantine` es normal; nunca desactives Gatekeeper globalmente.
- **Nada de `sudo`, ni borrar/sobrescribir archivos, ni `curl | bash`.** Lee el script antes.
- Solo Apple Silicon y macOS 13+. Los Mac Intel deben compilar desde el código.

## Vía A — con terminal

Lee el script, haz una simulación y luego ejecútalo. Explica cada paso antes de lanzarlo.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Vía B — sin terminal / instalación manual

Descarga desde la URL estable, compara el SHA256 con el endpoint de metadatos y abre el DMG.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## Después de instalar

Aparece el icono de gelatina en la barra de menús. Ábrelo, despliega el panel y pega un enlace de Bilibili / YouTube o arrastra un vídeo local.

## Si algo falla

Detente de inmediato si el checksum no coincide. Si macOS dice que la app está dañada, ejecuta una vez `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` y vuelve a abrirla, sin tocar la seguridad del sistema.

---

## Todos los documentos en español

- [README.es.md](../../README.es.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
