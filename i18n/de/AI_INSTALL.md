# Dòng — Installationshandbuch

> Die lesbare Fassung der Installationsanleitung. KI-Agenten nutzen bitte die englische AI_INSTALL.md im Repo-Stammverzeichnis.

## Offizielle Adressen

| Eintrag | Adresse |
|---|---|
| Offizielles Repo | `https://github.com/zhang-1-kael/dong` |
| Offizielle Website | `https://dongisgood.coze.site/en` |
| Stabile DMG-URL | `https://dongisgood.coze.site/api/download?channel=stable` |
| Version + SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| Installationsskript | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Regeln, die nicht gebrochen werden dürfen

- **GitHub Releases können leer sein.** Schicke niemanden dorthin und erfinde keine Asset-URL.
- **Die Object-Storage-URL nie fest codieren.** `/api/download` leitet auf eine signierte URL weiter, die abläuft.
- **Das DMG ist ad-hoc signiert und nicht notarisiert.** `com.apple.quarantine` zu entfernen ist normal; Gatekeeper darf nie systemweit deaktiviert werden.
- **Kein `sudo`, keine gelöschten oder überschriebenen Dateien, kein `curl | bash`.** Erst das Skript lesen.
- Nur Apple Silicon und macOS 13+. Intel-Macs müssen selbst kompilieren.

## Weg A — mit Terminal

Skript zuerst lesen, Probe-Lauf, dann ausführen. Vor jedem Schritt kurz erklären, was passiert.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Weg B — ohne Terminal / manuell

Von der stabilen URL laden, SHA256 mit dem Wert der Metadaten-API vergleichen und das DMG öffnen.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## Nach der Installation

In der Menüleiste erscheint das Glibber-Symbol. Anklicken, Panel öffnen, dann einen Bilibili-/YouTube-Link einfügen oder eine lokale Videodatei hineinziehen.

## Wenn etwas schiefgeht

Bei abweichender Prüfsumme sofort abbrechen. Sagt macOS, die App sei beschädigt, einmal `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` ausführen und erneut öffnen — keine systemweiten Sicherheitseinstellungen ändern.

---

## Alle Dokumente auf Deutsch

- [README.de.md](../../README.de.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
