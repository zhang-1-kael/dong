# Dòng von einer KI installieren lassen

Einen Block kopieren, in einen Assistenten einfügen, der Befehle auf deinem Mac ausführen kann — fertig.

> [!TIP]
> Der Prompt unten ist absichtlich auf Englisch, damit ihn jedes KI-Werkzeug versteht. Die letzte Zeile verlangt eine Antwort auf Deutsch — du liest also durchgehend Deutsch.

## ① Empfohlen — der universelle Prompt

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in German.
```

Den gesamten Block kopieren. Die KI lädt das offizielle DMG, prüft die SHA256, installiert die App und erledigt die einmalige Bestätigung von macOS beim ersten Start. Die Auswahl beim ersten App-Start triffst du selbst.

## ② Alternative — der Prompt auf Deutsch

```text
Bitte installiere Dòng, eine Live-Wallpaper-App für macOS, auf diesem Mac.

Offizielles Repo: https://github.com/zhang-1-kael/dong
Offizielle Website: https://dongisgood.coze.site/en
Installationshandbuch für KIs: AI_INSTALL.md im Repo; Ein-Klick-Skript: install.sh

Lies zuerst Handbuch und Skript und folge dann dem Handbuch: von der offiziellen stabilen URL herunterladen, SHA256 aus der offiziellen API prüfen, nach /Applications installieren, die einmalige Bestätigung von macOS beim ersten Start erledigen, die App starten und mir Ergebnis und Bedienung melden.
Nur die oben genannten offiziellen Domains verwenden; kein sudo, keine meiner Dateien löschen oder überschreiben, keine systemweiten Sicherheitseinstellungen ändern. Ohne Terminal-Zugriff gib mir nur die kürzesten kopierbaren Befehle — behaupte nicht, etwas installiert zu haben.
```

Wenn dein KI-Assistent Deutsch besser versteht, kannst du diesen Block nehmen.

## ③ Lieber drei Befehle selbst eingeben

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

Mit --dry-run wird nur angezeigt, was passieren würde — kein Download, keine Änderung.

---

## Alle Dokumente auf Deutsch

- [README.de.md](../../README.de.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
