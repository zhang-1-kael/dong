# Dòng — Guida tecnica e al progetto

> Tutte le altre informazioni sul progetto, in italiano.

## Architettura

Quattro pipeline indipendenti: finestre sul livello desktop con `AVPlayerLayer`, transcodifica yt-dlp + ffmpeg, pannello e libreria disegnati a mano in AppKit, e avvio automatico / monitoraggio cartelle / statistiche anonime tramite LaunchAgent.

## Dettagli implementativi chiave

- Ogni finestra è 24 pt più grande dello schermo per nascondere gli angoli arrotondati e i bordi nel cambio desktop.
- La firma `--deep` rompe le firme annidate delle risorse: da evitare.
- L'audio in loop si mixa con tre seek separati; con uno solo resta un clic.
- Il pannello della barra dei menu è disegnato a mano per coprire il vetro smerigliato di sistema.

## Debug da riga di comando

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

Le variabili d'ambiente (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) sono nella sezione 9 dell'originale cinese.

## Licenza e uso commerciale

Codice e documentazione sono sotto **GPL-3.0**; il testo legalmente vincolante è il [LICENSE](../../LICENSE) in inglese. Per prodotti closed-source esiste una licenza commerciale separata: [COMMERCIAL.md](../../COMMERCIAL.md).

## Marchio e risorse

Il nome «Dòng», `AppIcon.icns` e `BrandMark*.png` sono segni distintivi. I video di `presets/` e `bili/` e i binari ffmpeg / yt-dlp non sono in questo repo.

## Contribuire e policy IA

Issue e PR sono benvenute, i modelli sono in `.github/` e la CI compila l'app. I contributi assistiti da IA vanno dichiarati e rivisti riga per riga — [AI_POLICY.md](../../AI_POLICY.md).

## Privacy

Le statistiche anonime sono attive per impostazione predefinita e si disattivano nelle impostazioni. Se fai un fork, imposta a `false` il valore di `isEnabled` in `Analytics.swift`.

Approfondimento tecnico completo in cinese: [技术原理.md](../../技术原理.md).

---

## Tutti i documenti in italiano

- [README.it.md](../../README.it.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
