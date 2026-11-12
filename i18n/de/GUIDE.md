# Dòng — Technik- & Projekthandbuch

> Alle weiteren Informationen zum Projekt, auf Deutsch.

## Architektur

Vier unabhängige Pipelines: Fenster auf der Desktop-Ebene mit `AVPlayerLayer`, Transkodierung mit yt-dlp + ffmpeg, handgezeichnetes AppKit-Menüleistenpanel und Bibliothek sowie Autostart / Ordnerüberwachung / anonyme Statistik via LaunchAgent.

## Wichtige Implementierungsdetails

- Jedes Fenster ist 24 pt größer als der Bildschirm, um abgerundete Ecken und Ränder beim Desktop-Wechsel zu verdecken.
- `--deep`-Signatur zerstört verschachtelte Ressourcensignaturen — nicht verwenden.
- Loop-Audio wird mit drei getrennten Seeks gemischt; ein Durchgang hinterlässt ein Knacken.
- Das Menüleistenpanel wird komplett von Hand gezeichnet, um den systemeigenen Milchglaseffekt zu überdecken.

## Debugging in der Kommandozeile

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

Die Umgebungsvariablen (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) stehen in Abschnitt 9 des chinesischen Originals.

## Lizenz und kommerzielle Nutzung

Code und Dokumentation stehen unter **GPL-3.0**; rechtlich verbindlich ist der englische [LICENSE](../../LICENSE)-Text. Für proprietäre Produkte gibt es eine eigene kommerzielle Lizenz: [COMMERCIAL.md](../../COMMERCIAL.md).

## Marke und Assets

Der Name „Dòng", `AppIcon.icns` und `BrandMark*.png` sind Markenzeichen. Die Wallpaper-Videos aus `presets/` und `bili/` sowie die ffmpeg-/yt-dlp-Binaries liegen nicht im Repo.

## Mitmachen und KI-Richtlinie

Issues und PRs sind willkommen, Vorlagen liegen in `.github/`, die CI baut die App. KI-unterstützte Beiträge müssen offengelegt und Zeile für Zeile geprüft werden — [AI_POLICY.md](../../AI_POLICY.md).

## Datenschutz

Anonyme Statistik ist standardmäßig an und lässt sich in den Einstellungen abschalten. Wenn du das Projekt forkst, setze den Standardwert von `isEnabled` in `Analytics.swift` auf `false`.

Vollständige technische Ausführung auf Chinesisch: [技术原理.md](../../技术原理.md).

---

## Alle Dokumente auf Deutsch

- [README.de.md](../../README.de.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
