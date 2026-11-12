# Попросить ИИ установить Dòng

Скопируйте блок и вставьте его в помощника, который может выполнять команды на вашем Mac. На этом всё.

> [!TIP]
> Промпт ниже намеренно написан по-английски, чтобы его понял любой ИИ-инструмент. Последняя строка просит отвечать по-русски, поэтому всё, что вы читаете, остаётся на русском.

## ① Рекомендуется — универсальный промпт

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Russian.
```

Скопируйте весь блок. ИИ скачает официальный DMG, проверит SHA256, установит приложение и выполнит однократное подтверждение macOS при первом запуске. Выбор при первом запуске самого приложения оставьте за собой.

## ② Альтернатива — промпт на русском

```text
Установи на этом Mac приложение Dòng — живые обои для macOS.

Официальный репозиторий: https://github.com/zhang-1-kael/dong
Официальный сайт: https://dongisgood.coze.site/en
Инструкция для ИИ: AI_INSTALL.md в репозитории; скрипт установки: install.sh

Сначала прочитай инструкцию и скрипт, затем действуй по инструкции: скачай установщик со стабильной официальной ссылки, проверь SHA256 из официального API, установи в /Applications, выполни однократное подтверждение macOS при первом запуске, запусти приложение и сообщи результат и как им пользоваться.
Используй только указанные официальные домены; без sudo, не удаляй и не перезаписывай мои файлы, не меняй системные настройки безопасности. Если доступа к терминалу нет, просто дай самые короткие команды и не говори, что установка выполнена.
```

Если ваш ИИ-помощник лучше понимает русский, используйте этот блок.

## ③ Хотите выполнить три команды сами

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

С --dry-run будет только предварительный показ: ничего не скачивается и не меняется.

---

## Все документы на русском

- [README.ru.md](../../README.ru.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
