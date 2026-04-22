# WinForms 品番展開画面 エラー表示実装ガイド

品番展開画面におけるエラー表示・動的レイアウト・表示切替の実装パターンをまとめます。

---

## 1. エラー表示の実装方式 — 3つの選択肢

### 方式A：Panel + Label の組み合わせ（推奨）

エラー領域を `Panel` として用意し、その中に複数行エラーを表示する `Label` を配置します。`Panel.AutoSize = True` を使えばエラー件数に応じてサイズが自動調整されます。

**コントロール構成：**

```
pnlError (Panel)
  ├─ BackColor   = #FFF0F0 (薄赤)
  ├─ BorderStyle = FixedSingle
  ├─ AutoSize    = True
  ├─ AutoSizeMode = GrowAndShrink
  └─ lblError (Label)
       ├─ AutoSize = True
       ├─ ForeColor = #8B1A10
       └─ Text = "・品番位置に * が2個含まれています\n・開始品番が終了品番より大きいです"
```

**メリット：**

- 実装がシンプル
- 改行（`\n`）で複数行エラーを自然に並べられる
- `AutoSize` で高さが件数に応じて自動調整
- コントロール数が少なく軽量

**デメリット：**

- エラー1件ごとに個別の装飾（アイコン色分け等）は難しい
- エラー文字列を組み立てるロジックが必要

---

### 方式B：FlowLayoutPanel + 複数 Label

エラー1件ごとに `Label` を動的に追加/削除する方式です。

**コントロール構成：**

```
pnlError (Panel)            ← 背景色・枠線
  └─ flpErrors (FlowLayoutPanel)
       ├─ FlowDirection = TopDown
       ├─ WrapContents = False
       ├─ AutoSize = True
       └─ 動的に Label を Controls.Add
```

**メリット：**

- エラー1件ごとに個別に装飾可能（アイコン、色、リンク等）
- 特定エラーだけ削除・更新しやすい
- 動的な追加/削除が自然

**デメリット：**

- コントロール数が増えるため若干重い
- 追加削除のロジックが煩雑
- 件数が多い場合のパフォーマンスに注意

---

### 方式C：ErrorProvider（各入力欄横にアイコン表示）

WinForms 標準の `ErrorProvider` コンポーネントで、エラーのある入力欄の隣にビックリマークアイコンを表示する方式です。

**メリット：**

- 標準コンポーネントで実装簡単
- エラー発生箇所が入力欄の横に直接出るので直感的
- ホバーでツールチップ表示

**デメリット：**

- エラーサマリが一箇所にまとまらない
- 見落としやすい
- アイコンだけで詳細はツールチップのみ

---

### 推奨：方式A ＋ ErrorProvider のハイブリッド

今回の要件のように「複数エラーを一覧で見せたい」ケースでは **方式A（Panel + Label）** が最適です。入力欄横の赤枠は独自のスタイル指定（`BackColor` の切替）で実現できます。

補助的に `ErrorProvider` を併用すれば、ユーザーは以下の両方の視点でエラーを認識できます：

- サマリ：画面下部のエラーパネル
- 個別：各入力欄の横のビックリマーク

---

## 2. 方式A のサンプルコード（VB.NET）

```vb
Public Class frmPartNumberExpansion

    ' --- エラー表示用コントロール ---
    Private pnlError As Panel
    Private lblError As Label

    Private Sub InitializeErrorPanel()
        pnlError = New Panel() With {
            .BackColor = Color.FromArgb(255, 240, 240),
            .BorderStyle = BorderStyle.FixedSingle,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .Padding = New Padding(6, 4, 6, 4),
            .Dock = DockStyle.Top,
            .Visible = False  ' 初期は非表示
        }

        lblError = New Label() With {
            .AutoSize = True,
            .ForeColor = Color.FromArgb(139, 26, 16),
            .Font = New Font("Meiryo UI", 9),
            .Dock = DockStyle.Fill
        }

        pnlError.Controls.Add(lblError)
        grpBatchGenerate.Controls.Add(pnlError)
    End Sub

    ' --- エラー表示 ---
    Private Sub ShowErrors(errors As List(Of String))
        If errors Is Nothing OrElse errors.Count = 0 Then
            pnlError.Visible = False
            Return
        End If

        Dim header = $"入力エラー（{errors.Count}件）" & Environment.NewLine
        Dim body = String.Join(Environment.NewLine, errors.Select(Function(e) "・" & e))
        lblError.Text = header & body
        pnlError.Visible = True
    End Sub

    ' --- バリデーション ---
    Private Function ValidateInput() As List(Of String)
        Dim errors As New List(Of String)

        ' 品番位置の * が1個かチェック
        If CountAsterisk(txtItemCodeTemplate.Text) <> 1 Then
            errors.Add("品目コードの品番位置：* は1つだけ指定してください")
            txtItemCodeTemplate.BackColor = Color.FromArgb(255, 240, 240)
        Else
            txtItemCodeTemplate.BackColor = Color.White
        End If

        ' 桁数チェック
        If txtStart.Text.Length <> txtEnd.Text.Length Then
            errors.Add($"開始品番({txtStart.Text} / {txtStart.Text.Length}桁) " &
                       $"と 終了品番({txtEnd.Text} / {txtEnd.Text.Length}桁) の桁数が一致しません")
            txtStart.BackColor = Color.FromArgb(255, 240, 240)
            txtEnd.BackColor = Color.FromArgb(255, 240, 240)
        Else
            txtStart.BackColor = Color.White
            txtEnd.BackColor = Color.White
        End If

        ' 開始 > 終了 チェック
        If String.Compare(txtStart.Text, txtEnd.Text) > 0 Then
            errors.Add($"開始品番({txtStart.Text}) が 終了品番({txtEnd.Text}) より大きくなっています")
        End If

        Return errors
    End Function

    ' --- 入力変更時にリアルタイム検証 ---
    Private Sub OnInputChanged(sender As Object, e As EventArgs) _
            Handles txtStart.TextChanged, txtEnd.TextChanged,
                    txtStep.TextChanged, txtItemCodeTemplate.TextChanged

        Dim errors = ValidateInput()
        ShowErrors(errors)

        ' エラーがあればボタン無効化
        btnAddToPreview.Enabled = (errors.Count = 0)

        ' プレビューの切替
        RefreshInlinePreview(errors.Count = 0)
    End Sub

End Class
```

---

## 3. 正常時 ⇔ エラー時の表示切替

### パターン1：同じ領域で切り替え（省スペース）

展開結果プレビューとエラーパネルを同じ位置に配置し、どちらかを `Visible = True/False` で切り替えます。

```
grpBatchGenerate (GroupBox)
  ├─ [入力欄群]
  ├─ pnlPreview  (Panel, Visible = True)   ← 正常時
  │    └─ プレビューボックス
  └─ pnlError    (Panel, Visible = False)  ← エラー時
       └─ lblError
```

**表示切替ロジック：**

```vb
Private Sub RefreshInlinePreview(isValid As Boolean)
    pnlPreview.Visible = isValid
    pnlError.Visible = Not isValid

    If isValid Then
        GeneratePreviewContent()
    End If
End Sub
```

### パターン2：両方表示（エラーはプレビューの上/下）

エラーパネルをプレビューの上か下に配置し、エラー時にのみ展開。常にプレビューも見える。

**メリット：** 正常に戻った時の展開結果がエラー前と比較できる
**デメリット：** 縦幅を消費する

---

## 4. GroupBox のサイズ動的変更

### 基本方針：AutoSize を使う

`GroupBox` 自体に `AutoSize = True` を設定すれば、内部コントロールの高さに応じて自動追従します。

```vb
grpBatchGenerate.AutoSize = True
grpBatchGenerate.AutoSizeMode = AutoSizeMode.GrowAndShrink
```

ただし、**親コンテナも AutoSize にするか、Dock/Anchor で追従させる必要があります**。

### 推奨レイアウト：TableLayoutPanel で縦積み

画面全体を `TableLayoutPanel` で縦に積み、各行の高さを `AutoSize` にすれば、GroupBox の伸縮に自動追従します。

```
Form
 └─ tlpMain (TableLayoutPanel, Dock = Fill)
      ├─ ColumnStyles: Percent 100%
      ├─ RowStyles:
      │    [0] AutoSize (変更対象)
      │    [1] AutoSize (品番位置の指定)
      │    [2] AutoSize (品番の一括生成 ← エラー表示で伸縮)
      │    [3] Percent 100% (展開プレビュー ← 残り全て)
      │    [4] AutoSize (ボタン行)
      ├─ [0] grpChangeTarget
      ├─ [1] grpItemPosition
      ├─ [2] grpBatchGenerate
      ├─ [3] grpPreview
      └─ [4] pnlButtons
```

**この構成で実現されること：**

- エラー表示時：`grpBatchGenerate` の高さが伸びる → `grpPreview`（Percent）が縮む
- 正常時：`grpBatchGenerate` の高さが縮む → `grpPreview` が広がる
- ウィンドウリサイズ：`grpPreview` だけが伸縮する（他は固定高）

### 縮み防止：MinimumSize

プレビューが縮みすぎて使い物にならなくなるのを防ぐため、最小サイズを設定します。

```vb
grpPreview.MinimumSize = New Size(0, 200)
```

---

## 5. 展開プレビューとエラーメッセージの切替設計

### 設計案：状態駆動でレンダリング

画面の状態を列挙型で管理し、状態遷移時に表示を一括更新します。

```vb
Private Enum PreviewState
    Idle          ' 入力途中（プレビュー空）
    [Error]       ' バリデーションエラー
    Valid         ' 正常、プレビュー表示
End Enum

Private _state As PreviewState = PreviewState.Idle

Private Sub RenderState()
    Select Case _state
        Case PreviewState.Idle
            pnlPreview.Visible = False
            pnlError.Visible = False
            btnAddToPreview.Enabled = False

        Case PreviewState.Error
            pnlPreview.Visible = False
            pnlError.Visible = True
            btnAddToPreview.Enabled = False

        Case PreviewState.Valid
            pnlPreview.Visible = True
            pnlError.Visible = False
            btnAddToPreview.Enabled = True
            GeneratePreviewContent()
    End Select
End Sub
```

これで、入力変更時の処理は次の3行で済みます：

```vb
Private Sub OnInputChanged(sender As Object, e As EventArgs) Handles ...
    Dim errors = ValidateInput()
    _state = DetermineState(errors)
    RenderState()
End Sub
```

---

## 6. SuspendLayout / ResumeLayout によるちらつき防止

`AutoSize` や `Visible` の切替時にコントロールが一瞬ちらつくことがあります。`SuspendLayout` / `ResumeLayout` で抑制できます。

```vb
Private Sub RenderState()
    grpBatchGenerate.SuspendLayout()
    Try
        ' 表示切替処理
        pnlPreview.Visible = ...
        pnlError.Visible = ...
        lblError.Text = ...
    Finally
        grpBatchGenerate.ResumeLayout(True)
    End Try
End Sub
```

さらに描画停止が必要な場合は `WM_SETREDRAW` メッセージを送る手法もありますが、通常は `SuspendLayout` で十分です。

---

## 7. まとめ：実装チェックリスト

- [ ] エラー表示は `Panel + Label` 方式で実装
- [ ] `Panel.AutoSize = True` で動的高さ対応
- [ ] エラー時は `txtXxx.BackColor` で該当入力欄を薄赤に
- [ ] 正常時のプレビューパネルと、エラーパネルは同じ位置で `Visible` 切替
- [ ] 親は `TableLayoutPanel` で縦積み、プレビュー行のみ `Percent 100%`
- [ ] `GroupBox.AutoSize = True` でエラー件数に追従
- [ ] 状態管理は `enum` で一元化、`RenderState()` で描画
- [ ] `SuspendLayout` / `ResumeLayout` でちらつき抑止
- [ ] `ErrorProvider` を併用して入力欄横にアイコン表示（任意）

---

## 補足：TextBox の BackColor 切替の注意点

`TextBox` の `BackColor` をエラー時に変えると、 Windows の Visual Styles と相性が悪くフラットな見た目になる場合があります。気になる場合は以下を検討してください：

- `BorderStyle = FixedSingle` に変更してフラット化を許容する
- `Panel` で `TextBox` を囲み、Panel の BackColor を切替
- `ErrorProvider` のアイコン表示だけで済ませる（入力欄は白のまま）

業務アプリでは視認性優先で `BackColor` 切替を使うのが一般的です。
