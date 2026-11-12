# Dòng — Руководство по установке

> Версия для чтения человеком. ИИ-агенты должны использовать английский AI_INSTALL.md в корне репозитория.

## Официальные адреса

| Что | Адрес |
|---|---|
| Официальный репозиторий | `https://github.com/zhang-1-kael/dong` |
| Официальный сайт | `https://dongisgood.coze.site/en` |
| Стабильная ссылка на DMG | `https://dongisgood.coze.site/api/download?channel=stable` |
| Версия и SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| Скрипт установки | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Правила, которые нельзя нарушать

- **На GitHub Releases выложена v3.31** (`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`): `Dong-3.31.dmg` и полный архив релиза. Используйте как запасной путь, если сайт недоступен; всегда проверяйте SHA256. Не выдумывайте URL других версий.
- **Не задавайте прямую ссылку объектного хранилища.** `/api/download` перенаправляет на подписанную ссылку с истекающим сроком.
- **DMG подписан ad-hoc и не нотаризован.** Удаление `com.apple.quarantine` — штатный шаг; не отключайте Gatekeeper для всей системы.
- **Никаких `sudo`, удаления или перезаписи файлов, никакого `curl | bash`.** Сначала прочитайте скрипт.
- Только Apple Silicon и macOS 13+. На Intel Mac нужно собирать из исходников.

## Способ А — есть терминал

Сначала прочитайте скрипт, сделайте пробный запуск, затем выполните. Перед каждым шагом объясняйте, что делаете.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Способ Б — без терминала / вручную

Скачайте со стабильной ссылки, сравните SHA256 со значением из API метаданных и откройте DMG.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## После установки

В строке меню появится желейный значок. Нажмите его, откройте панель и вставьте ссылку Bilibili / YouTube или перетащите локальное видео.

## Если что-то пошло не так

При несовпадении контрольной суммы сразу остановитесь. Если macOS говорит, что приложение повреждено, один раз выполните `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` и откройте снова, не меняя системные настройки безопасности.

---

## Все документы на русском

- [README.ru.md](../../README.ru.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
