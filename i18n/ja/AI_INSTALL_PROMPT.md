# AI に Dòng をインストールしてもらう

ブロックを丸ごとコピーし、Mac でコマンドを実行できる AI アシスタントに貼り付けるだけです。

> [!TIP]
> 下のプロンプトは、どの AI ツールでも読めるよう意図的に英語で書いてあります。最後の一行で日本語での返答を指定しているので、あなたが読む文章は日本語のままです。

## ① 推奨：共通プロンプト（すべての AI ツールが理解できます）

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Japanese.
```

ブロック全体をコピーして貼り付けてください。AI が公式 DMG のダウンロード、SHA256 の検証、インストール、macOS 初回起動時の確認まで行います。アプリ側の初回設定は自分で選んでください。

## ② 別案：日本語のプロンプト

```text
この Mac に macOS 用ライブ壁紙アプリ Dòng をインストールしてください。

公式リポジトリ: https://github.com/zhang-1-kael/dong
公式サイト: https://dongisgood.coze.site/en
AI 向け手順書: リポジトリ内の AI_INSTALL.md／ワンコマンド版: install.sh

まず手順書とスクリプトを読み、その指示に従ってください。公式の安定エンドポイントからダウンロードし、公式 API の SHA256 で検証し、「アプリケーション」に導入し、macOS の初回起動確認を済ませて起動、結果と使い方を報告してください。
上記の公式ドメインのみを使い、sudo は使わず、ファイルの削除・上書きやシステム全体のセキュリティ設定変更はしないでください。ターミナル権限がない場合は最短のコマンドだけを提示し、インストールしたと見せかけないでください。
```

日本語の指示のほうが通る AI ツールなら、こちらを使っても構いません。

## ③ 自分で 3 行だけ実行したい場合

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

--dry-run を付けると、ダウンロードや変更をせずに予定だけを表示します。

---

## 日本語のドキュメント一覧

- [README.ja.md](../../README.ja.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
