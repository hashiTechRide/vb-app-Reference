## はじめに

ComponentOne の C1FlexGrid は、高機能なグリッドコントロールですが、行やセルの選択方法が多様で、初めて使う際に戸惑うことがあります。

本記事では、C1FlexGridの選択機能を網羅的に解説し、実用的なサンプルコードとともに紹介します。

### 開発環境
- 開発対象: .NET Framework 4.8
- 開発言語: VB.NET
- コントロール: ComponentOne C1FlexGrid

### この記事で学べること
- 選択モードの種類と使い分け
- プログラムからの行・セル選択
- 選択状態の取得方法
- 選択範囲の操作
- 実務で使えるサンプルコード

## 1. 選択モードの種類

C1FlexGridには複数の選択モードがあり、`SelectionMode`プロパティで設定します。

```vb
Imports C1.Win.C1FlexGrid

Public Class Form1
    Private Sub Form1_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        ' 選択モードの設定
        C1FlexGrid1.SelectionMode = SelectionModeEnum.Row
    End Sub
End Class
```

### 1-1. 選択モード一覧

| モード | 説明 | 用途 |
|--------|------|------|
| `Cell` | 単一セル選択 | セル単位の編集 |
| `CellRange` | セル範囲選択（矩形） | 複数セルのコピー |
| `Row` | 単一行選択 | 行単位の操作 |
| `RowRange` | 複数行選択（連続） | 複数行の一括処理 |
| `ListBox` | 複数行選択（非連続可） | Ctrl+クリックで複数選択 |
| `Free` | 自由選択（非推奨） | 特殊な用途 |

### 1-2. 各モードの設定例

```vb
' セル単位の選択
C1FlexGrid1.SelectionMode = SelectionModeEnum.Cell

' セル範囲選択（Excelライク）
C1FlexGrid1.SelectionMode = SelectionModeEnum.CellRange

' 行単位の選択
C1FlexGrid1.SelectionMode = SelectionModeEnum.Row

' 複数行の範囲選択（Shift+クリック）
C1FlexGrid1.SelectionMode = SelectionModeEnum.RowRange

' 複数行の非連続選択（Ctrl+クリック）
C1FlexGrid1.SelectionMode = SelectionModeEnum.ListBox
```

### 1-3. 選択モードの動作比較

```vb
Private Sub SetupSelectionModeDemo()
    ' デモ用のデータを設定
    With C1FlexGrid1
        .Rows.Count = 10
        .Cols.Count = 5
        
        For i = 1 To .Rows.Count - 1
            For j = 1 To .Cols.Count - 1
                .Item(i, j) = $"R{i}C{j}"
            Next
        Next
        
        ' ヘッダー設定
        For j = 1 To .Cols.Count - 1
            .Item(0, j) = $"列{j}"
        Next
    End With
End Sub

Private Sub btnCellMode_Click(sender As Object, e As EventArgs) Handles btnCellMode.Click
    C1FlexGrid1.SelectionMode = SelectionModeEnum.Cell
    MessageBox.Show("単一セル選択モード：セルを1つだけ選択できます")
End Sub

Private Sub btnCellRangeMode_Click(sender As Object, e As EventArgs) Handles btnCellRangeMode.Click
    C1FlexGrid1.SelectionMode = SelectionModeEnum.CellRange
    MessageBox.Show("セル範囲選択モード：ドラッグで矩形範囲を選択できます")
End Sub

Private Sub btnRowMode_Click(sender As Object, e As EventArgs) Handles btnRowMode.Click
    C1FlexGrid1.SelectionMode = SelectionModeEnum.Row
    MessageBox.Show("単一行選択モード：行を1つだけ選択できます")
End Sub

Private Sub btnRowRangeMode_Click(sender As Object, e As EventArgs) Handles btnRowRangeMode.Click
    C1FlexGrid1.SelectionMode = SelectionModeEnum.RowRange
    MessageBox.Show("行範囲選択モード：Shiftを押しながらクリックで範囲選択できます")
End Sub

Private Sub btnListBoxMode_Click(sender As Object, e As EventArgs) Handles btnListBoxMode.Click
    C1FlexGrid1.SelectionMode = SelectionModeEnum.ListBox
    MessageBox.Show("リストボックスモード：Ctrlを押しながらクリックで非連続選択できます")
End Sub
```

## 2. プログラムからの行選択

### 2-1. 基本的な行選択

```vb
' 単一行を選択
Private Sub SelectSingleRow(rowIndex As Integer)
    With C1FlexGrid1
        ' 選択範囲を指定（行全体）
        .Select(rowIndex, 1, rowIndex, .Cols.Count - 1)
        
        ' または、Rowプロパティを使用
        .Row = rowIndex
    End With
End Sub

' 使用例
Private Sub btnSelectRow3_Click(sender As Object, e As EventArgs) Handles btnSelectRow3.Click
    SelectSingleRow(3) ' 3行目を選択
End Sub
```

### 2-2. 複数行の選択

```vb
' 連続した複数行を選択
Private Sub SelectRowRange(startRow As Integer, endRow As Integer)
    With C1FlexGrid1
        ' SelectionModeをRowRangeに設定
        .SelectionMode = SelectionModeEnum.RowRange
        
        ' 開始行から終了行まで選択
        .Select(startRow, 1, endRow, .Cols.Count - 1)
    End With
End Sub

' 使用例
Private Sub btnSelectRows3To7_Click(sender As Object, e As EventArgs) Handles btnSelectRows3To7.Click
    SelectRowRange(3, 7) ' 3行目から7行目まで選択
End Sub
```

### 2-3. 非連続な複数行の選択

```vb
' 非連続な複数行を選択（ListBoxモード）
Private Sub SelectMultipleRows(rowIndices As Integer())
    With C1FlexGrid1
        ' SelectionModeをListBoxに設定
        .SelectionMode = SelectionModeEnum.ListBox
        
        ' 既存の選択をクリア
        .Select(-1, -1)
        
        ' 各行を選択状態に
        For Each rowIndex In rowIndices
            .Rows(rowIndex).Selected = True
        Next
    End With
End Sub

' 使用例
Private Sub btnSelectRows2_5_8_Click(sender As Object, e As EventArgs) Handles btnSelectRows2_5_8.Click
    SelectMultipleRows(New Integer() {2, 5, 8}) ' 2行目、5行目、8行目を選択
End Sub
```

### 2-4. すべての行を選択

```vb
' すべてのデータ行を選択
Private Sub SelectAllRows()
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.RowRange
        .Select(1, 1, .Rows.Count - 1, .Cols.Count - 1)
    End With
End Sub

' 使用例
Private Sub btnSelectAll_Click(sender As Object, e As EventArgs) Handles btnSelectAll.Click
    SelectAllRows()
End Sub
```

## 3. プログラムからのセル選択

### 3-1. 単一セルの選択

```vb
' 特定のセルを選択
Private Sub SelectCell(row As Integer, col As Integer)
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.Cell
        .Select(row, col)
        
        ' または
        .Row = row
        .Col = col
    End With
End Sub

' 使用例
Private Sub btnSelectCell_Click(sender As Object, e As EventArgs) Handles btnSelectCell.Click
    SelectCell(3, 2) ' 3行目2列目を選択
End Sub
```

### 3-2. セル範囲の選択

```vb
' セル範囲を選択（矩形）
Private Sub SelectCellRange(startRow As Integer, startCol As Integer, endRow As Integer, endCol As Integer)
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.CellRange
        .Select(startRow, startCol, endRow, endCol)
    End With
End Sub

' 使用例
Private Sub btnSelectRange_Click(sender As Object, e As EventArgs) Handles btnSelectRange.Click
    ' 2行2列から5行4列まで選択
    SelectCellRange(2, 2, 5, 4)
End Sub
```

### 3-3. 列全体の選択

```vb
' 特定の列全体を選択
Private Sub SelectColumn(colIndex As Integer)
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.CellRange
        .Select(1, colIndex, .Rows.Count - 1, colIndex)
    End With
End Sub

' 使用例
Private Sub btnSelectColumn2_Click(sender As Object, e As EventArgs) Handles btnSelectColumn2.Click
    SelectColumn(2) ' 2列目を選択
End Sub
```

### 3-4. CellRange構造体を使った選択

```vb
' CellRange構造体を使った選択
Private Sub SelectUsingCellRange()
    Dim range As New CellRange(2, 2, 5, 4)
    
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.CellRange
        .Selection = range
    End With
End Sub

' 使用例
Private Sub btnSelectUsingCellRange_Click(sender As Object, e As EventArgs) Handles btnSelectUsingCellRange.Click
    SelectUsingCellRange()
End Sub
```

## 4. 選択状態の取得

### 4-1. 現在選択されている行・列の取得

```vb
' 現在選択されている行と列を取得
Private Sub GetCurrentSelection()
    With C1FlexGrid1
        Dim currentRow = .Row
        Dim currentCol = .Col
        
        MessageBox.Show($"現在の選択: 行={currentRow}, 列={currentCol}")
    End With
End Sub

' 使用例
Private Sub btnGetCurrent_Click(sender As Object, e As EventArgs) Handles btnGetCurrent.Click
    GetCurrentSelection()
End Sub
```

### 4-2. 選択範囲の取得

```vb
' 選択範囲を取得
Private Sub GetSelectionRange()
    With C1FlexGrid1
        Dim selection = .Selection
        
        Dim info As String = $"選択範囲:{Environment.NewLine}" &
                            $"開始行: {selection.r1}{Environment.NewLine}" &
                            $"開始列: {selection.c1}{Environment.NewLine}" &
                            $"終了行: {selection.r2}{Environment.NewLine}" &
                            $"終了列: {selection.c2}{Environment.NewLine}" &
                            $"行数: {selection.Rows}{Environment.NewLine}" &
                            $"列数: {selection.Cols}"
        
        MessageBox.Show(info)
    End With
End Sub

' 使用例
Private Sub btnGetSelectionRange_Click(sender As Object, e As EventArgs) Handles btnGetSelectionRange.Click
    GetSelectionRange()
End Sub
```

### 4-3. 選択されているすべての行を取得

```vb
' 選択されているすべての行インデックスを取得
Private Function GetSelectedRowIndices() As List(Of Integer)
    Dim selectedRows As New List(Of Integer)
    
    With C1FlexGrid1
        ' ListBoxモードまたはRowRangeモードの場合
        If .SelectionMode = SelectionModeEnum.ListBox OrElse .SelectionMode = SelectionModeEnum.RowRange Then
            For i = 1 To .Rows.Count - 1
                If .Rows(i).Selected Then
                    selectedRows.Add(i)
                End If
            Next
        Else
            ' その他のモードの場合、Selectionから取得
            Dim selection = .Selection
            For i = selection.r1 To selection.r2
                selectedRows.Add(i)
            Next
        End If
    End With
    
    Return selectedRows
End Function

' 使用例
Private Sub btnGetSelectedRows_Click(sender As Object, e As EventArgs) Handles btnGetSelectedRows.Click
    Dim selectedRows = GetSelectedRowIndices()
    
    If selectedRows.Count = 0 Then
        MessageBox.Show("行が選択されていません")
    Else
        Dim rowList = String.Join(", ", selectedRows)
        MessageBox.Show($"選択されている行: {rowList}")
    End If
End Sub
```

### 4-4. 選択範囲のデータを取得

```vb
' 選択範囲のデータを取得
Private Function GetSelectedData() As List(Of List(Of String))
    Dim data As New List(Of List(Of String))
    
    With C1FlexGrid1
        Dim selection = .Selection
        
        For row = selection.r1 To selection.r2
            Dim rowData As New List(Of String)
            
            For col = selection.c1 To selection.c2
                rowData.Add(.GetData(row, col)?.ToString())
            Next
            
            data.Add(rowData)
        Next
    End With
    
    Return data
End Function

' 使用例
Private Sub btnGetSelectedData_Click(sender As Object, e As EventArgs) Handles btnGetSelectedData.Click
    Dim data = GetSelectedData()
    
    Dim result As New System.Text.StringBuilder()
    result.AppendLine("選択範囲のデータ:")
    
    For Each rowData In data
        result.AppendLine(String.Join(", ", rowData))
    Next
    
    MessageBox.Show(result.ToString())
End Sub
```

## 5. 選択範囲の操作

### 5-1. 選択のクリア

```vb
' 選択をクリア
Private Sub ClearSelection()
    With C1FlexGrid1
        ' 方法1: 無効な範囲を選択
        .Select(-1, -1)
        
        ' 方法2: ListBoxモードの場合、各行の選択を解除
        If .SelectionMode = SelectionModeEnum.ListBox Then
            For i = 1 To .Rows.Count - 1
                .Rows(i).Selected = False
            Next
        End If
    End With
End Sub

' 使用例
Private Sub btnClearSelection_Click(sender As Object, e As EventArgs) Handles btnClearSelection.Click
    ClearSelection()
End Sub
```

### 5-2. 選択範囲の拡張

```vb
' 選択範囲を拡張
Private Sub ExtendSelection(toRow As Integer, toCol As Integer)
    With C1FlexGrid1
        Dim selection = .Selection
        
        ' 新しい選択範囲を作成
        Dim newSelection As New CellRange(
            Math.Min(selection.r1, toRow),
            Math.Min(selection.c1, toCol),
            Math.Max(selection.r2, toRow),
            Math.Max(selection.c2, toCol)
        )
        
        .Selection = newSelection
    End With
End Sub

' 使用例
Private Sub btnExtendSelection_Click(sender As Object, e As EventArgs) Handles btnExtendSelection.Click
    ExtendSelection(10, 5) ' 10行5列まで拡張
End Sub
```

### 5-3. 選択範囲の反転

```vb
' 選択状態を反転（ListBoxモード）
Private Sub InvertSelection()
    With C1FlexGrid1
        If .SelectionMode <> SelectionModeEnum.ListBox Then
            MessageBox.Show("ListBoxモードでのみ使用できます")
            Return
        End If
        
        For i = 1 To .Rows.Count - 1
            .Rows(i).Selected = Not .Rows(i).Selected
        Next
    End With
End Sub

' 使用例
Private Sub btnInvertSelection_Click(sender As Object, e As EventArgs) Handles btnInvertSelection.Click
    InvertSelection()
End Sub
```

## 6. 選択イベント

### 6-1. 選択変更イベント

```vb
' 選択が変更されたときのイベント
Private Sub C1FlexGrid1_AfterSelChange(sender As Object, e As RangeEventArgs) Handles C1FlexGrid1.AfterSelChange
    Dim selection = C1FlexGrid1.Selection
    
    Debug.WriteLine($"選択変更: R{selection.r1}C{selection.c1} - R{selection.r2}C{selection.c2}")
    
    ' 選択範囲の情報を表示
    lblSelectionInfo.Text = $"選択: {selection.Rows}行 x {selection.Cols}列"
End Sub
```

### 6-2. 行選択イベント

```vb
' 行がクリックされたときのイベント
Private Sub C1FlexGrid1_RowColChange(sender As Object, e As EventArgs) Handles C1FlexGrid1.RowColChange
    With C1FlexGrid1
        If .Row > 0 Then ' ヘッダー行を除外
            Debug.WriteLine($"現在の行: {.Row}")
            
            ' 選択行のデータを表示
            Dim rowData As New List(Of String)
            For col = 1 To .Cols.Count - 1
                rowData.Add(.GetData(.Row, col)?.ToString())
            Next
            
            lblRowData.Text = String.Join(" | ", rowData)
        End If
    End With
End Sub
```

### 6-3. セル選択前のイベント（キャンセル可能）

```vb
' 選択が変更される前のイベント（キャンセル可能）
Private Sub C1FlexGrid1_BeforeSelChange(sender As Object, e As RangeEventArgs) Handles C1FlexGrid1.BeforeSelChange
    ' 例: 特定の行は選択不可にする
    If e.NewRange.r1 = 5 Then
        MessageBox.Show("この行は選択できません")
        e.Cancel = True ' 選択をキャンセル
    End If
End Sub
```

## 7. 実用的なサンプル

### 7-1. 選択行のデータ取得と処理

```vb
' 選択された行のデータを取得してリストに表示
Public Class CustomerData
    Public Property CustomerId As Integer
    Public Property CustomerName As String
    Public Property Email As String
End Class

Private Sub btnGetSelectedCustomers_Click(sender As Object, e As EventArgs) Handles btnGetSelectedCustomers.Click
    Dim selectedCustomers = GetSelectedCustomersFromGrid()
    
    If selectedCustomers.Count = 0 Then
        MessageBox.Show("顧客を選択してください")
        Return
    End If
    
    ' 選択された顧客情報を表示
    Dim result As New System.Text.StringBuilder()
    result.AppendLine($"{selectedCustomers.Count}件の顧客が選択されています:")
    
    For Each customer In selectedCustomers
        result.AppendLine($"ID: {customer.CustomerId}, 名前: {customer.CustomerName}")
    Next
    
    MessageBox.Show(result.ToString())
End Sub

Private Function GetSelectedCustomersFromGrid() As List(Of CustomerData)
    Dim customers As New List(Of CustomerData)
    Dim selectedRows = GetSelectedRowIndices()
    
    For Each rowIndex In selectedRows
        With C1FlexGrid1
            Dim customer As New CustomerData With {
                .CustomerId = CInt(.GetData(rowIndex, 1)),
                .CustomerName = .GetData(rowIndex, 2)?.ToString(),
                .Email = .GetData(rowIndex, 3)?.ToString()
            }
            customers.Add(customer)
        End With
    Next
    
    Return customers
End Function
```

### 7-2. 選択行の一括更新

```vb
' 選択された行の特定列を一括更新
Private Sub btnBulkUpdateStatus_Click(sender As Object, e As EventArgs) Handles btnBulkUpdateStatus.Click
    Dim selectedRows = GetSelectedRowIndices()
    
    If selectedRows.Count = 0 Then
        MessageBox.Show("更新する行を選択してください")
        Return
    End If
    
    Dim result = MessageBox.Show(
        $"{selectedRows.Count}行のステータスを「処理済み」に更新しますか？",
        "確認",
        MessageBoxButtons.YesNo,
        MessageBoxIcon.Question
    )
    
    If result = DialogResult.Yes Then
        UpdateStatusForRows(selectedRows, "処理済み")
        MessageBox.Show("更新しました")
    End If
End Sub

Private Sub UpdateStatusForRows(rowIndices As List(Of Integer), status As String)
    With C1FlexGrid1
        For Each rowIndex In rowIndices
            .SetData(rowIndex, 5, status) ' 5列目（ステータス列）を更新
            
            ' 背景色を変更
            .SetCellStyle(rowIndex, 5, .Styles("Updated"))
        Next
    End With
End Sub
```

### 7-3. 選択範囲のコピー（クリップボード）

```vb
' 選択範囲をクリップボードにコピー
Private Sub btnCopyToClipboard_Click(sender As Object, e As EventArgs) Handles btnCopyToClipboard.Click
    CopySelectionToClipboard()
    MessageBox.Show("選択範囲をクリップボードにコピーしました")
End Sub

Private Sub CopySelectionToClipboard()
    Dim data = GetSelectedData()
    Dim result As New System.Text.StringBuilder()
    
    For Each rowData In data
        result.AppendLine(String.Join(vbTab, rowData))
    Next
    
    If result.Length > 0 Then
        Clipboard.SetText(result.ToString())
    End If
End Sub

' Ctrl+Cでコピー
Private Sub C1FlexGrid1_KeyDown(sender As Object, e As KeyEventArgs) Handles C1FlexGrid1.KeyDown
    If e.Control AndAlso e.KeyCode = Keys.C Then
        CopySelectionToClipboard()
        e.Handled = True
    End If
End Sub
```

### 7-4. 選択行の削除

```vb
' 選択された行を削除
Private Sub btnDeleteSelectedRows_Click(sender As Object, e As EventArgs) Handles btnDeleteSelectedRows.Click
    Dim selectedRows = GetSelectedRowIndices()
    
    If selectedRows.Count = 0 Then
        MessageBox.Show("削除する行を選択してください")
        Return
    End If
    
    Dim result = MessageBox.Show(
        $"{selectedRows.Count}行を削除しますか？",
        "確認",
        MessageBoxButtons.YesNo,
        MessageBoxIcon.Warning
    )
    
    If result = DialogResult.Yes Then
        DeleteRows(selectedRows)
        MessageBox.Show("削除しました")
    End If
End Sub

Private Sub DeleteRows(rowIndices As List(Of Integer))
    ' 後ろから削除（インデックスのズレを防ぐ）
    For i = rowIndices.Count - 1 To 0 Step -1
        C1FlexGrid1.Rows.Remove(rowIndices(i))
    Next
End Sub
```

### 7-5. 条件に合う行を自動選択

```vb
' 条件に合う行を自動選択
Private Sub btnSelectHighValueRows_Click(sender As Object, e As EventArgs) Handles btnSelectHighValueRows.Click
    Dim threshold As Decimal = 10000
    SelectRowsByCondition(Function(rowIndex) GetRowValue(rowIndex, 4) > threshold)
End Sub

Private Sub SelectRowsByCondition(condition As Func(Of Integer, Boolean))
    With C1FlexGrid1
        .SelectionMode = SelectionModeEnum.ListBox
        
        ' すべての選択をクリア
        For i = 1 To .Rows.Count - 1
            .Rows(i).Selected = False
        Next
        
        ' 条件に合う行を選択
        For i = 1 To .Rows.Count - 1
            If condition(i) Then
                .Rows(i).Selected = True
            End If
        Next
    End With
End Sub

Private Function GetRowValue(rowIndex As Integer, colIndex As Integer) As Decimal
    Dim value = C1FlexGrid1.GetData(rowIndex, colIndex)
    
    If value IsNot Nothing AndAlso IsNumeric(value) Then
        Return CDec(value)
    End If
    
    Return 0
End Function
```

### 7-6. 選択行のハイライト表示

```vb
' 選択された行をハイライト表示
Private Sub SetupRowHighlight()
    ' カスタムスタイルを作成
    Dim highlightStyle = C1FlexGrid1.Styles.Add("Highlight")
    highlightStyle.BackColor = Color.LightYellow
    highlightStyle.ForeColor = Color.Black
    
    AddHandler C1FlexGrid1.AfterSelChange, AddressOf HighlightSelectedRows
End Sub

Private Sub HighlightSelectedRows(sender As Object, e As RangeEventArgs)
    With C1FlexGrid1
        ' すべての行のスタイルをリセット
        For i = 1 To .Rows.Count - 1
            .Rows(i).Style = Nothing
        Next
        
        ' 選択行にハイライトスタイルを適用
        Dim selectedRows = GetSelectedRowIndices()
        For Each rowIndex In selectedRows
            .Rows(rowIndex).Style = .Styles("Highlight")
        Next
    End With
End Sub
```

### 7-7. 行番号列の追加と選択

```vb
' 行番号列を追加して、行番号クリックで行選択
Private Sub SetupRowNumberColumn()
    With C1FlexGrid1
        ' 固定列を追加（行番号用）
        .Cols.Fixed = 1
        .Cols(0).Width = 40
        .Cols(0).AllowEditing = False
        
        ' 行番号を設定
        For i = 1 To .Rows.Count - 1
            .SetData(i, 0, i)
        Next
        
        ' 列ヘッダー
        .SetData(0, 0, "#")
        
        ' 行番号列クリックで行全体を選択
        AddHandler .BeforeMouseDown, AddressOf RowNumberColumn_MouseDown
    End With
End Sub

Private Sub RowNumberColumn_MouseDown(sender As Object, e As BeforeMouseDownEventArgs)
    With C1FlexGrid1
        Dim hitTest = .HitTest(e.X, e.Y)
        
        ' 行番号列（固定列）がクリックされた場合
        If hitTest.Column = 0 AndAlso hitTest.Row > 0 Then
            SelectSingleRow(hitTest.Row)
            e.Cancel = True ' デフォルトの動作をキャンセル
        End If
    End With
End Sub
```

## 8. よくある問題と解決方法

### 問題1: 選択がうまくできない

**原因**: SelectionModeが適切でない

**解決方法**:
```vb
' 行を選択したい場合
C1FlexGrid1.SelectionMode = SelectionModeEnum.Row

' 複数行を選択したい場合
C1FlexGrid1.SelectionMode = SelectionModeEnum.ListBox
```

### 問題2: 選択範囲の取得で固定行・列が含まれる

**原因**: 固定行・列を考慮していない

**解決方法**:
```vb
Private Function GetDataRowIndices() As List(Of Integer)
    Dim rows As New List(Of Integer)
    Dim selection = C1FlexGrid1.Selection
    
    ' 固定行を除外（通常は0行目がヘッダー）
    For i = Math.Max(selection.r1, 1) To selection.r2
        rows.Add(i)
    Next
    
    Return rows
End Function
```
### 問題3: ListBoxモードで選択が解除されてしまう

**原因**: Ctrlキーを押さずにクリック

**解決方法**:
```vb
' AllowSelectionプロパティを設定
C1FlexGrid1.AllowSelection = True

' または、プログラムで選択を保持
Private Sub C1FlexGrid1_BeforeSelChange(sender As Object, e As RangeEventArgs) Handles C1FlexGrid1.BeforeSelChange
    ' Ctrlキーが押されていない場合、既存の選択を維持
    If Not Control.ModifierKeys.HasFlag(Keys.Control) Then
        ' カスタムロジック
    End If
End Sub
```

### 問題4: 選択行のデータが取得できない

**原因**: 行インデックスが0から始まっていない

**解決方法**:
```vb
' ✅ 正しい方法：1から始める（0はヘッダー）
For i = 1 To C1FlexGrid1.Rows.Count - 1
    If C1FlexGrid1.Rows(i).Selected Then
        ' データ取得
    End If
Next

' ❌ 間違い：0から始める
For i = 0 To C1FlexGrid1.Rows.Count - 1 ' ヘッダー行も含まれる
    If C1FlexGrid1.Rows(i).Selected Then
        ' データ取得
    End If
Next
```

## 9. パフォーマンス最適化

### 9-1. 大量データでの選択

```vb
' 大量データがある場合の最適化
Private Sub SelectRowsOptimized(rowIndices As List(Of Integer))
    With C1FlexGrid1
        ' 再描画を一時停止
        .BeginUpdate()
        
        Try
            .SelectionMode = SelectionModeEnum.ListBox
            
            ' すべてクリア
            For i = 1 To .Rows.Count - 1
                .Rows(i).Selected = False
            Next
            
            ' 選択
            For Each rowIndex In rowIndices
                .Rows(rowIndex).Selected = True
            Next
            
        Finally
            ' 再描画を再開
            .EndUpdate()
        End Try
    End With
End Sub
```

### 9-2. イベントの一時停止

```vb
' イベントを一時的に無効化
Private Sub BulkOperation()
    RemoveHandler C1FlexGrid1.AfterSelChange, AddressOf C1FlexGrid1_AfterSelChange
    
    Try
        ' 大量の選択操作
        For i = 1 To 1000
            C1FlexGrid1.Rows(i).Selected = True
        Next
        
    Finally
        AddHandler C1FlexGrid1.AfterSelChange, AddressOf C1FlexGrid1_AfterSelChange
    End Try
End Sub
```

## 10. まとめ

### 選択モードの使い分け

| 用途 | 推奨モード |
|------|-----------|
| 単一行の選択・編集 | `Row` |
| 複数行の一括処理 | `ListBox` または `RowRange` |
| セル単位の編集 | `Cell` |
| 範囲コピー・ペースト | `CellRange` |

### 重要なプロパティとメソッド

| 項目 | 説明 |
|------|------|
| `SelectionMode` | 選択モードの設定 |
| `Selection` | 現在の選択範囲を取得・設定 |
| `Select(r1, c1, r2, c2)` | 範囲を選択 |
| `Row`/`Col` | 現在の行・列 |
| `Rows(i).Selected` | 行の選択状態 |
| `BeginUpdate()`/`EndUpdate()` | 再描画の制御 |

### ベストプラクティス

1. **適切な選択モードを設定**: 用途に応じて`SelectionMode`を選択
2. **固定行・列を考慮**: データ行は通常1から始まる
3. **パフォーマンスを意識**: 大量データでは`BeginUpdate()`を使用
4. **イベントを活用**: `AfterSelChange`で選択変更を検知
5. **エラーハンドリング**: 範囲外のインデックスに注意

## おわりに

C1FlexGridの選択機能は非常に強力で、様々な要件に対応できます。

本記事で紹介した方法を組み合わせることで、ユーザーフレンドリーで高機能なグリッド操作を実装できます。

実際のプロジェクトでは、要件に応じて適切な選択モードとイベントハンドリングを選択してください。
