# Demander à une IA d'installer Dòng

Copiez un bloc, collez-le dans un assistant capable d'exécuter des commandes sur votre Mac, et c'est fait.

> [!TIP]
> Le prompt ci-dessous est volontairement en anglais pour être compris par tous les outils d'IA. Sa dernière ligne demande à l'IA de répondre en français : vous ne lisez donc que du français.

## ① Recommandé — le prompt universel

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in French.
```

Copiez tout le bloc. L'IA télécharge le DMG officiel, vérifie son SHA256, installe l'app et effectue la confirmation unique de macOS au premier lancement. Le choix proposé par l'app au premier démarrage reste à vous.

## ② Autre option — le prompt en français

```text
Installe Dòng, une app de fond d'écran animé pour macOS, sur ce Mac.

Dépôt officiel : https://github.com/zhang-1-kael/dong
Site officiel : https://dongisgood.coze.site/en
Manuel d'installation pour IA : AI_INSTALL.md dans ce dépôt ; script : install.sh

Lis d'abord le manuel et le script, puis suis le manuel : télécharge depuis l'URL stable officielle, vérifie le SHA256 fourni par l'API officielle, installe dans /Applications, effectue la confirmation unique de macOS au premier lancement, lance l'app, puis indique le résultat et la prise en main.
N'utilise que les domaines officiels ci-dessus ; pas de sudo, pas de suppression ou d'écrasement de mes fichiers, aucune modification des réglages de sécurité du système. Sans accès au terminal, donne-moi simplement les commandes les plus courtes, sans prétendre avoir installé quoi que ce soit.
```

Si votre assistant comprend mieux le français, utilisez plutôt ce bloc.

## ③ Préférer trois commandes à la main

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

Ajoutez --dry-run pour un aperçu : rien n'est téléchargé ni modifié.

---

## Tous les documents en français

- [README.fr.md](../../README.fr.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
