#!/usr/bin/env python3
"""Regenerate the localized UI screenshots used by the per-language READMEs.

Usage (Pillow required):
    uv run --with pillow python tools/gen_i18n_images.py

The two source screenshots show a Chinese UI. This script erases the Chinese
UI strings with a gradient-preserving fill and draws the same strings in each
of the nine supported languages, so a reader who picks a language never sees
text in a different one.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "i18n"

# language code -> strings drawn into the screenshots
IMG = {
    "en": {
        "stats": "26 wallpapers · 1.1 GB on disk · online 4h 41m",
        "placeholder": "Paste a video link to make it your wallpaper",
        "wtitle": "04-Asuka-Manga Collage",
        "liblabel": "Library",
        "toast": "Paste a link, press Enter to download",
    },
    "zh": {
        "stats": "壁纸 26 张 · 磁盘 1.1 GB · 在线 4 小时 41 分",
        "placeholder": "粘贴视频链接，转成动态壁纸",
        "wtitle": "04-明日香-漫画拼贴",
        "liblabel": "壁纸库",
        "toast": "粘贴视频链接，回车开始下载",
    },
    "ja": {
        "stats": "壁紙 26 枚 · ディスク 1.1 GB · オンライン 4 時間 41 分",
        "placeholder": "動画リンクを貼り付けて壁紙にする",
        "wtitle": "04-アスカ-漫画コラージュ",
        "liblabel": "ライブラリ",
        "toast": "リンクを貼って Enter でダウンロード",
    },
    "ko": {
        "stats": "배경화면 26개 · 디스크 1.1 GB · 온라인 4시간 41분",
        "placeholder": "동영상 링크를 붙여넣어 배경화면으로",
        "wtitle": "04-아스카-만화 콜라주",
        "liblabel": "보관함",
        "toast": "링크 붙여넣고 Enter 로 다운로드",
    },
    "fr": {
        "stats": "26 fonds d'écran · 1,1 Go sur le disque · en ligne 4 h 41",
        "placeholder": "Collez un lien vidéo pour en faire un fond d'écran",
        "wtitle": "04-Asuka-Collage manga",
        "liblabel": "Bibliothèque",
        "toast": "Collez un lien, Entrée pour télécharger",
    },
    "de": {
        "stats": "26 Hintergründe · 1,1 GB auf der Platte · online 4 Std. 41 Min.",
        "placeholder": "Videolink einfügen und zum Hintergrund machen",
        "wtitle": "04-Asuka-Manga-Collage",
        "liblabel": "Bibliothek",
        "toast": "Link einfügen, Enter zum Laden",
    },
    "es": {
        "stats": "26 fondos · 1,1 GB en disco · en línea 4 h 41 min",
        "placeholder": "Pega un enlace de vídeo para crear un fondo",
        "wtitle": "04-Asuka-Collage manga",
        "liblabel": "Biblioteca",
        "toast": "Pega un enlace, Enter para descargar",
    },
    "it": {
        "stats": "26 sfondi · 1,1 GB su disco · online 4 h 41 min",
        "placeholder": "Incolla un link video per creare uno sfondo",
        "wtitle": "04-Asuka-Collage manga",
        "liblabel": "Libreria",
        "toast": "Incolla un link, Invio per scaricare",
    },
    "ru": {
        "stats": "26 обоев · 1,1 ГБ на диске · онлайн 4 ч 41 мин",
        "placeholder": "Вставьте ссылку на видео, чтобы сделать обои",
        "wtitle": "04-Аска-Манга-коллаж",
        "liblabel": "Библиотека",
        "toast": "Вставьте ссылку, Enter для загрузки",
    },
}

FONT_BY_LANG = {
    "zh": "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "ja": "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "ko": "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "en": "/System/Library/Fonts/Helvetica.ttc",
    "fr": "/System/Library/Fonts/Helvetica.ttc",
    "de": "/System/Library/Fonts/Helvetica.ttc",
    "es": "/System/Library/Fonts/Helvetica.ttc",
    "it": "/System/Library/Fonts/Helvetica.ttc",
    "ru": "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
}

# (left, top, right, bottom), base font size, text colour, optional bold stroke
PANEL_FIELDS = [
    ("stats",       (205, 152, 945, 208), 31, (105, 110, 118), 0),
    ("placeholder", (150, 270, 950, 330), 32, (138, 144, 153), 0),
    ("wtitle",      (395, 482, 860, 548), 40, (28, 28, 30), 1),
    ("liblabel",    (898, 630, 1032, 682), 29, (138, 144, 153), 0),
]
LIBRARY_FIELDS = [
    ("toast",       (98, 1004, 405, 1044), 17, (216, 216, 216), 0),
]


def erase_gradient(im, box):
    """Fill a box by interpolating between the pixel rows just above/below it.

    The panel has a subtle vertical gradient; a flat rectangle would leave a
    visible patch. Interpolating column by column keeps the original shading.
    """
    x0, y0, x1, y1 = box
    px = im.load()
    top = [px[x, max(0, y0 - 3)] for x in range(x0, x1)]
    bot = [px[x, min(im.height - 1, y1 + 3)] for x in range(x0, x1)]
    for y in range(y0, y1):
        t = (y - y0 + 1) / (y1 - y0 + 1)
        for i, x in enumerate(range(x0, x1)):
            a, b = top[i], bot[i]
            px[x, y] = tuple(int(a[c] * (1 - t) + b[c] * t) for c in range(3))


def erase_flat(im, box, sample_box):
    """Fill a box with the average colour of a nearby clean area."""
    sample = im.crop(sample_box)
    px = list(sample.getdata())
    avg = tuple(sum(p[c] for p in px) // len(px) for c in range(3))
    ImageDraw.Draw(im).rectangle(box, fill=avg)


def fitted_font(lang, text, box, size, max_width):
    path = FONT_BY_LANG[lang]
    while size > 9:
        f = ImageFont.truetype(path, size)
        if f.getbbox(text)[2] - f.getbbox(text)[0] <= max_width:
            return f
        size -= 1
    return ImageFont.truetype(path, 9)


def draw_field(im, lang, text, box, size, colour, stroke):
    x0, y0, x1, y1 = box
    f = fitted_font(lang, text, box, size, x1 - x0 - 6)
    d = ImageDraw.Draw(im)
    bbox = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    # centre vertically in the box, left aligned with a little padding
    x = x0 + 3
    y = y0 + (y1 - y0 - th) / 2 - bbox[1]
    d.text((x, y), text, font=f, fill=colour, stroke_width=stroke,
           stroke_fill=colour if stroke else None)


def build():
    panel_src = Image.open(ROOT / "assets" / "panel.jpg").convert("RGB")
    library_src = Image.open(ROOT / "assets" / "library-wide.jpg").convert("RGB")

    for lang, strings in IMG.items():
        dest = OUT / lang
        dest.mkdir(parents=True, exist_ok=True)

        panel = panel_src.copy()
        for key, box, size, colour, stroke in PANEL_FIELDS:
            erase_gradient(panel, box)
            draw_field(panel, lang, strings[key], box, size, colour, stroke)
        panel.save(dest / "panel.jpg", quality=92, subsampling=0)

        library = library_src.copy()
        for key, box, size, colour, stroke in LIBRARY_FIELDS:
            # the toast sits over a photo; interpolating the neighbouring rows
            # keeps that photo's shading instead of stamping a flat patch
            erase_gradient(library, box)
            draw_field(library, lang, strings[key], box, size, colour, stroke)
        library.save(dest / "library.jpg", quality=92, subsampling=0)

        print(f"{lang:3} → {dest.relative_to(ROOT)}/panel.jpg, library.jpg")


if __name__ == "__main__":
    build()
