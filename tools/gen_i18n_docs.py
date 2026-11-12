#!/usr/bin/env python3
"""Render one complete set of documents per language into i18n/<lang>/.

Each README links only into its own language directory, so a reader who picks
a language never lands on a Chinese or English page. The one exception is the
GPL-3.0 LICENSE text, which stays in English for legal reasons and is always
accompanied by a localized summary in GUIDE.md.
"""

from pathlib import Path
import json
import re

from i18n_data import EN_PROMPT, INSTALL, LANGS, PLACEHOLDERS, REPO, SITE, T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "i18n"

README_FILE = {
    "en": "README.md", "zh": "README.zh.md", "ja": "README.ja.md",
    "ko": "README.ko.md", "fr": "README.fr.md", "de": "README.de.md",
    "es": "README.es.md", "it": "README.it.md", "ru": "README.ru.md",
}

# Short titles/leads that are not part of the shared data table.
EXTRA = {
    "en": ("Installation manual", "A readable version of the installation reference. AI agents should use the English AI_INSTALL.md in the repo root.", "Technical & project guide", "Everything else about the project, in English."),
    "zh": ("安装手册", "给读者看的安装参考。AI 代理请直接读仓库根目录的英文版 AI_INSTALL.md。", "技术与项目文档", "本项目的其它说明，全部使用简体中文。"),
    "ja": ("インストール手順書", "人間が読むための手順書です。AI エージェントはリポジトリ直下の英語版 AI_INSTALL.md を参照してください。", "技術・プロジェクト文書", "プロジェクトに関するその他の説明を、すべて日本語でまとめています。"),
    "ko": ("설치 안내서", "사람이 읽는 설치 참고 문서입니다. AI 에이전트는 저장소 루트의 영문 AI_INSTALL.md 를 사용하세요.", "기술 및 프로젝트 문서", "프로젝트의 나머지 설명을 모두 한국어로 정리했습니다."),
    "fr": ("Manuel d'installation", "Version lisible par un humain. Les agents IA doivent utiliser le AI_INSTALL.md anglais à la racine du dépôt.", "Guide technique et projet", "Toutes les autres informations sur le projet, en français."),
    "de": ("Installationshandbuch", "Die lesbare Fassung der Installationsanleitung. KI-Agenten nutzen bitte die englische AI_INSTALL.md im Repo-Stammverzeichnis.", "Technik- & Projekthandbuch", "Alle weiteren Informationen zum Projekt, auf Deutsch."),
    "es": ("Manual de instalación", "Versión legible para personas. Los agentes de IA deben usar el AI_INSTALL.md en inglés de la raíz del repo.", "Guía técnica y del proyecto", "El resto de la información del proyecto, en español."),
    "it": ("Manuale di installazione", "Versione leggibile per le persone. Gli agenti IA devono usare l'AI_INSTALL.md in inglese nella radice del repo.", "Guida tecnica e al progetto", "Tutte le altre informazioni sul progetto, in italiano."),
    "ru": ("Руководство по установке", "Версия для чтения человеком. ИИ-агенты должны использовать английский AI_INSTALL.md в корне репозитория.", "Техническое описание и проект", "Вся остальная информация о проекте на русском языке."),
}


def expand(text, lang):
    for key, value in PLACEHOLDERS.items():
        text = text.replace(key, value)
    return text.replace("{{REPLY}}", T[lang]["reply"])


def local_prompt_from_readme(lang):
    """Keep the human-language prompt as the optional second block.

    The prompts are frozen in tools/i18n_local_prompts.json: the README prompt
    blocks are English on purpose, so re-reading them would silently replace
    the localized alternative prompts with English on a later regeneration.
    """
    frozen = Path(__file__).parent / "i18n_local_prompts.json"
    if frozen.exists():
        return json.loads(frozen.read_text(encoding="utf-8"))[lang].strip()
    t = (ROOT / README_FILE[lang]).read_text(encoding="utf-8")
    m = re.search(r"```text\s*\n(.*?)\n```", t, re.S)
    if not m:
        raise RuntimeError(f"no prompt block in {README_FILE[lang]}")
    return m.group(1).strip()


def english_prompt(lang):
    return EN_PROMPT.format(repo=REPO, site=SITE, reply=T[lang]["reply"])


def sections_block(sections, lang):
    parts = []
    for heading, body in sections:
        parts.append(f"## {heading}\n\n{expand(body, lang)}")
    return "\n\n".join(parts)


def nav(lang):
    return (f"- [{README_FILE[lang]}](../../{README_FILE[lang]})\n"
            f"- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)\n"
            f"- [AI_INSTALL.md](AI_INSTALL.md)\n"
            f"- [GUIDE.md](GUIDE.md)")


def render_prompt(lang, d):
    p = d["p"]
    out = [f"# {p['title']}", "", p["intro"], "",
           "> [!TIP]", f"> {d['prompt_note']}", "",
           f"## ① {p['common']}", "", "```text", english_prompt(lang), "```", "",
           p["common_hint"]]
    if lang != "en":
        out += ["", f"## ② {p['alt']}", "", "```text",
                local_prompt_from_readme(lang), "```", "", p["alt_hint"]]
    three = "\n".join(x for x in INSTALL.splitlines() if "--dry-run" not in x)
    out += ["", f"## {'③' if lang != 'en' else '②'} {p['manual']}", "",
            "```bash", three, "```", "", p["manual_tip"], "",
            "---", "", f"## {p['nav']}", "", nav(lang), ""]
    return "\n".join(out)


def render_manual(lang, d):
    title, lead, _, _ = EXTRA[lang]
    return "\n".join([
        f"# Dòng — {title}", "", f"> {lead}", "",
        sections_block(d["m_sections"], lang), "", "---", "",
        f"## {d['p']['nav']}", "", nav(lang), "",
    ])


def render_guide(lang, d):
    _, _, title, lead = EXTRA[lang]
    return "\n".join([
        f"# Dòng — {title}", "", f"> {lead}", "",
        sections_block(d["g_sections"], lang), "", "---", "",
        f"## {d['p']['nav']}", "", nav(lang), "",
    ])


def main():
    for lang in LANGS:
        d = T[lang]
        dest = OUT / lang
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "AI_INSTALL_PROMPT.md").write_text(render_prompt(lang, d), encoding="utf-8")
        (dest / "AI_INSTALL.md").write_text(render_manual(lang, d), encoding="utf-8")
        (dest / "GUIDE.md").write_text(render_guide(lang, d), encoding="utf-8")
        print(f"{lang:3} → i18n/{lang}/ (prompt, manual, guide)")


if __name__ == "__main__":
    main()
