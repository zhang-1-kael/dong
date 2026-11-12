# Dòng — 技術・プロジェクト文書

> プロジェクトに関するその他の説明を、すべて日本語でまとめています。

## 構成

4 本の独立したパイプライン：デスクトップ層のウィンドウと `AVPlayerLayer`、yt-dlp + ffmpeg の変換、AppKit で手描きしたメニューバーパネルとライブラリ、LaunchAgent による自動起動・フォルダ監視・匿名統計です。

## 実装の要点

- ウィンドウは画面より 24 pt 大きくし、角の丸みとデスクトップ切替時の縁を隠します。
- `--deep` 署名は入れ子のリソース署名を壊すため使いません。
- ループ音声は 3 回の seek で混合します。1 回だけだとノイズが残ります。
- メニューバーパネルはシステムのすりガラスを覆うため、すべて手描きです。

## コマンドラインでのデバッグ

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

環境変数（`VW_PANEL_SHOT`、`VW_GEOM`、`VW_DUMP_MENU` など）は中国語の原文書 9 章にあります。

## ライセンスと商用利用

コードと文書は **GPL-3.0** です。法的に有効な全文は英語の [LICENSE](../../LICENSE) です。クローズドソースの商用利用には別途ライセンスが必要です：[COMMERCIAL.md](../../COMMERCIAL.md)。

## ブランドと素材

名称「Dòng」、`AppIcon.icns`、`BrandMark*.png` はブランド標識です。`presets/` と `bili/` の壁紙動画、ffmpeg / yt-dlp のバイナリはリポジトリに含まれません。

## コントリビューションと AI 方針

issue と PR を歓迎します。テンプレートは `.github/`、CI でビルドされます。AI を使った貢献は開示し、行単位でレビューしてください：[AI_POLICY.md](../../AI_POLICY.md)。

## プライバシー

匿名の利用統計は既定で有効ですが、設定から無効化できます。fork する場合は `Analytics.swift` の `isEnabled` 初期値を `false` に変更してください。

中国語の完全な技術解説：[技术原理.md](../../技术原理.md)。

---

## 日本語のドキュメント一覧

- [README.ja.md](../../README.ja.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
