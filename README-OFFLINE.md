# Next.js オフラインインストールガイド

このガイドでは、インターネット接続が制限された環境（職場など）でNext.jsプロジェクトをセットアップする方法を説明します。

## 📋 概要

- **抽出されたパッケージ数**: 420個
- **Next.jsバージョン**: 最新版（create-next-app使用）
- **含まれる依存関係**: すべての依存関係とdev依存関係

## 🏠 自宅での準備作業

### ステップ1: URLリストの確認

`package-urls.txt` には420個のnpmパッケージのURLが含まれています。

```
例:
https://registry.npmjs.org/next/-/next-15.1.6.tgz
https://registry.npmjs.org/react/-/react-19.0.0.tgz
https://registry.npmjs.org/react-dom/-/react-dom-19.0.0.tgz
...
```

### ステップ2: パッケージのダウンロード

PowerShellで以下を実行：

```powershell
powershell -ExecutionPolicy Bypass -File download-packages.ps1
```

**実行内容:**
- `package-urls.txt` から全URLを読み込み
- 各パッケージを `npm-packages/` フォルダにダウンロード
- 既存のファイルはスキップ（再実行可能）
- 失敗したダウンロードは `failed-downloads.log` に記録

**オプション:**
```powershell
# カスタムディレクトリに保存
powershell -ExecutionPolicy Bypass -File download-packages.ps1 -downloadDir "my-packages"
```

### ステップ3: ファイルの準備

以下のファイル/フォルダを職場に持っていきます：

```
📁 持っていくもの
├── 📁 npm-packages/          # ダウンロードした420個の .tgz ファイル
├── 📄 package.json           # プロジェクト設定
├── 📄 package-lock.json      # 依存関係の完全なリスト
├── 📄 install-offline.ps1    # オフラインインストールスクリプト
└── 📄 README-OFFLINE.md      # このファイル（オプション）
```

**推奨方法:**
- USBメモリ
- 社内ファイル共有
- メール添付（zipファイルに圧縮）

## 🏢 職場での作業

### 前提条件

Node.jsがインストールされていることを確認：

```powershell
node --version
npm --version
```

インストールされていない場合は、Node.jsをインストールしてください：
https://nodejs.org/

### インストール手順

1. **ファイルの配置**

持ってきたファイルをプロジェクトフォルダに配置：

```
📁 my-nextjs-project/
├── 📁 npm-packages/
├── 📄 package.json
├── 📄 package-lock.json
└── 📄 install-offline.ps1
```

2. **オフラインインストールの実行**

PowerShellで実行：

```powershell
powershell -ExecutionPolicy Bypass -File install-offline.ps1
```

**実行内容:**
- npmキャッシュを準備
- `npm-packages/` 内の全.tgzファイルをキャッシュに追加
- オフラインモードで `npm install` を実行
- `node_modules/` フォルダを作成

3. **開発サーバーの起動**

インストール完了後：

```powershell
npm run dev
```

ブラウザで http://localhost:3000 を開く

## 📝 スクリプトの詳細

### download-packages.ps1

**機能:**
- URLリストから全パッケージをダウンロード
- プログレスバー表示
- 既存ファイルのスキップ
- エラーログの記録

**パラメータ:**
- `-urlsFile`: URLリストファイル（デフォルト: package-urls.txt）
- `-downloadDir`: 保存先ディレクトリ（デフォルト: npm-packages）

### install-offline.ps1

**機能:**
- 必要ファイルの確認
- npmキャッシュの準備
- オフラインインストールの実行
- エラーハンドリング

**パラメータ:**
- `-packagesDir`: パッケージディレクトリ（デフォルト: npm-packages）

## 🔧 トラブルシューティング

### ダウンロード失敗時

```powershell
# ログを確認
Get-Content failed-downloads.log

# スクリプトを再実行（失敗したものだけ再ダウンロード）
powershell -ExecutionPolicy Bypass -File download-packages.ps1
```

### インストール失敗時

**考えられる原因:**

1. **Node.jsがインストールされていない**
   - Node.jsをインストール: https://nodejs.org/

2. **パッケージファイルが不足**
   - `npm-packages/` フォルダ内の.tgzファイル数を確認
   - 420個すべて揃っているか確認

3. **package-lock.jsonが古い**
   - 自宅と職場で同じファイルを使用しているか確認

**解決方法:**

```powershell
# node_modulesを削除して再試行
Remove-Item -Path node_modules -Recurse -Force
powershell -ExecutionPolicy Bypass -File install-offline.ps1
```

### 権限エラー

```powershell
# 管理者権限でPowerShellを起動
# または
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

## 📊 ファイルサイズ目安

- `npm-packages/` フォルダ: 約250-350MB
- インストール後の `node_modules/`: 約400-600MB

## 🎯 含まれる主要パッケージ

- **next**: Next.jsフレームワーク
- **react**: Reactライブラリ
- **react-dom**: React DOM
- **typescript**: TypeScript
- **tailwindcss**: TailwindCSS
- **eslint**: ESLint
- その他414個の依存パッケージ

## 💡 ヒント

1. **初回セットアップ時**
   - すべてのファイルが揃っているか確認
   - インターネット接続なしでも動作します

2. **パッケージの更新**
   - 新しいパッケージを追加したい場合は、自宅で同様の手順を繰り返す

3. **複数プロジェクト**
   - 同じ`npm-packages/`フォルダを使い回せます
   - `package-lock.json`が同じなら再利用可能

## ❓ よくある質問

**Q: インターネット接続は必要ですか？**
A: いいえ、すべてのファイルがローカルにあればインストール可能です。

**Q: パッケージを追加したい場合は？**
A: 自宅で新しいパッケージをインストール→URLを抽出→ダウンロード→職場に持っていく

**Q: 他のプロジェクトにも使えますか？**
A: `package-lock.json`が同じなら使えます。異なる場合は新しくダウンロードが必要です。

## 📞 サポート

問題が発生した場合：
1. エラーメッセージをコピー
2. `failed-downloads.log`を確認
3. ファイルの整合性を確認

---

作成日: 2026年1月19日
Next.jsバージョン: 15.x
パッケージ数: 420
