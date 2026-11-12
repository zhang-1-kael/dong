# Dòng — インストール手順書

> 人間が読むための手順書です。AI エージェントはリポジトリ直下の英語版 AI_INSTALL.md を参照してください。

## 公式のアドレス

| 項目 | アドレス |
|---|---|
| 公式リポジトリ | `https://github.com/zhang-1-kael/dong` |
| 公式サイト | `https://dongisgood.coze.site/en` |
| 安定版 DMG | `https://dongisgood.coze.site/api/download?channel=stable` |
| バージョンと SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| ワンコマンド導入スクリプト | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## 守るべきルール

- **GitHub Releases に v3.31 が公開されています**（`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`）：`Dong-3.31.dmg` と完全なリリースバンドル。公式サイトが使えない時の予備として使い、SHA256 は必ず検証してください。他のバージョンのアセット URL を作らないでください。
- **オブジェクトストレージの直リンクを固定しないでください。** `/api/download` は期限付き署名 URL へリダイレクトします。
- **DMG は ad-hoc 署名で公証されていません。** `com.apple.quarantine` の解除は想定内です。Gatekeeper をシステム全体で無効化してはいけません。
- **`sudo`、ユーザーファイルの削除・上書き、`curl | bash` は禁止。** まずスクリプトを読んでください。
- Apple Silicon と macOS 13 以降のみ。Intel Mac はソースからビルドが必要です。

## 方法 A：ターミナルがある場合

スクリプトを読んでから予行演習し、その後実行します。各手順の前に何をするか説明してください。

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## 方法 B：ターミナルがない / 手動で入れる場合

安定版エンドポイントからダウンロードし、メタデータの SHA256 と照合してから DMG を開きます。

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## インストール後

メニューバーにゼリーのアイコンが出ます。クリックしてパネルを開き、Bilibili / YouTube のリンクを貼るか、ローカル動画をドラッグしてください。

## うまくいかないとき

チェックサムが一致しない場合は即座に中止してください。「壊れている」と表示されたら `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` を一度実行して開き直します。システム全体のセキュリティ設定は変更しないでください。

---

## 日本語のドキュメント一覧

- [README.ja.md](../../README.ja.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
