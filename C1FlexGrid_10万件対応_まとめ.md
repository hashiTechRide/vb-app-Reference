# VB.NET (.NET Framework 4.8) - C1FlexGrid 10万件表示 実装まとめ

## 前提
- 表示データ: `DataTable`（約10万件）
- 要件: 仮想化 / データ連動セルスタイル / SearchPanel / 列値に応じた行の編集可否制御

---

## 1. 基本セットアップ（DataTableバインド + 仮想化）

C1FlexGridは`DataSource`バインド時点で表示行のみ描画する仮想描画になっているが、10万件規模では初期化コストを抑える設定が重要。

```vb
Private statusColIndex As Integer

Private Sub SetupFlexGrid()
    With flexGrid1
        .BeginUpdate()

        ' 描画・計算コストを下げる
        .AutoSizeMode = C1.Win.C1FlexGrid.AutoSizeMode.None
        .ScrollTips = C1.Win.C1FlexGrid.ScrollTipsMode.None
        .SelectionMode = C1.Win.C1FlexGrid.SelectionMode.CellRange

        .DataSource = dtSource   ' 10万件のDataTable
        .OwnerDraw = True        ' セルスタイル用

        .EndUpdate()
    End With

    ' 列名→インデックスはデータ設定時にキャッシュしておく
    ' （OwnerDrawCell等で都度 Cols("名前") を呼ぶとコストがかかるため）
    statusColIndex = flexGrid1.Cols("Status").Index
End Sub
```

**再バインド時の注意**: `DataTable`を差し替える場合、列構成が変わる可能性があるため`statusColIndex`も再取得する。

```vb
Private Sub RebindData(newDt As DataTable)
    flexGrid1.BeginUpdate()
    flexGrid1.DataSource = newDt
    flexGrid1.EndUpdate()

    statusColIndex = flexGrid1.Cols("Status").Index
End Sub
```

---

## 2. 列の値に応じたセル色変更（OwnerDrawCell）

`OwnerDrawCell`は画面に見えている行のみ発火するため、10万件でもパフォーマンス影響は小さい。

```vb
Private Sub flexGrid1_OwnerDrawCell(sender As Object, e As OwnerDrawCellEventArgs) Handles flexGrid1.OwnerDrawCell
    If e.Row < 1 Then Return ' ヘッダー行は除外

    Dim colName As String = flexGrid1.Cols(e.Col).Name

    If colName = "Status" Then
        Dim val As String = TryCast(flexGrid1(e.Row, e.Col), String)
        e.Style = New CellStyle(e.Style)

        Select Case val
            Case "NG"
                e.Style.BackColor = Color.MistyRose
                e.Style.ForeColor = Color.DarkRed
            Case "OK"
                e.Style.BackColor = Color.Gainsboro ' 編集不可を視覚化
            Case "Pending"
                e.Style.BackColor = Color.LightYellow
        End Select
    End If
End Sub
```

> `OwnerDraw = True`が必須。独自描画になるため、既存の枠線・選択表示との見た目の整合は要確認。

---

## 3. 行の編集可否制御（値に応じて）

### 3-1. 通常のセル編集 → `BeforeEdit`

```vb
Private Sub flexGrid1_BeforeEdit(sender As Object, e As RowColEventArgs) Handles flexGrid1.BeforeEdit
    If IsRowLocked(e.Row) Then e.Cancel = True
End Sub

Private Function IsRowLocked(row As Integer) As Boolean
    If row < 1 OrElse row >= flexGrid1.Rows.Count Then Return False
    Dim status As String = TryCast(flexGrid1(row, statusColIndex), String)
    Return status = "OK"
End Function
```

### 3-2. 【重要】`BeforeEdit`だけでは貼り付け・範囲削除を防げない

| 操作 | 発火するイベント |
|---|---|
| ダブルクリック/F2/文字入力で編集開始 | `BeforeEdit` |
| Ctrl+V 貼り付け | `Pasting` |
| Delete キーで範囲クリア | `BeforeEdit`を通らないことが多い |

**`BeforeEdit`のみのガードでは、貼り付けとDelete削除が素通りする**ため、追加の防御が必要。

```vb
' 貼り付け対策
Private Sub flexGrid1_Pasting(sender As Object, e As System.ComponentModel.CancelEventArgs) Handles flexGrid1.Pasting
    For Each rng As CellRange In flexGrid1.Selection
        For r As Integer = rng.r1 To rng.r2
            If IsRowLocked(r) Then
                e.Cancel = True
                Exit Sub
            End If
        Next
    Next
End Sub

' Deleteキーでの範囲クリア対策
Private Sub flexGrid1_KeyDown(sender As Object, e As KeyEventArgs) Handles flexGrid1.KeyDown
    If e.KeyCode = Keys.Delete Then
        For Each rng As CellRange In flexGrid1.Selection
            For r As Integer = rng.r1 To rng.r2
                If IsRowLocked(r) Then
                    e.SuppressKeyPress = True
                    Exit Sub
                End If
            Next
        Next
    End If
End Sub
```

### 3-3. より堅牢な方法: `Row.AllowEditing` ベース（推奨）

イベントを個別に潰す方式は漏れが出やすい。`Row.AllowEditing = False`にしておけば**貼り付け・Delete削除もC1FlexGrid側が内部で弾く**ため確実。

ただし10万行を初期バインド時に全ループするのは重いので、**変更があった行だけ都度更新**する運用にする。

```vb
Private Sub UpdateRowLock(row As Integer)
    Dim status As String = TryCast(flexGrid1(row, statusColIndex), String)
    flexGrid1.Rows(row).AllowEditing = (status <> "OK")
End Sub
```

- Status列の値が変更されたタイミングで、その行だけ`UpdateRowLock`を呼ぶ
- 全行の初期ループは避ける

---

## 4. SearchPanel の追加

```vb
Private WithEvents searchPanel1 As New C1.Win.C1FlexGrid.C1SearchPanel()

Private Sub SetupSearchPanel()
    searchPanel1.FlexGrid = flexGrid1
    searchPanel1.Dock = DockStyle.Top
    Me.Controls.Add(searchPanel1)

    ' 10万件だと入力毎の検索が重いため、確定までの遅延を設定
    searchPanel1.Delay = 300 ' ms
End Sub
```

---

## 5. 10万件規模での注意点まとめ

| 項目 | 対策 |
|---|---|
| 初期ロード | `BeginUpdate`/`EndUpdate`で必ず囲む |
| 列幅自動計算 | `AutoSizeMode = None`にして固定幅、または一度だけ計算 |
| ソート | DataTable側の`DefaultView.Sort`の方が速いことが多い |
| フィルタ | `C1FlexGridFilter`は件数が多いと重い → `DataView.RowFilter`を検討 |
| 再描画 | セルスタイル変更のたびに`Invalidate`しない。まとめて反映 |
| 列名解決 | `Cols("名前")`は都度呼ばずインデックスをキャッシュ |
| 編集可否 | `BeforeEdit`単体はNG。`Pasting`/`KeyDown`併用 or `Row.AllowEditing`推奨 |
| SearchPanel | `Delay`プロパティで入力中の検索を抑制 |

---

## 未確定事項（要確認）

- 色を変える「特定列」と編集可否を決める「特定列」が同一か別かは未確認（今回は同じ`Status`列と仮定してサンプル作成）
- `OwnerDraw = True`化による既存の枠線・選択表示への影響は実機確認が必要
