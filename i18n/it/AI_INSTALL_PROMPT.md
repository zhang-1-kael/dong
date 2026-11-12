# Chiedi a un'IA di installare Dòng

Copia un blocco, incollalo in un assistente che può eseguire comandi sul tuo Mac e hai finito.

> [!TIP]
> Il prompt è scritto apposta in inglese così qualsiasi strumento IA lo capisce. L'ultima riga chiede di rispondere in italiano: quindi tutto quello che leggi resta in italiano.

## ① Consigliato — il prompt universale

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Italian.
```

Copia tutto il blocco. L'IA scarica il DMG ufficiale, verifica lo SHA256, installa l'app e completa la conferma una tantum di macOS al primo avvio. La scelta iniziale dell'app la fai tu.

## ② Alternativa — il prompt in italiano

```text
Installa Dòng, un'app di sfondo animato per macOS, su questo Mac.

Repository ufficiale: https://github.com/zhang-1-kael/dong
Sito ufficiale: https://dongisgood.coze.site/en
Manuale di installazione per IA: AI_INSTALL.md nel repository; script: install.sh

Leggi prima il manuale e lo script, poi segui il manuale: scarica dall'endpoint stabile ufficiale, verifica lo SHA256 dell'API ufficiale, installa in /Applications, completa la conferma una tantum di macOS al primo avvio, avvia l'app e riportami risultato e istruzioni d'uso.
Usa solo i domini ufficiali indicati; niente sudo, non eliminare o sovrascrivere i miei file, non modificare le impostazioni di sicurezza di sistema. Se non hai accesso alla terminale, dammi solo i comandi più brevi e non fingere di aver installato qualcosa.
```

Se il tuo assistente capisce meglio l'italiano, puoi usare questo blocco.

## ③ Preferisci digitare tre comandi da solo

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

Aggiungi --dry-run per una simulazione: non scarica nulla e non modifica il sistema.

---

## Tutti i documenti in italiano

- [README.it.md](../../README.it.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
