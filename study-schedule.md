# React / Next.js / TypeScript / Tailwind CSS 学習計画

> **期間**: 2026/2/16（月）〜 2026/4/10（金）（8週間・平日40日）  
> **対象者**: .NET Framework 4.8 / WinForms / VB.NET 経験者  
> **前提**: 業務時間内に1日2〜3時間の学習時間を確保  
> **目標**: 2ヶ月後の業務でReact + Next.js + TypeScript + Tailwind CSSを使った開発に参加できるレベル

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

---

## 日付別スケジュール

### Week 1（2/16〜2/20）：TypeScript 基礎 - 型システムの理解

VB.NETの型の経験を活かしつつ、TypeScriptの型システムに慣れる週。

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 2/16 | 月 | 環境構築 + TS入門 | Node.js / npm / VS Code のセットアップ。TypeScriptコンパイラのインストール。`tsc --init`でtsconfig作成。Hello Worldを書いてコンパイル・実行 | サバイバルTS「開発環境の準備」「TypeScriptのあらまし」 | GitHubに学習用リポジトリ作成。Hello World を TS で実行 |
| 2/17 | 火 | 基本の型 | string, number, boolean, array, tuple, enum, any, unknown, void, null, undefined。VB.NETの型との対応表を自分で作る | サバイバルTS「値・型・変数」 | 各型を使った変数宣言のサンプルコード作成 |
| 2/18 | 水 | 関数の型付け | 引数の型、戻り値の型、オプション引数、デフォルト引数、アロー関数。VB.NETのFunction/Subとの違いを整理 | サバイバルTS「関数」 | 四則演算関数、配列操作関数をTSで実装 |
| 2/19 | 木 | interface と type | オブジェクト型の定義、interfaceの拡張（extends）、typeのユニオン・インターセクション。VB.NETのClassとの比較 | サバイバルTS「オブジェクト型」 | ユーザー情報（名前、年齢、住所など）をinterface/typeで定義 |
| 2/20 | 金 | ユニオン型・リテラル型 | ユニオン型（`string | number`）、リテラル型（`"success" | "error"`）、型の絞り込み（typeof, in演算子）。VB.NETにはない概念なので重点的に | サバイバルTS「ユニオン型」 | ステータス管理のサンプル（成功/失敗/ローディングを型で表現） |

### Week 2（2/23〜2/27）：TypeScript 応用 - 実践的な型の使い方

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 2/23 | 月 | ジェネリクス | ジェネリクスの基本構文、ジェネリック関数、ジェネリックインターフェース、制約（extends）。VB.NETの`Of T`との比較 | サバイバルTS「ジェネリクス」 | 汎用的なAPIレスポンス型`ApiResponse<T>`を設計 |
| 2/24 | 火 | 型ユーティリティ | Partial, Required, Pick, Omit, Record, Readonly。実際のユースケースと共に理解 | TS公式ハンドブック「Utility Types」 | 既存のUser型からフォーム用型（Partial）、表示用型（Pick）を派生 |
| 2/25 | 水 | モジュールとES構文 | import/export、デフォルトエクスポートと名前付きエクスポート。分割代入、スプレッド構文、テンプレートリテラル、Optional Chaining | サバイバルTS「import/export」 | 複数ファイルに分割したTSプロジェクトを作成 |
| 2/26 | 木 | 非同期処理 | Promise, async/await, try/catch。VB.NETのAsync/Awaitとの類似点と違いを確認。fetch APIの基本 | サバイバルTS「Promise / async / await」 | JSONPlaceholder APIからデータ取得するスクリプト作成 |
| 2/27 | 金 | TS総合演習 | Week 1-2の復習。TODOリストのロジック（追加・削除・完了切替・フィルタ）をTypeScriptだけで実装（UIなし、ロジックのみ） | - | `todo.ts` - CLIベースのTODO管理ロジック完成 |

### Week 3（3/2〜3/6）：React 基礎 - コンポーネント思考の習得

WinFormsのイベント駆動モデルとReactの宣言的UIの違いを理解する重要な週。

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 3/2 | 月 | React環境構築 + JSX | `npx create-next-app@latest`でプロジェクト作成（Next.js同梱だが、まずReactに集中）。JSXの文法、式の埋め込み、条件付きレンダリング | React公式「クイックスタート」「JSXでマークアップを書く」 | Reactプロジェクト作成。プロフィールカードコンポーネント作成 |
| 3/3 | 火 | コンポーネントとProps | コンポーネントの作成、Propsの渡し方、TypeScriptでのProps型定義、children props。WinFormsのUserControlとの比較 | React公式「コンポーネントにpropsを渡す」 | カードコンポーネントにPropsを追加、複数のカードを表示 |
| 3/4 | 水 | useState（状態管理） | useStateの基本、状態の更新、オブジェクト/配列の状態管理（イミュータブルな更新）。**WinFormsとの最大の違い：状態→UIの自動再描画** | React公式「stateの管理」「stateの更新」 | カウンターアプリ、テキスト入力→リアルタイム表示 |
| 3/5 | 木 | イベント処理 + リスト | onClick, onChange, onSubmit。配列のmap()によるリスト表示、keyの重要性。VB.NETのイベントハンドラとの比較 | React公式「イベントへの応答」「リストのレンダー」 | シンプルなTODOリスト（追加・表示）の実装 |
| 3/6 | 金 | 三目並べチュートリアル | React公式チュートリアル（Tic-Tac-Toe）を写経。コンポーネント間のデータフロー、状態の持ち上げを体感 | React公式チュートリアル | 三目並べゲーム完成 |

### Week 4（3/9〜3/13）：React 応用 - 実践パターンの習得

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 3/9 | 月 | useEffect | 副作用の概念、useEffectの基本パターン、依存配列、クリーンアップ。**WinFormsのForm_Loadとの違い** | React公式「エフェクトと同期する」「そのエフェクトは不要かも」 | APIからデータを取得してリスト表示するコンポーネント |
| 3/10 | 火 | フォーム処理 | 制御コンポーネント、フォームのバリデーション、複数入力の管理。VB.NETのTextBox.Textとの比較（双方向 vs 一方向バインディング） | React公式「入力をstateで管理する」 | ユーザー登録フォーム（名前・メール・パスワード）＋バリデーション |
| 3/11 | 水 | useContext | コンテキストの作成・提供・消費、テーマ切替の実装。グローバルな状態共有パターン | React公式「コンテキストでデータを深く渡す」 | ライト/ダークテーマ切替機能の実装 |
| 3/12 | 木 | カスタムフック | カスタムフックの設計と実装。useLocalStorage, useFetch, useFormなどの定番パターン | React公式「カスタムフックでロジックを再利用する」 | useFetch カスタムフック作成。TODO アプリに適用 |
| 3/13 | 金 | React総合演習 | Week3-4の総仕上げ：TODOアプリを本格的に作り直す。追加・削除・完了切替・フィルタ・LocalStorage保存 | - | React + TypeScript TODOアプリ完成（UI付き、スタイリングはまだ素朴でOK） |

### Week 5（3/16〜3/20）：Tailwind CSS - ユーティリティファーストのスタイリング

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 3/16 | 月 | Tailwind入門 + Flexbox | Tailwindの思想（ユーティリティファースト）、基本クラス（padding, margin, color, font）、Flexboxクラス（flex, justify, items, gap）。Flexbox Froggyでレイアウト感覚を掴む | Tailwind公式ドキュメント + Flexbox Froggy | Tailwind Playで各種レイアウトを実験。Flexbox Froggy完走 |
| 3/17 | 火 | Grid + レスポンシブ | CSS Gridクラス（grid, grid-cols, col-span）、レスポンシブプレフィックス（sm, md, lg, xl）、モバイルファーストの考え方 | Tailwind公式「Responsive Design」 | レスポンシブなカードグリッドレイアウト作成 |
| 3/18 | 水 | コンポーネントスタイリング | ホバー・フォーカス・アクティブ状態、トランジション・アニメーション、条件付きクラス（clsx/cn の使い方） | Tailwind公式「Hover, Focus, & Other States」 | ボタン・入力フィールド・カードのスタイル付きコンポーネント集 |
| 3/19 | 木 | ダークモード + カスタマイズ | ダークモード対応（dark:プレフィックス）、tailwind.config.jsのカスタマイズ、カスタムカラー・フォント設定 | Tailwind公式「Dark Mode」「Customization」 | ダークモード切替対応のレイアウト |
| 3/20 | 金 | TODOアプリ リデザイン | Week4で作ったTODOアプリにTailwind CSSを適用。レスポンシブ対応、ダークモード対応、アニメーション追加 | - | Tailwind CSS適用済みTODOアプリ完成 |

### Week 6（3/23〜3/27）：Next.js 基礎 - App Routerの理解

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 3/23 | 月 | Next.js概要 + ルーティング | Next.jsの利点（SSR/SSG/ISR）、App Routerのファイルベースルーティング、page.tsx / layout.tsx / loading.tsx / error.tsx の役割 | Next.js Learn Chapter 1-3 | 複数ページ（Home, About, Contact）のNext.jsプロジェクト作成 |
| 3/24 | 火 | レイアウトとナビゲーション | ルートレイアウト、ネストされたレイアウト、`<Link>`コンポーネント、usePathname。共通ヘッダー/サイドバーの実装 | Next.js Learn Chapter 4-5 | 共通ナビゲーション付きの複数ページアプリ |
| 3/25 | 水 | Server Components vs Client Components | RSCの概念、"use client"ディレクティブ、いつServerでいつClientか判断基準。**WinFormsにはない概念なので重点的に** | Next.js公式「Server and Client Components」 | 同じUIをServer Component版とClient Component版で実装比較 |
| 3/26 | 木 | データ取得 | Server Componentでのfetch、キャッシュ戦略、動的/静的レンダリング、loading.tsxでのサスペンス | Next.js Learn Chapter 7-9 | JSONPlaceholder APIからのデータ取得・一覧/詳細表示 |
| 3/27 | 金 | 動的ルーティング | `[id]`パラメータ、generateStaticParams、catch-allルート、パラレルルート | Next.js Learn Chapter 10 | ブログ風アプリ（記事一覧→記事詳細ページへの遷移） |

### Week 7（3/30〜4/3）：Next.js 応用 - 実務レベルの機能

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 3/30 | 月 | Server Actions + フォーム | Server Actionsの概念と実装、フォームの送信処理、バリデーション（zod）、revalidatePath | Next.js Learn Chapter 12-13 | フォーム送信→データ保存→再表示の一連の流れ |
| 3/31 | 火 | Route Handlers (API) | Route Handlersの作成（GET/POST/PUT/DELETE）、リクエスト/レスポンスの処理、エラーハンドリング | Next.js公式「Route Handlers」 | REST API風のCRUDエンドポイント作成 |
| 4/1 | 水 | ミドルウェア + 認証基礎 | middleware.tsの役割、リダイレクト、ヘッダー操作。NextAuth.js（Auth.js）の概要理解 | Next.js Learn Chapter 15 + Next.js公式「Middleware」 | 未ログイン時のリダイレクト実装 |
| 4/2 | 木 | エラーハンドリング + メタデータ | error.tsx, not-found.tsx、Metadata API（SEO対応）、OGP設定 | Next.js Learn Chapter 13 + Next.js公式「Metadata」 | エラー境界の実装、各ページにメタデータ設定 |
| 4/3 | 金 | Next.js総合演習 | Week6-7で学んだ機能を使ったミニダッシュボードアプリ作成開始 | - | ダッシュボードアプリの骨格完成（ルーティング、レイアウト、ナビ） |

### Week 8（4/6〜4/10）：総合演習 + 業務準備

業務で想定される画面・機能を意識した実践的なアプリ構築。

| 日付 | 曜日 | テーマ | 学習内容 | 教材 | アウトプット |
|------|------|--------|---------|------|-------------|
| 4/6 | 月 | 総合アプリ構築（1） | ダッシュボードアプリの実装：データ一覧画面（テーブル表示、ソート、ページネーション） | - | データ一覧ページ完成 |
| 4/7 | 火 | 総合アプリ構築（2） | 詳細画面・編集画面の実装：フォーム → バリデーション → Server Action → データ更新 → 再表示 | - | CRUD操作が一通り動作 |
| 4/8 | 水 | 総合アプリ構築（3） | レスポンシブ対応、ローディング/エラー状態の実装、コンポーネントの整理・リファクタリング | - | UI完成・コード整理 |
| 4/9 | 木 | コードレビュー + 弱点補強 | 自分のコードを見直し（可能であれば他者にレビュー依頼）。理解度チェックシートで弱い部分を重点復習 | - | 弱点の補強完了 |
| 4/10 | 金 | 業務準備 + まとめ | 業務で使う技術スタック・コーディング規約の確認。開発環境構築手順の確認。学習の振り返りドキュメント作成 | - | 学習振り返りREADME、業務参加準備完了 |

---

## 日々のルーティン

| 時間配分 | 内容 | 補足 |
|---------|------|------|
| 最初の30〜60分 | **インプット** | ドキュメントを読む。コードを読む。動画を観る |
| 次の90〜120分 | **アウトプット** | 実際にコードを書く。**最も重要な時間** |
| 最後の15分 | **振り返り** | 今日学んだことを3行メモ。理解度チェック更新 |

---

## VB.NET / WinForms 経験者向け 概念対応表

VB.NETの知識を活かすための対応関係を整理。

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

学習開始時にインストールしておくと効率が上がるもの。

| 拡張機能 | 用途 |
|---------|------|
| ES7+ React/Redux/React-Native snippets | Reactコンポーネントのスニペット |
| TypeScript Importer | 自動import補完 |
| Tailwind CSS IntelliSense | Tailwindクラスの自動補完（必須） |
| Prettier | コード自動フォーマット |
| ESLint | コード品質チェック |
| Error Lens | エラーをインラインで表示 |
| Auto Rename Tag | HTML/JSXタグの自動リネーム |

---

## 学習のコツ

### 写経から始めて改造する

チュートリアルをそのまま写経→動くことを確認→自分なりにアレンジ（色を変える、機能を追加する）。この「改造」が理解を深める。

### エラーを恐れない

TypeScriptの型エラーやReactのランタイムエラーは最初は頻出する。エラーメッセージを読む→検索する→解決するサイクルに慣れることが最重要スキル。

### GitHubに毎日pushする

学習用リポジトリに毎日コミットすることで進捗が可視化される。コミットメッセージに「今日学んだこと」を書くと振り返りにもなる。

### WinFormsとの比較を意識する

新しい概念が出てきたら「WinFormsだとどうやっていたか」を考える。差分で理解すると定着が早い。特に「宣言的UI」と「一方向データフロー」は最重要の概念転換。
