# React / Next.js / TypeScript / Tailwind CSS 学習計画（拡張版）

> **期間**: 2026/2/16（月）〜 2026/4/12（日）（8週間）  
> **対象者**: .NET Framework 4.8 / WinForms / VB.NET 経験者  
> **学習時間**:  
> 　業務時間 … 平日 2〜3h（約100〜120h）  
> 　自習時間 … 平日夜 1h ＋ 土日 各3h（約88h）  
> 　**合計 約200h**  
> **目標**: 2ヶ月後の業務で自走できるレベル。状態管理ライブラリ・フォームライブラリ・テスト・デプロイまで経験済みの状態

---

## 理解度チェックシート

各項目を **Lv1〜5** で週次に自己評価し、推移を記録する。

| Lv | 定義 |
|----|------|
| 1 | ドキュメントを読み始めた段階。用語がわかる |
| 2 | チュートリアルを写経で完走できる |
| 3 | 小さな機能を自力で実装できる |
| 4 | エラーを自力で解決しつつアプリを作れる |
| 5 | 設計判断ができ、他人に説明できる |

### 評価項目一覧

| カテゴリ | 評価項目 | W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 |
|---------|---------|----|----|----|----|----|----|----|----|
| **TypeScript** | 基本型（string, number, boolean, array） | | | | | | | | |
| | interface と type の違いと使い分け | | | | | | | | |
| | ユニオン型・リテラル型 | | | | | | | | |
| | ジェネリクス | | | | | | | | |
| | 型ガード・型の絞り込み | | | | | | | | |
| | モジュールとimport/export | | | | | | | | |
| **React** | JSXの理解 | | | | | | | | |
| | コンポーネントとProps | | | | | | | | |
| | useState | | | | | | | | |
| | useEffect | | | | | | | | |
| | イベントハンドリング | | | | | | | | |
| | 条件付きレンダリング・リスト表示 | | | | | | | | |
| | カスタムフック | | | | | | | | |
| | useContext | | | | | | | | |
| **React応用** | React Hook Form + zod | | | | | | | | |
| | TanStack Query | | | | | | | | |
| | Zustand（状態管理） | | | | | | | | |
| | テスト（Jest + RTL） | | | | | | | | |
| **Tailwind CSS** | ユーティリティクラスの基本 | | | | | | | | |
| | Flexbox / Grid レイアウト | | | | | | | | |
| | レスポンシブデザイン | | | | | | | | |
| | ダークモード・テーマ設定 | | | | | | | | |
| **Next.js** | App Routerの仕組み | | | | | | | | |
| | ページ遷移・動的ルーティング | | | | | | | | |
| | Server Components vs Client Components | | | | | | | | |
| | データ取得（fetch / Server Actions） | | | | | | | | |
| | レイアウトとテンプレート | | | | | | | | |
| | API Routes / Route Handlers | | | | | | | | |
| | ミドルウェア・認証 | | | | | | | | |
| **実務スキル** | Git ブランチ運用 | | | | | | | | |
| | デプロイ（Vercel） | | | | | | | | |
| | DB連携（Prisma / Supabase） | | | | | | | | |

---

## 時間の使い分け方針

| 時間帯 | 性質 | 主な用途 |
|--------|------|---------|
| **平日 業務時間**（2〜3h） | コアタイム | メインカリキュラムの消化（インプット＋コーディング） |
| **平日 夜**（1h） | インプット | 動画教材、技術記事、コードリーディング、当日の振り返り |
| **土日**（各3h） | アウトプット | ミニアプリ構築、ライブラリの深掘り、ポートフォリオ開発 |

---

## 教材リスト

| # | 教材名 | 種類 | URL | 使用週 |
|---|--------|------|-----|--------|
| 1 | サバイバルTypeScript | Web（日本語・無料） | https://typescriptbook.jp/ | W1-W2 |
| 2 | TypeScript公式ハンドブック | Web（英語） | https://www.typescriptlang.org/docs/handbook/ | W1-W2 |
| 3 | React公式ドキュメント | Web（日本語あり） | https://ja.react.dev/ | W3-W4 |
| 4 | React公式チュートリアル（三目並べ） | Web | https://ja.react.dev/learn/tutorial-tic-tac-toe | W3 |
| 5 | Tailwind CSS公式ドキュメント | Web | https://tailwindcss.com/docs | W5 |
| 6 | Tailwind Play（ブラウザで試す） | ツール | https://play.tailwindcss.com/ | W5 |
| 7 | Flexbox Froggy（CSS Flexbox学習） | ゲーム | https://flexboxfroggy.com/ | W5 |
| 8 | Next.js公式 Learn コース | Web | https://nextjs.org/learn | W6-W7 |
| 9 | Next.js公式ドキュメント | Web | https://nextjs.org/docs | W6-W7 |
| 10 | Zenn / Qiita の良記事 | Web（日本語） | 各サイト内で技術名で検索 | 全週（平日夜） |
| 11 | React Hook Form 公式 | Web | https://react-hook-form.com/ | W4 土日 |
| 12 | TanStack Query 公式 | Web | https://tanstack.com/query/latest | W4 土日 |
| 13 | Zustand 公式 | Web | https://zustand-demo.pmnd.rs/ | W4 土日 |
| 14 | Jest + React Testing Library | Web | https://testing-library.com/docs/react-testing-library/intro/ | W5 土日 |

---

## 日付別スケジュール

凡例:  
🏢 = 業務時間（平日 2〜3h）  
🌙 = 平日夜の自習（1h）  
🏠 = 土日の自習（各3h）

---

### Week 1（2/16〜2/22）：TypeScript 基礎 - 型システムの理解

VB.NETの型の経験を活かしつつ、TypeScriptの型システムに慣れる週。

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 2/16 | 月 | 🏢 | 環境構築 + TS入門 | Node.js / npm / VS Code セットアップ。TSコンパイラ導入。`tsc --init`でtsconfig作成。Hello World実行 | GitHubリポジトリ作成。Hello World |
| 2/16 | 月 | 🌙 | VS Code環境整備 | 推奨拡張機能のインストール。ESLint + Prettier設定。tsconfig.jsonの各オプションの意味を調べる | VS Code設定完了、設定メモ作成 |
| 2/17 | 火 | 🏢 | 基本の型 | string, number, boolean, array, tuple, enum, any, unknown, void, null, undefined。VB.NETとの型対応表を自作 | 各型のサンプルコード + VB.NET対応表 |
| 2/17 | 火 | 🌙 | 記事読み | Zenn/Qiitaで「TypeScript 入門」の良記事を2〜3本読む(https://zenn.dev/hinoshin/articles/87b99f4ddc2729)(https://qiita.com/uhyo/items/e2fdef2d3236b9bfe74a) | 気になった記事をブックマーク |
| 2/18 | 水 | 🏢 | 関数の型付け | 引数・戻り値の型、オプション引数、デフォルト引数、アロー関数。VB.NETのFunction/Subとの違い | 四則演算関数、配列操作関数 |
| 2/18 | 水 | 🌙 | 型パズル | type-challenges（GitHub）のeasyレベルに挑戦(https://github.com/type-challenges/type-challenges/blob/main/README.ja.md) | 3〜5問解く |
| 2/19 | 木 | 🏢 | interface と type | オブジェクト型定義、interfaceのextends、typeのユニオン・インターセクション。VB.NETのClassとの比較 | ユーザー情報型の定義 |
| 2/19 | 木 | 🌙 | コードリーディング | GitHubでTypeScriptプロジェクトのコードを読む（小規模OSSのsrc/types/を眺める）(https://github.com/gvergnaud/ts-pattern)(https://github.com/sindresorhus/ky)(https://github.com/ai/nanoid) | 型定義の実例メモ |
| 2/20 | 金 | 🏢 | ユニオン型・リテラル型 | ユニオン型、リテラル型、型の絞り込み（typeof, in演算子）。VB.NETにない概念なので重点的に | ステータス管理サンプル（成功/失敗/ローディング） |
| 2/20 | 金 | 🌙 | 週の振り返り | Week1前半の復習。理解度チェックシート記入。つまずいたポイントの整理 | 振り返りメモ |
| 2/21 | 土 | 🏠 | TS実践（3h） | TypeScriptだけでCLIツールを作る。例：体重記録CLIツール（JSON読み書き）。型定義、関数、モジュール分割を実践 | CLIツール完成、GitHubにpush |
| 2/22 | 日 | 🏠 | CSS基礎の補強（3h） | HTMLとCSSの基礎をおさらい。ボックスモデル、Flexbox、Grid、ポジション。MDN Web Docsで学習。後のTailwind理解の土台作り | HTMLで基本レイアウトを3パターン作成 |

---

### Week 2（2/23〜3/1）：TypeScript 応用 - 実践的な型の使い方

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 2/23 | 月 | 🏢 | ジェネリクス | 基本構文、ジェネリック関数、ジェネリックインターフェース、制約（extends）。VB.NETの`Of T`との比較 | `ApiResponse<T>`型の設計 |
| 2/23 | 月 | 🌙 | 動画学習 | YouTubeでTypeScriptジェネリクスの解説動画（日本語）を視聴 | 視聴メモ |
| 2/24 | 火 | 🏢 | 型ユーティリティ | Partial, Required, Pick, Omit, Record, Readonly。実際のユースケース | User型から派生型を作成 |
| 2/24 | 火 | 🌙 | 型パズル続き | type-challengesのeasy〜mediumに挑戦 | 3〜5問解く |
| 2/25 | 水 | 🏢 | モジュールとES構文 | import/export、分割代入、スプレッド構文、テンプレートリテラル、Optional Chaining | 複数ファイルのTSプロジェクト |
| 2/25 | 水 | 🌙 | Git基礎 | Gitのブランチ操作（branch, checkout, merge, rebase）を練習。業務で必須 | ブランチ操作の練習リポジトリ |
| 2/26 | 木 | 🏢 | 非同期処理 | Promise, async/await, try/catch。VB.NETのAsync/Awaitとの比較。fetch API基本 | JSONPlaceholder APIからデータ取得スクリプト |
| 2/26 | 木 | 🌙 | 記事読み | 「TypeScript async/await」「Promise」関連の記事を読む | 理解メモ |
| 2/27 | 金 | 🏢 | TS総合演習 | TODOリストのロジック（追加・削除・完了切替・フィルタ）をTSだけで実装（UIなし） | `todo.ts` CLIベースTODO完成 |
| 2/27 | 金 | 🌙 | 週の振り返り | Week2の復習。理解度チェックシート更新 | 振り返りメモ |
| 2/28 | 土 | 🏠 | Git + GitHub実践（3h） | GitHubフロー（feature branch → PR → merge）を一人で練習。Issue作成→ブランチ→作業→PR→マージの流れを3回繰り返す | GitHubフローの練習完了 |
| 3/1 | 日 | 🏠 | REST API基礎（3h） | REST APIの概念（GET/POST/PUT/DELETE）、HTTPステータスコード、JSONの構造。Postmanでパブリックなて無料APIを叩いて体感 | Postmanでの API操作メモ |

---

### Week 3（3/2〜3/8）：React 基礎 - コンポーネント思考の習得

WinFormsのイベント駆動 → Reactの宣言的UI。最も重要なパラダイムシフトの週。

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 3/2 | 月 | 🏢 | React環境構築 + JSX | `npx create-next-app@latest`でプロジェクト作成。JSX文法、式の埋め込み、条件付きレンダリング | プロフィールカードコンポーネント |
| 3/2 | 月 | 🌙 | React概念の理解 | React公式「Reactの流儀」を読む。WinFormsとの考え方の違いを自分の言葉でまとめる | 「宣言的UI vs 命令的UI」メモ |
| 3/3 | 火 | 🏢 | コンポーネントとProps | コンポーネント作成、Propsの渡し方、TSでのProps型定義、children | Propsつきカードコンポーネント |
| 3/3 | 火 | 🌙 | 動画学習 | React入門の動画（日本語）を1セクション視聴 | 視聴メモ |
| 3/4 | 水 | 🏢 | useState | useStateの基本、オブジェクト/配列の状態管理（イミュータブル更新）。**状態→UIの自動再描画を体感** | カウンターアプリ、テキスト入力→リアルタイム表示 |
| 3/4 | 水 | 🌙 | 手を動かす | useStateの応用：トグル、アコーディオン、タブ切替を自力で実装 | 3つのUI部品 |
| 3/5 | 木 | 🏢 | イベント + リスト | onClick, onChange, onSubmit。map()によるリスト表示、keyの重要性 | シンプルTODOリスト（追加・表示） |
| 3/5 | 木 | 🌙 | 記事読み | 「React key なぜ必要」「React 再レンダリング」の記事を読む | 理解メモ |
| 3/6 | 金 | 🏢 | 三目並べチュートリアル | React公式チュートリアル写経。コンポーネント間のデータフロー、状態の持ち上げ | 三目並べゲーム完成 |
| 3/6 | 金 | 🌙 | 週の振り返り | Week3振り返り。理解度チェック更新。「WinFormsならこう書くがReactではこう」の対応メモ | 振り返り + 対応表更新 |
| 3/7 | 土 | 🏠 | ミニアプリ①（3h） | **じゃんけんアプリ**を自力で作る。ユーザーの選択→結果表示→勝敗カウント。useState、条件分岐、イベント処理の総合練習 | じゃんけんアプリ完成 |
| 3/8 | 日 | 🏠 | ミニアプリ②（3h） | **カラーパレットジェネレーター**。ランダムな色を生成→表示→クリックでコピー。配列のstate管理とイベント処理の応用 | カラーパレットアプリ完成 |

---

### Week 4（3/9〜3/15）：React 応用 - 実践パターンの習得

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 3/9 | 月 | 🏢 | useEffect | 副作用の概念、基本パターン、依存配列、クリーンアップ。**Form_Loadとの違い** | API取得→リスト表示コンポーネント |
| 3/9 | 月 | 🌙 | 深掘り | 「useEffectは不要かも」（React公式）を精読。不要なuseEffectのパターンを理解 | よくあるアンチパターンのメモ |
| 3/10 | 火 | 🏢 | フォーム処理 | 制御コンポーネント、バリデーション、複数入力管理。VB.NETのTextBox.Textとの比較 | ユーザー登録フォーム + バリデーション |
| 3/10 | 火 | 🌙 | 記事読み | 「React フォーム ベストプラクティス」系の記事 | メモ |
| 3/11 | 水 | 🏢 | useContext | コンテキスト作成・提供・消費、テーマ切替の実装 | ライト/ダークテーマ切替 |
| 3/11 | 水 | 🌙 | 動画学習 | useContext, useReducerの解説動画視聴 | 視聴メモ |
| 3/12 | 木 | 🏢 | カスタムフック | カスタムフックの設計。useFetch, useLocalStorage, useFormなど | useFetchフック作成・TODOに適用 |
| 3/12 | 木 | 🌙 | OSSのフック集を読む | usehooks-tsのソースコードを読み、実装パターンを学ぶ(https://github.com/juliencrn/usehooks-ts)(https://github.com/streamich/react-use)(https://github.com/react-hookz/web) | 気になったフックの実装メモ |
| 3/13 | 金 | 🏢 | React総合演習 | TODOアプリ本格版：追加・削除・完了切替・フィルタ・LocalStorage保存 | TODOアプリ完成 |
| 3/13 | 金 | 🌙 | 週の振り返り | Week4振り返り。理解度チェック更新 | 振り返りメモ |
| 3/14 | 土 | 🏠 | React Hook Form + zod（3h） | React Hook Formの導入、zodスキーマでのバリデーション。業務でフォームは頻出するので重点学習 | 登録フォームをRHF + zodで作り直し |
| 3/15 | 日 | 🏠 | Zustand + TanStack Query（3h） | Zustandで軽量な状態管理。TanStack QueryでAPI取得のキャッシュ・ローディング・エラー状態の管理 | Zustand + TanStack Queryのサンプルアプリ |

---

### Week 5（3/16〜3/22）：Tailwind CSS - ユーティリティファーストのスタイリング

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 3/16 | 月 | 🏢 | Tailwind入門 + Flexbox | ユーティリティファーストの思想、基本クラス（padding, margin, color, font）、Flexbox。Flexbox Froggy完走 | Tailwind Playで実験。Froggy完走 |
| 3/16 | 月 | 🌙 | Tailwind チートシート作成 | よく使うクラスの一覧を自分用にまとめる | チートシート（.mdファイル） |
| 3/17 | 火 | 🏢 | Grid + レスポンシブ | CSS Grid、レスポンシブプレフィックス（sm, md, lg, xl）、モバイルファースト | レスポンシブカードグリッド |
| 3/17 | 火 | 🌙 | 参考サイト模写 | Tailwind UIやdaisyUIのコンポーネント例を見て、気に入ったものを模写 | 模写コンポーネント1つ |
| 3/18 | 水 | 🏢 | コンポーネントスタイリング | ホバー・フォーカス・アクティブ、トランジション、条件付きクラス（clsx/cn） | ボタン・入力・カードのスタイル付きコンポーネント集 |
| 3/18 | 水 | 🌙 | shadcn/ui 調査 | shadcn/uiの仕組みを調べる。コピペで使えるコンポーネントライブラリの理解 | shadcn/uiの概要メモ |
| 3/19 | 木 | 🏢 | ダークモード + カスタマイズ | dark:プレフィックス、tailwind.config.jsカスタマイズ、カスタムカラー/フォント | ダークモード対応レイアウト |
| 3/19 | 木 | 🌙 | アクセシビリティ基礎 | セマンティックHTML、aria属性の基本、キーボードナビゲーション | アクセシビリティチェックリスト作成 |
| 3/20 | 金 | 🏢 | TODOアプリ リデザイン | Week4のTODOアプリにTailwind適用。レスポンシブ、ダークモード、アニメーション | Tailwind適用TODOアプリ完成 |
| 3/20 | 金 | 🌙 | 週の振り返り | Week5振り返り。理解度チェック更新 | 振り返りメモ |
| 3/21 | 土 | 🏠 | テスト入門（3h） | Jest + React Testing Library導入。コンポーネントテストの基本：render, screen, fireEvent, waitFor | TODOアプリに基本テスト3〜5件追加 |
| 3/22 | 日 | 🏠 | ポートフォリオ構想（3h） | Week8に向けたポートフォリオアプリの設計。画面構成、データ構造、使用技術の決定。候補：タスクボード / 家計簿 / ブログCMS | 設計ドキュメント（README.md） |

---

### Week 6（3/23〜3/29）：Next.js 基礎 - App Routerの理解

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 3/23 | 月 | 🏢 | Next.js概要 + ルーティング | Next.jsの利点、App Routerのファイルベースルーティング、page.tsx / layout.tsx / loading.tsx / error.tsx | 複数ページのNext.jsプロジェクト |
| 3/23 | 月 | 🌙 | SSR/SSG/ISRの概念整理 | 各レンダリング方式の違い、使い分けの判断基準をまとめる | レンダリング方式比較メモ |
| 3/24 | 火 | 🏢 | レイアウト + ナビゲーション | ルートレイアウト、ネストレイアウト、`<Link>`、usePathname。共通ヘッダー/サイドバー | 共通ナビ付きアプリ |
| 3/24 | 火 | 🌙 | 記事読み | 「Next.js App Router」の実践記事を読む | メモ |
| 3/25 | 水 | 🏢 | Server vs Client Components | RSCの概念、"use client"、判断基準。**WinFormsにはない概念** | Server/Client版の実装比較 |
| 3/25 | 水 | 🌙 | 深掘り | 「なぜServer Componentsが必要か」公式ブログや解説記事 | 理解メモ |
| 3/26 | 木 | 🏢 | データ取得 | Server Componentでのfetch、キャッシュ戦略、loading.tsx | API一覧/詳細表示 |
| 3/26 | 木 | 🌙 | 動画学習 | Next.js App Routerの解説動画 | 視聴メモ |
| 3/27 | 金 | 🏢 | 動的ルーティング | `[id]`パラメータ、generateStaticParams、catch-all | ブログ風アプリ（一覧→詳細） |
| 3/27 | 金 | 🌙 | 週の振り返り | Week6振り返り。理解度チェック更新 | 振り返りメモ |
| 3/28 | 土 | 🏠 | Supabase入門（3h） | Supabaseプロジェクト作成、テーブル定義、CRUD操作。Next.jsからの接続方法 | Supabase + Next.jsの接続サンプル |
| 3/29 | 日 | 🏠 | Prisma入門（3h） | PrismaでのDB操作基礎。スキーマ定義、マイグレーション、CRUD。Supabase PostgreSQLに接続 | Prisma + Supabaseのサンプル |

---

### Week 7（3/30〜4/5）：Next.js 応用 - 実務レベルの機能

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 3/30 | 月 | 🏢 | Server Actions + フォーム | Server Actionsの実装、zodバリデーション、revalidatePath | フォーム送信→保存→再表示 |
| 3/30 | 月 | 🌙 | 記事読み | Server Actionsのベストプラクティス記事 | メモ |
| 3/31 | 火 | 🏢 | Route Handlers (API) | GET/POST/PUT/DELETE、リクエスト/レスポンス処理、エラーハンドリング | REST CRUD APIエンドポイント |
| 3/31 | 火 | 🌙 | 動画学習 | Next.js Route Handlers解説動画 | 視聴メモ |
| 4/1 | 水 | 🏢 | ミドルウェア + 認証基礎 | middleware.ts、リダイレクト、NextAuth.js概要 | 未ログイン時リダイレクト |
| 4/1 | 水 | 🌙 | 認証の仕組み | JWT、Cookie、セッションの基礎知識を記事で学ぶ | 認証フロー理解メモ |
| 4/2 | 木 | 🏢 | エラーハンドリング + メタデータ | error.tsx, not-found.tsx、Metadata API、OGP | エラー境界 + メタデータ設定 |
| 4/2 | 木 | 🌙 | Vercelデプロイ予習 | Vercelのドキュメントを読む。デプロイの流れを理解 | デプロイ手順メモ |
| 4/3 | 金 | 🏢 | Next.js総合演習 | ダッシュボードアプリ作成開始（ルーティング、レイアウト、ナビ） | ダッシュボード骨格完成 |
| 4/3 | 金 | 🌙 | 週の振り返り | Week7振り返り。理解度チェック更新 | 振り返りメモ |
| 4/4 | 土 | 🏠 | ポートフォリオ開発①（3h） | Week5で設計したアプリの本格開発開始。Next.js + Tailwind + Prisma + Supabase。認証、DB連携込み | ポートフォリオアプリ：基本CRUD動作 |
| 4/5 | 日 | 🏠 | ポートフォリオ開発②（3h） | UI実装、Tailwindでスタイリング、レスポンシブ対応、ローディング/エラー状態 | ポートフォリオアプリ：UI完成 |

---

### Week 8（4/6〜4/12）：総合演習 + 業務準備

業務で想定される画面・機能を意識した総仕上げ。

| 日付 | 曜日 | 時間帯 | テーマ | 学習内容 | アウトプット |
|------|------|--------|--------|---------|-------------|
| 4/6 | 月 | 🏢 | 総合アプリ構築（1） | ダッシュボード：データ一覧画面（テーブル表示、ソート、ページネーション） | 一覧ページ完成 |
| 4/6 | 月 | 🌙 | テストの追加 | ダッシュボードアプリに基本テストを追加 | テスト3〜5件 |
| 4/7 | 火 | 🏢 | 総合アプリ構築（2） | 詳細・編集画面：フォーム→バリデーション→Server Action→更新→再表示 | CRUD一通り動作 |
| 4/7 | 火 | 🌙 | 記事読み | 「Next.js 本番運用」「パフォーマンス最適化」の記事 | メモ |
| 4/8 | 水 | 🏢 | 総合アプリ構築（3） | レスポンシブ対応、ローディング/エラー状態の実装、コンポーネント整理 | UI完成・コード整理 |
| 4/8 | 水 | 🌙 | リファクタリング | コンポーネントの責務分離、共通処理の切り出し、命名見直し | リファクタリング完了 |
| 4/9 | 木 | 🏢 | コードレビュー + 弱点補強 | 自分のコードを見直し。可能なら他者にレビュー依頼。理解度チェックで弱い部分を復習 | 弱点補強完了 |
| 4/9 | 木 | 🌙 | 業務準備 | 業務で使う技術スタック・コーディング規約の確認 | 規約メモ |
| 4/10 | 金 | 🏢 | 業務準備 + まとめ | 開発環境構築手順の確認。学習振り返りドキュメント作成 | README、業務参加準備完了 |
| 4/10 | 金 | 🌙 | 最終振り返り | 全8週間の理解度チェック最終記入。到達点と残課題の整理 | 最終振り返りドキュメント |
| 4/11 | 土 | 🏠 | ポートフォリオ仕上げ（3h） | Vercelにデプロイ。README整備、OGP設定、最終調整 | **ポートフォリオアプリ公開** |
| 4/12 | 日 | 🏠 | 予備日 / 弱点補強（3h） | 理解が浅い部分の最終補強。または休息日（燃え尽き防止） | 必要に応じて補強 |

---

## 8週間の成果物一覧

| # | 成果物 | 完成週 | 使用技術 |
|---|--------|--------|---------|
| 1 | TypeScript CLIツール | W1 土日 | TypeScript |
| 2 | HTML/CSS基本レイアウト | W1 土日 | HTML, CSS |
| 3 | 三目並べゲーム | W3 | React, TypeScript |
| 4 | じゃんけんアプリ | W3 土日 | React, TypeScript |
| 5 | カラーパレットジェネレーター | W3 土日 | React, TypeScript |
| 6 | TODOアプリ（React版） | W4 | React, TypeScript |
| 7 | TODOアプリ（Tailwind版） | W5 | React, TypeScript, Tailwind |
| 8 | TODOアプリ（テスト付き） | W5 土日 | React, TypeScript, Tailwind, Jest |
| 9 | ブログ風アプリ | W6 | Next.js, TypeScript, Tailwind |
| 10 | ダッシュボードアプリ | W7-W8 | Next.js, TypeScript, Tailwind, Server Actions |
| 11 | **ポートフォリオアプリ** | W7-W8 土日 | Next.js, TypeScript, Tailwind, Prisma, Supabase, Vercel |

---

## VB.NET / WinForms 経験者向け 概念対応表

| VB.NET / WinForms | React / Next.js / TypeScript | 注意点 |
|-------------------|------------------------------|--------|
| `Dim x As Integer = 10` | `const x: number = 10` | TSはletよりconst推奨 |
| `Sub / Function` | `const fn = (): void => {}` | アロー関数が主流 |
| `Class` | `interface / type` | TSではクラスより型定義が多用される |
| `Form` | ページコンポーネント（page.tsx） | 1 Form = 1ページに近い |
| `UserControl` | Reactコンポーネント | 再利用可能なUI部品 |
| `Button.Click += Handler` | `onClick={handler}` | JSXで直接指定 |
| `TextBox.Text = "value"` | `useState` + `onChange` | 双方向バインディング→一方向データフロー |
| `Form.Show()` | `<Link href="/page">` | ルーティングベースの画面遷移 |
| `Me.Controls.Add(ctrl)` | JSXで宣言的に記述 | 命令的→宣言的UIへの転換 |
| `DataGridView` | テーブルコンポーネント自作 or ライブラリ | TanStack Table 等が定番 |
| `Async / Await` | `async / await` | ほぼ同じ概念。Promise ベース |
| `Try / Catch` | `try / catch` | 構文はほぼ同一 |
| `Module / Namespace` | `import / export` | ファイル単位のモジュール |
| `Nothing` | `null / undefined` | 2種類あるので注意 |

---

## 推奨 VS Code 拡張機能

| 拡張機能 | 用途 |
|---------|------|
| ES7+ React/Redux/React-Native snippets | Reactコンポーネントのスニペット |
| TypeScript Importer | 自動import補完 |
| Tailwind CSS IntelliSense | Tailwindクラスの自動補完（必須） |
| Prettier | コード自動フォーマット |
| ESLint | コード品質チェック |
| Error Lens | エラーをインラインで表示 |
| Auto Rename Tag | HTML/JSXタグの自動リネーム |
| GitLens | Gitの履歴・blame表示 |

---

## 学習のコツ

### 写経から始めて改造する
チュートリアルをそのまま写経→動くことを確認→自分なりにアレンジ。この「改造」が理解を最も深める。

### エラーを恐れない
TypeScriptの型エラーやReactのランタイムエラーは最初は頻出する。エラーメッセージを読む→検索→解決のサイクルに慣れることが最重要スキル。

### GitHubに毎日pushする
学習用リポジトリに毎日コミット。コミットメッセージに「今日学んだこと」を書くと振り返りにもなる。草（Contribution Graph）が可視化のモチベーションになる。

### WinFormsとの比較を意識する
新しい概念は「WinFormsだとどうやっていたか」と比較する。差分で理解すると定着が早い。

### 土日は「作る」に集中する
平日にインプットしたことを土日にアウトプットするサイクルが最も効率的。土日にチュートリアルを進めるのではなく、自分でアプリを作る時間にする。

### 燃え尽きない
毎週末フルで勉強する必要はない。疲れた週は土日どちらかを休みにする勇気も大事。8週間走り切ることが最優先。
