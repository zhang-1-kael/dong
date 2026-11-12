#!/usr/bin/env python3
"""Bind every README to its own language.

Run once after editing the per-language README prose:

    python3 tools/gen_i18n_readme.py

It rewrites: screenshot paths (localized images), every link to a document
(per-language i18n/<lang>/ pages), badge labels, image alt text, and the AI
prompt block. The prompt itself becomes English on purpose — every AI tool can
read it — with a final line asking the AI to answer in the reader's language.
"""

from pathlib import Path
import re
import urllib.parse

from i18n_data import EN_PROMPT, LANGS, REPO, SITE, T

ROOT = Path(__file__).resolve().parent.parent

FILES = {
    "README.md": "en", "README.en.md": "en",
    "README.zh.md": "zh", "README.ja.md": "ja", "README.ko.md": "ko",
    "README.fr.md": "fr", "README.de.md": "de", "README.es.md": "es",
    "README.it.md": "it", "README.ru.md": "ru",
}

TECH_LABEL = {
    "en": "technical guide", "zh": "技术文档", "ja": "技術文書",
    "ko": "기술 문서", "fr": "guide technique", "de": "Technikhandbuch",
    "es": "guía técnica", "it": "guida tecnica", "ru": "техническое описание",
}

# GitHub generates heading anchors from the localized heading text. Hand-written
# <a id="..."> tags get rewritten to user-content-*, so use real heading slugs.
HEADING_SLUGS = {
    "en": ("features", "installation"),
    "zh": ("功能", "安装"),
    "ja": ("機能", "インストール"),
    "ko": ("기능", "설치"),
    "fr": ("fonctionnalités", "installation"),
    "de": ("funktionen", "installation"),
    "es": ("características", "instalación"),
    "it": ("funzionalità", "installazione"),
    "ru": ("возможности", "установка"),
}

ABOUT_TITLE = {
    "en": "About", "zh": "关于", "ja": "作者について", "ko": "소개",
    "fr": "À propos", "de": "Über den Autor", "es": "Acerca de",
    "it": "L'autore", "ru": "Об авторе",
}

# "(Chinese)"-style notes that used to explain the Chinese-only write-up.
CHINESE_NOTE = re.compile(
    r"\s*(?:\((?:Chinese|Chinesisch|en chino|en chinois|in cinese|중국어|на китайском)\)"
    r"|（(?:中国語|中文)）)"
)


def english_prompt(lang):
    return EN_PROMPT.format(repo=REPO, site=SITE, reply=T[lang]["reply"])


def localise(fn, lang):
    p = ROOT / fn
    t = p.read_text(encoding="utf-8")
    d = T[lang]
    base = f"i18n/{lang}"

    # 1. screenshots — the text inside them is now in this language too
    t = t.replace('src="assets/panel.jpg"', f'src="assets/i18n/{lang}/panel.jpg"')
    t = t.replace('src="assets/library-wide.jpg"', f'src="assets/i18n/{lang}/library.jpg"')
    t = t.replace('alt="Dòng menu bar panel"', f'alt="{d["alt_panel"]}"')  # en only
    t = t.replace('alt="Dòng wallpaper library"', f'alt="{d["alt_library"]}"')

    # 2. every document link -> this language's own copy
    for target, replacement in [
        ("AI_INSTALL_PROMPT.md", f"{base}/AI_INSTALL_PROMPT.md"),
        ("AI_INSTALL.md", f"{base}/AI_INSTALL.md"),
        ("COMMERCIAL.md", f"{base}/GUIDE.md"),
    ]:
        t = t.replace(f"]({target})", f"]({replacement})")
        t = t.replace(f'href="{target}"', f'href="{replacement}"')
    t = t.replace("[COMMERCIAL.md]", "[GUIDE.md]")

    # 2b. the Chinese technical write-up -> localized guide
    t = t.replace("[`技术原理.md`](技术原理.md)",
                  f"[{TECH_LABEL[lang]}]({base}/GUIDE.md)")
    t = t.replace("`技术原理.md`", "`GUIDE.md`")
    t = CHINESE_NOTE.sub("", t)

    # 2c. the Chinese README kept three English headings; localize them, and
    # give every language a localized "About" heading (the paragraph itself
    # stays in English — the author's own words, as requested).
    if lang == "zh":
        t = re.sub(r"^## Features$", "## 功能", t, flags=re.M)
        t = re.sub(r"^## Usage$", "## 使用方法", t, flags=re.M)
        t = re.sub(r"^### Installation$", "### 安装", t, flags=re.M)
    t = re.sub(r"^## About$", "## " + ABOUT_TITLE[lang], t, flags=re.M)

    # 2d. real heading anchors instead of hand-written ids
    t = re.sub(r'<a id="(?:features|installation)" name="(?:features|installation)"></a>\n\n', "", t)
    feat, inst = HEADING_SLUGS[lang]
    t = t.replace('href="#features"', f'href="#{feat}"')
    t = t.replace('href="#installation"', f'href="#{inst}"')

    # 3. badge labels
    ai = urllib.parse.quote(d["badge_ai"], safe="_-")
    lic = urllib.parse.quote(d["badge_license"], safe="_-")
    t = t.replace("AI_Install-One_message-7B61FF", f"AI_Install-{ai}-7B61FF")
    t = t.replace("License-GPL--3.0-5865F2", f"{lic}-GPL--3.0-5865F2")

    # 4. one universal prompt, with an explicit reply-language instruction
    t, n = re.subn(r"```text\n.*?\n```",
                   lambda m: "```text\n" + english_prompt(lang) + "\n```",
                   t, count=1, flags=re.S)
    assert n == 1, f"{fn}: prompt block not found"

    # 5. explain, in this language, why the prompt is in English (idempotent)
    if d["prompt_note"] not in t:
        m = re.search(r"> \[!IMPORTANT\]\n(?:>.*\n)+", t)
        assert m, f"{fn}: IMPORTANT block not found"
        t = t[:m.end()] + f">\n> {d['prompt_note']}\n" + t[m.end():]

    # 6. state that the whole page is in this language (idempotent)
    if d["lang_note"] not in t:
        marker = "  </p>\n</div>"
        assert marker in t, f"{fn}: language bar end not found"
        t = t.replace(marker, f"  </p>\n  <p><sub>{d['lang_note']}</sub></p>\n</div>", 1)

    # 7. a single obvious entry point to this language's documents (idempotent)
    entry = f"[{d['p']['nav']}]({base}/GUIDE.md)"
    if entry not in t:
        t, n = re.subn(r"(^📖 .*)$",
                       lambda m: m.group(1) + " · " + entry,
                       t, count=1, flags=re.M)
        assert n == 1, f"{fn}: related-files line not found"

    p.write_text(t, encoding="utf-8")
    print(f"{fn:16} → {lang:2} | screenshots, docs, badges, prompt localized")


def main():
    for fn, lang in FILES.items():
        localise(fn, lang)


if __name__ == "__main__":
    main()
