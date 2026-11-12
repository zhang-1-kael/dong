# Dòng — Manuel d'installation

> Version lisible par un humain. Les agents IA doivent utiliser le AI_INSTALL.md anglais à la racine du dépôt.

## Adresses officielles

| Élément | Adresse |
|---|---|
| Dépôt officiel | `https://github.com/zhang-1-kael/dong` |
| Site officiel | `https://dongisgood.coze.site/en` |
| DMG stable | `https://dongisgood.coze.site/api/download?channel=stable` |
| Version + SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| Script d'installation | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Règles à ne pas enfreindre

- **Les GitHub Releases hébergent la v3.31** (`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`) : `Dong-3.31.dmg` et l'archive complète. À utiliser en repli si le site officiel est indisponible ; vérifiez toujours le SHA256. N'inventez pas d'URL pour d'autres versions.
- **Ne codez jamais l'URL de stockage en dur.** `/api/download` redirige vers une URL signée qui expire.
- **Le DMG est signé ad-hoc et non notarisé.** Effacer `com.apple.quarantine` est normal ; ne désactivez jamais Gatekeeper globalement.
- **Pas de `sudo`, ni suppression/écrasement de fichiers, ni `curl | bash`.** Lisez d'abord le script.
- Apple Silicon et macOS 13+ uniquement. Les Mac Intel doivent compiler depuis les sources.

## Méthode A — avec un terminal

Lisez le script, faites un essai à blanc, puis exécutez-le. Expliquez chaque étape avant de la lancer.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Méthode B — sans terminal / installation manuelle

Téléchargez depuis l'URL stable, comparez le SHA256 à celui du endpoint de métadonnées, puis ouvrez le DMG.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## Après l'installation

Une icône gélatineuse apparaît dans la barre de menus. Cliquez, ouvrez le panneau, puis collez un lien Bilibili / YouTube ou glissez une vidéo locale.

## En cas de problème

Arrêtez-vous immédiatement si la somme ne correspond pas. Si macOS dit que l'app est endommagée, exécutez une fois `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` puis rouvrez-la, sans modifier la sécurité du système.

---

## Tous les documents en français

- [README.fr.md](../../README.fr.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
