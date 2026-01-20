# 食事管理アプリ オフラインセットアップガイド

## 📋 概要

このガイドでは、インターネット接続が制限された環境で食事管理アプリをセットアップする方法を説明します。

**アプリの機能:**
- 食事の記録（朝食・昼食・夕食・間食）
- カロリー計算と統計
- グラフによる可視化
- ユーザー認証（ローカル）

**技術スタック:**
- Next.js 16
- PostgreSQL (ローカル)
- Prisma (ORM)
- Zustand (状態管理)
- Recharts (グラフ)
- Tailwind CSS
- bcryptjs (認証)

---

## 🏠 ステップ1: 自宅での準備作業

### 1.1 Next.jsプロジェクトの作成

```bash
# Next.jsプロジェクトを作成
npx create-next-app@latest meal-tracker
# TypeScript: Yes
# ESLint: Yes
# Tailwind CSS: Yes
# src/ directory: Yes
# App Router: Yes
# import alias: No (デフォルト)

cd meal-tracker
```

### 1.2 必要なパッケージをインストール

```bash
# 追加パッケージをインストール
npm install prisma @prisma/client zustand recharts bcryptjs
npm install -D @types/bcryptjs
```

### 1.3 package-urls.txt の作成

次のファイルを統合します：
1. **基本のNext.jsパッケージ** (添付の package-urls.txt)
2. **追加パッケージ** (meal-tracker-additional-packages.txt)

```bash
# 2つのファイルを統合
cat package-urls.txt meal-tracker-additional-packages.txt > meal-tracker-all-packages.txt
```

または、手動で以下のファイルを作成：

**meal-tracker-all-packages.txt** に以下を含める：
- 基本のNext.jsパッケージ（420個）
- Prisma関連（4個）
- Zustand関連（2個）
- Recharts関連（15個）
- bcryptjs関連（2個）

**合計: 約443個のパッケージ**

### 1.4 パッケージのダウンロード

```powershell
# PowerShellで実行（Windowsの場合）
powershell -ExecutionPolicy Bypass -File download-packages.ps1 -urlsFile "meal-tracker-all-packages.txt"

# または、オリジナルのスクリプトを修正して使用
```

**実行内容:**
- すべてのパッケージを `npm-packages/` フォルダにダウンロード
- 約300-400MBのファイルサイズ

### 1.5 プロジェクトファイルの準備

以下のファイルを職場に持っていく準備をします：

```
📁 meal-tracker/
├── 📁 npm-packages/           # ダウンロードした .tgz ファイル（443個）
├── 📁 src/                    # ソースコード
├── 📁 prisma/                 # Prismaスキーマ
├── 📁 public/                 # 静的ファイル
├── 📄 package.json
├── 📄 package-lock.json
├── 📄 install-offline.ps1
├── 📄 next.config.ts
├── 📄 tailwind.config.ts
├── 📄 tsconfig.json
├── 📄 .env.example            # 環境変数テンプレート
└── 📄 README-OFFLINE.md
```

---

## 🏢 ステップ2: 職場でのセットアップ

### 2.1 前提条件の確認

**必須:**
- Node.js 18.17以上がインストールされていること
- PostgreSQL 12以上がインストールされていること

**確認コマンド:**
```powershell
node --version    # v18.17以上
npm --version     # 9.0以上
psql --version    # 12以上
```

### 2.2 PostgreSQLデータベースの準備

```sql
-- PostgreSQLに接続
psql -U postgres

-- データベースを作成
CREATE DATABASE meal_tracker;

-- ユーザーを作成（オプション）
CREATE USER meal_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE meal_tracker TO meal_user;

-- 終了
\q
```

### 2.3 環境変数の設定

`.env` ファイルを作成：

```env
# Database
DATABASE_URL="postgresql://postgres:password@localhost:5432/meal_tracker?schema=public"

# または、専用ユーザーを使用する場合
# DATABASE_URL="postgresql://meal_user:your_password@localhost:5432/meal_tracker?schema=public"
```

### 2.4 オフラインインストールの実行

```powershell
# PowerShellで実行
powershell -ExecutionPolicy Bypass -File install-offline.ps1
```

**実行内容:**
- npmキャッシュの準備
- 全パッケージのインストール
- node_modulesフォルダの作成

### 2.5 Prismaのセットアップ

```powershell
# Prismaクライアントを生成
npx prisma generate

# データベースマイグレーション
npx prisma migrate dev --name init
```

### 2.6 開発サーバーの起動

```powershell
npm run dev
```

ブラウザで http://localhost:3000 を開く

---

## 📝 プロジェクト構造の詳細

### ディレクトリ構成

```
meal-tracker/
├── src/
│   ├── app/                    # Next.js App Router
│   │   ├── api/               # API Routes
│   │   │   ├── auth/         # 認証API
│   │   │   │   ├── login/
│   │   │   │   ├── register/
│   │   │   │   └── logout/
│   │   │   ├── meals/        # 食事API
│   │   │   │   ├── route.ts  # GET, POST
│   │   │   │   └── [id]/
│   │   │   └── stats/        # 統計API
│   │   ├── login/            # ログインページ
│   │   ├── register/         # 登録ページ
│   │   ├── dashboard/        # メインダッシュボード
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── components/            # Reactコンポーネント
│   │   ├── MealForm.tsx      # 食事入力フォーム
│   │   ├── MealList.tsx      # 食事一覧
│   │   ├── CalorieChart.tsx  # カロリーグラフ
│   │   └── StatsCard.tsx     # 統計カード
│   ├── lib/                   # ユーティリティ
│   │   ├── prisma.ts         # Prismaクライアント
│   │   └── auth.ts           # 認証ヘルパー
│   └── store/                 # Zustand store
│       └── mealStore.ts      # 食事データストア
├── prisma/
│   ├── schema.prisma         # データベーススキーマ
│   └── migrations/           # マイグレーションファイル
└── public/                    # 静的ファイル
```

### Prismaスキーマ (prisma/schema.prisma)

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(uuid())
  username  String   @unique
  password  String   // bcryptでハッシュ化
  createdAt DateTime @default(now())
  meals     Meal[]
}

model Meal {
  id          String   @id @default(uuid())
  userId      String
  user        User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  name        String
  calories    Int
  mealType    String   // breakfast, lunch, dinner, snack
  date        DateTime @default(now())
  createdAt   DateTime @default(now())
  
  @@index([userId, date])
}
```

---

## 🔧 トラブルシューティング

### 問題1: パッケージのインストールエラー

**症状:**
```
npm ERR! code ENOTFOUND
```

**解決方法:**
```powershell
# 1. node_modulesを削除
Remove-Item -Path node_modules -Recurse -Force

# 2. npmキャッシュをクリア
npm cache clean --force

# 3. 再インストール
powershell -ExecutionPolicy Bypass -File install-offline.ps1
```

### 問題2: Prismaのセットアップエラー

**症状:**
```
Environment variable not found: DATABASE_URL
```

**解決方法:**
```powershell
# .envファイルが存在するか確認
Get-Content .env

# 存在しない場合は作成
@"
DATABASE_URL="postgresql://postgres:password@localhost:5432/meal_tracker?schema=public"
"@ | Out-File -FilePath .env -Encoding utf8
```

### 問題3: PostgreSQL接続エラー

**症状:**
```
Can't reach database server
```

**解決方法:**
```powershell
# PostgreSQLサービスを確認
Get-Service -Name postgresql*

# サービスを起動
Start-Service -Name "postgresql-x64-14"  # バージョンに応じて変更

# 接続テスト
psql -U postgres -d meal_tracker
```

### 問題4: ポート3000が使用中

**症状:**
```
Port 3000 is already in use
```

**解決方法:**
```powershell
# 別のポートで起動
npm run dev -- -p 3001

# または、使用中のプロセスを終了
Get-Process -Id (Get-NetTCPConnection -LocalPort 3000).OwningProcess | Stop-Process
```

---

## 💡 開発のヒント

### 1. データベースの確認

Prisma Studioを使用してデータを視覚的に確認：

```powershell
npx prisma studio
```

ブラウザで http://localhost:5555 が開きます

### 2. データベースのリセット

```powershell
# データベースをリセット（開発時のみ）
npx prisma migrate reset

# 確認メッセージで 'y' を入力
```

### 3. 本番ビルド

```powershell
# 本番用ビルド
npm run build

# 本番サーバーを起動
npm start
```

### 4. 型チェック

```powershell
# TypeScriptの型チェック
npm run type-check

# または
npx tsc --noEmit
```

---

## 📊 ファイルサイズ目安

- `npm-packages/` フォルダ: 約350-450MB
- インストール後の `node_modules/`: 約600-800MB
- Prismaクライアント生成後: 追加50-100MB

---

## 🎯 次のステップ

インストール完了後、以下の順序で開発を進めます：

1. **認証機能の実装**
   - ユーザー登録
   - ログイン
   - セッション管理

2. **食事記録機能**
   - 食事入力フォーム
   - 一覧表示
   - 編集・削除

3. **統計とグラフ**
   - 日別カロリー集計
   - グラフ表示（Recharts使用）
   - 期間別統計

4. **UI/UXの改善**
   - レスポンシブデザイン
   - ローディング状態
   - エラーハンドリング

---

## ❓ よくある質問

**Q: パッケージを追加したい場合は？**
A: 自宅で新しいパッケージをインストール→URLを抽出→ダウンロード→職場に持っていく

**Q: データベースのバックアップは？**
A: `pg_dump`を使用：
```powershell
pg_dump -U postgres meal_tracker > backup.sql
```

**Q: 環境変数を変更したら？**
A: `.env`ファイルを編集後、開発サーバーを再起動

**Q: Prismaスキーマを変更したら？**
A: マイグレーションを作成：
```powershell
npx prisma migrate dev --name your_migration_name
```

---

## 📞 チェックリスト

セットアップ完了の確認：

- [ ] Node.jsがインストールされている
- [ ] PostgreSQLがインストールされている
- [ ] データベースが作成されている
- [ ] .envファイルが設定されている
- [ ] npm installが成功している
- [ ] Prismaクライアントが生成されている
- [ ] マイグレーションが完了している
- [ ] 開発サーバーが起動する
- [ ] http://localhost:3000 にアクセスできる

---

作成日: 2026年1月20日
アプリバージョン: 1.0.0
パッケージ数: 443個
