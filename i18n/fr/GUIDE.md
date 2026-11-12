# Dòng — Guide technique et projet

> Toutes les autres informations sur le projet, en français.

## Architecture

Quatre pipelines indépendants : fenêtres sur la couche bureau avec `AVPlayerLayer`, transcodage yt-dlp + ffmpeg, panneau de barre de menus et bibliothèque dessinés à la main en AppKit, démarrage automatique / surveillance de dossier / statistiques anonymes via LaunchAgent.

## Détails d'implémentation

- Chaque fenêtre dépasse l'écran de 24 pt pour masquer les coins arrondis et les bords lors du changement de bureau.
- La signature `--deep` casse les signatures de ressources imbriquées : à éviter.
- L'audio en boucle est mixé en trois seeks ; un seul laisse un clic.
- Le panneau de la barre de menus est entièrement dessiné à la main pour couvrir le verre dépoli du système.

## Débogage en ligne de commande

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

Les variables d'environnement (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) sont listées à la section 9 de l'original chinois.

## Licence et usage commercial

Le code et la documentation sont sous **GPL-3.0** ; le texte juridiquement valable est le [LICENSE](../../LICENSE) anglais. Une licence commerciale distincte existe pour les produits propriétaires : [COMMERCIAL.md](../../COMMERCIAL.md).

## Marque et ressources

Le nom « Dòng », `AppIcon.icns` et `BrandMark*.png` sont des signes de marque. Les vidéos de `presets/` et `bili/`, ainsi que les binaires ffmpeg / yt-dlp, ne sont pas dans ce dépôt.

## Contribuer et politique IA

Issues et PR sont bienvenues ; les modèles sont dans `.github/` et la CI compile l'app. Toute contribution assistée par IA doit être déclarée et relue ligne par ligne — [AI_POLICY.md](../../AI_POLICY.md).

## Confidentialité

Les statistiques anonymes sont activées par défaut et se désactivent dans les réglages. Si vous forkez le projet, passez la valeur par défaut de `isEnabled` dans `Analytics.swift` à `false`.

Texte technique complet en chinois : [技术原理.md](../../技术原理.md).

---

## Tous les documents en français

- [README.fr.md](../../README.fr.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
