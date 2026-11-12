# Dòng — Manuale di installazione

> Versione leggibile per le persone. Gli agenti IA devono usare l'AI_INSTALL.md in inglese nella radice del repo.

## Indirizzi ufficiali

| Elemento | Indirizzo |
|---|---|
| Repo ufficiale | `https://github.com/zhang-1-kael/dong` |
| Sito ufficiale | `https://dongisgood.coze.site/en` |
| DMG stabile | `https://dongisgood.coze.site/api/download?channel=stable` |
| Versione + SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| Script di installazione | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Regole da non infrangere

- **Le GitHub Releases possono essere vuote.** Non mandarci l'utente e non inventare un URL dell'asset.
- **Non fissare l'URL dell'object storage.** `/api/download` reindirizza a un URL firmato che scade.
- **Il DMG ha firma ad-hoc e non è notarizzato.** Rimuovere `com.apple.quarantine` è normale; non disattivare Gatekeeper a livello di sistema.
- **Niente `sudo`, né cancellazione/sovrascrittura di file, né `curl | bash`.** Leggi prima lo script.
- Solo Apple Silicon e macOS 13+. I Mac Intel devono compilare dai sorgenti.

## Percorso A — con terminale

Leggi lo script, fai una prova e poi eseguilo. Spiega ogni passo prima di lanciarlo.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Percorso B — senza terminale / installazione manuale

Scarica dall'URL stabile, confronta lo SHA256 con l'endpoint dei metadati e apri il DMG.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## Dopo l'installazione

Nella barra dei menu appare l'icona gelatinosa. Cliccala, apri il pannello e incolla un link di Bilibili / YouTube oppure trascina un video locale.

## Se qualcosa va storto

Fermati subito se il checksum non corrisponde. Se macOS dice che l'app è danneggiata, esegui una volta `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` e riaprila, senza modificare la sicurezza di sistema.

---

## Tutti i documenti in italiano

- [README.it.md](../../README.it.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
