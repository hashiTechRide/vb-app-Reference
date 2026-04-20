# C1FlexGrid 日付セル実装ガイド (VB.NET)

ComponentOne C1FlexGrid (WinForms 2022) で、文字列入力可能な日付セルにMonthCalendarのドロップダウンを追加し、コピペにも対応する実装。

## 仕様概要

- 日付列は **文字列型** として保持(自動変換させない)
- セルのドロップダウンボタン押下で **MonthCalendar** をポップアップ表示(画面外でも切れない)
- 手動入力時は **複数フォーマット** を許容して検証
- コピペ時は **不正値をスキップ** して、ペースト完了後に **集約通知**
- 編集確定後は表示を `yyyy/MM/dd` に **正規化**

## 技術的ポイント

### MonthCalendarのポップアップ表示

`ToolStripDropDown` + `ToolStripControlHost` を使用する。これによりフォームの境界を超えても切れずに表示でき、外側クリック・ESC・フォーカス喪失での自動クローズも標準で得られる。

### ValidateEditイベントの注意点

`ValidateEdit` は手動編集確定時とペースト時の両方で発火するが、**ペースト時は `flexGrid.Editor` が `Nothing`** になる。値の取得元を分岐する必要がある。

| 発火タイミング | `flexGrid.Editor` | 値の取得元 |
|---|---|---|
| 手動編集確定時 | エディタコントロール | `flexGrid.Editor.Text` |
| ペースト時(セルごと) | `Nothing` | `flexGrid(e.Row, e.Col)` |

### ペーストエラーの集約通知

`BeforePaste` でエラーリストを初期化し、`ValidateEdit` 内でペースト時のエラーをリストに溜め、`AfterPaste` でまとめてメッセージ表示する。これにより複数行ペーストでメッセージボックスが連発される問題を回避する。

## 完成コード

```vbnet
Imports C1.Win.C1FlexGrid
Imports System.Globalization

Public Class Form1

    Private _dropDown As ToolStripDropDown
    Private _monthCalendar As MonthCalendar
    Private _editingRow As Integer = -1
    Private _editingCol As Integer = -1
    Private Const DateCol As Integer = 1

    ' ペーストエラー集約用
    Private ReadOnly _pasteErrors As New List(Of String)
    Private _isPasting As Boolean = False

    ' 許容する日付フォーマット(必要に応じて増やす)
    Private ReadOnly _dateFormats As String() = {
        "yyyy/MM/dd",
        "yyyy/M/d",
        "yyyy-MM-dd",
        "yyyyMMdd",
        "yyyy.MM.dd"
    }

    Private Sub Form1_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        InitFlexGrid()
        InitCalendarPopup()
    End Sub

#Region "初期化"

    Private Sub InitFlexGrid()
        ' 日付列を文字列として設定
        flexGrid.Cols(DateCol).DataType = GetType(String)
        flexGrid.Cols(DateCol).Format = ""

        ' ドロップダウンボタンのみ表示(ComboListを "..." にする)
        flexGrid.Cols(DateCol).ComboList = "..."

        ' イベント登録
        AddHandler flexGrid.CellButtonClick, AddressOf FlexGrid_CellButtonClick
        AddHandler flexGrid.ValidateEdit, AddressOf FlexGrid_ValidateEdit
        AddHandler flexGrid.AfterEdit, AddressOf FlexGrid_AfterEdit
        AddHandler flexGrid.BeforePaste, AddressOf FlexGrid_BeforePaste
        AddHandler flexGrid.AfterPaste, AddressOf FlexGrid_AfterPaste
    End Sub

    Private Sub InitCalendarPopup()
        _monthCalendar = New MonthCalendar With {
            .MaxSelectionCount = 1
        }
        AddHandler _monthCalendar.DateSelected, AddressOf MonthCalendar_DateSelected

        Dim host As New ToolStripControlHost(_monthCalendar) With {
            .Margin = Padding.Empty,
            .Padding = Padding.Empty,
            .AutoSize = False,
            .Size = _monthCalendar.Size
        }

        _dropDown = New ToolStripDropDown With {
            .Padding = Padding.Empty,
            .AutoSize = True
        }
        _dropDown.Items.Add(host)
    End Sub

#End Region

#Region "MonthCalendarポップアップ"

    ''' <summary>
    ''' ドロップダウンボタンクリック時にMonthCalendarをポップアップ表示
    ''' </summary>
    Private Sub FlexGrid_CellButtonClick(sender As Object, e As RowColEventArgs)
        If e.Col <> DateCol Then Return

        _editingRow = e.Row
        _editingCol = e.Col

        ' セルのスクリーン座標を取得
        Dim rect = flexGrid.GetCellRect(e.Row, e.Col, False)
        Dim screenPoint = flexGrid.PointToScreen(New Point(rect.Left, rect.Bottom))

        ' 現在の値を初期選択
        Dim cellValue = Convert.ToString(flexGrid(e.Row, e.Col))
        Dim dt As DateTime
        If TryParseDate(cellValue, dt) Then
            _monthCalendar.SelectionStart = dt
        Else
            _monthCalendar.SelectionStart = DateTime.Today
        End If

        _dropDown.Show(screenPoint)
    End Sub

    Private Sub MonthCalendar_DateSelected(sender As Object, e As DateRangeEventArgs)
        If _editingRow >= 0 AndAlso _editingCol >= 0 Then
            flexGrid(_editingRow, _editingCol) = e.Start.ToString("yyyy/MM/dd")
        End If
        _dropDown.Close()
    End Sub

#End Region

#Region "編集検証"

    ''' <summary>
    ''' セル編集確定前の検証(手動編集・ペーストの両方で発火)
    ''' </summary>
    Private Sub FlexGrid_ValidateEdit(sender As Object, e As ValidateEditEventArgs)
        If e.Col <> DateCol Then Return

        ' 値の取得元を分岐
        ' 手動編集時: Editorコントロールから現在の編集テキストを取得
        ' ペースト時: Editorはnothing、既にセルにペースト値がセットされている
        Dim isManualEdit = flexGrid.Editor IsNot Nothing
        Dim input As String

        If isManualEdit Then
            input = Convert.ToString(flexGrid.Editor.Text)
        Else
            input = Convert.ToString(flexGrid(e.Row, e.Col))
        End If

        ' 空文字は許容(必要に応じて変更)
        If String.IsNullOrWhiteSpace(input) Then Return

        Dim dt As DateTime
        If TryParseDate(input, dt) Then Return

        ' --- 不正値の処理 ---
        e.Cancel = True ' このセルへの入力をキャンセル

        If isManualEdit Then
            ' 手動編集時は即座にメッセージ表示(編集モードが継続される)
            MessageBox.Show(
                $"日付の形式が正しくありません。{Environment.NewLine}" &
                $"例: 2026/04/17, 20260417",
                "入力エラー",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning)
        ElseIf _isPasting Then
            ' ペースト時はリストに溜めて、後でまとめて通知
            _pasteErrors.Add($"  行{e.Row + 1} 列{e.Col + 1}: ""{input}""")
        End If
    End Sub

    ''' <summary>
    ''' 編集確定後に表示フォーマットを正規化
    ''' </summary>
    Private Sub FlexGrid_AfterEdit(sender As Object, e As RowColEventArgs)
        If e.Col <> DateCol Then Return

        Dim input = Convert.ToString(flexGrid(e.Row, e.Col))
        If String.IsNullOrWhiteSpace(input) Then Return

        Dim dt As DateTime
        If TryParseDate(input, dt) Then
            ' 表示を統一フォーマットに正規化
            flexGrid(e.Row, e.Col) = dt.ToString("yyyy/MM/dd")
        End If
    End Sub

#End Region

#Region "ペースト処理"

    ''' <summary>
    ''' ペースト開始時にエラーリストを初期化
    ''' </summary>
    Private Sub FlexGrid_BeforePaste(sender As Object, e As ClipboardEventArgs)
        _isPasting = True
        _pasteErrors.Clear()
    End Sub

    ''' <summary>
    ''' ペースト完了時にエラーをまとめて通知
    ''' </summary>
    Private Sub FlexGrid_AfterPaste(sender As Object, e As ClipboardEventArgs)
        _isPasting = False

        If _pasteErrors.Count = 0 Then Return

        ' エラー件数が多い場合は先頭N件のみ表示
        Const maxDisplay As Integer = 20
        Dim displayList = _pasteErrors.Take(maxDisplay).ToList()
        Dim message = $"以下のセルで不正な日付がスキップされました ({_pasteErrors.Count}件):" &
                      Environment.NewLine &
                      String.Join(Environment.NewLine, displayList)

        If _pasteErrors.Count > maxDisplay Then
            message &= Environment.NewLine & $"  ...他 {_pasteErrors.Count - maxDisplay}件"
        End If

        MessageBox.Show(
            message,
            "ペースト時の警告",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning)
    End Sub

#End Region

#Region "日付パース"

    ''' <summary>
    ''' 複数フォーマットを許容する日付パース
    ''' </summary>
    Private Function TryParseDate(input As String, ByRef result As DateTime) As Boolean
        If String.IsNullOrWhiteSpace(input) Then
            result = DateTime.MinValue
            Return False
        End If

        ' 指定フォーマットで厳密にパース
        If DateTime.TryParseExact(
            input.Trim(),
            _dateFormats,
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            result) Then
            Return True
        End If

        ' フォールバック: 現在カルチャで緩くパース
        If DateTime.TryParse(input.Trim(), result) Then
            Return True
        End If

        Return False
    End Function

#End Region

End Class
```

## 動作仕様まとめ

### 手動入力時

| 入力 | 動作 |
|---|---|
| `2026/04/17` 等の有効な日付 | 確定後に `yyyy/MM/dd` へ正規化 |
| 空文字 | 許容(セルクリア) |
| 不正な形式・存在しない日付 | メッセージ表示 → 編集モード継続 |

### ドロップダウンボタン押下時

| 状況 | 動作 |
|---|---|
| セルが空 | 今日の日付を初期選択 |
| セルに有効な日付 | その日付を初期選択 |
| セルに不正な値 | 今日の日付を初期選択 |
| 日付選択後 | `yyyy/MM/dd` 形式でセルに反映 |

### ペースト時 (Ctrl+V)

| 値 | 動作 |
|---|---|
| 有効な日付 | セルに書き込み + 正規化 |
| 不正な値 | そのセルだけスキップ、エラーリストに追加 |
| ペースト完了後 | 不正値があった場合、まとめて警告ダイアログ表示 |

## カスタマイズポイント

### 許容フォーマットの追加

`_dateFormats` 配列に追記する。和暦対応が必要な場合は `"ggyy/MM/dd"` 等を追加し、`CultureInfo.InvariantCulture` を `New CultureInfo("ja-JP")` に変更する。

### 空文字の扱い

業務要件によっては空文字を不可とする場合もある。`ValidateEdit` 内の以下の行を変更する。

```vbnet
' 空文字を許容する場合
If String.IsNullOrWhiteSpace(input) Then Return

' 空文字を不可とする場合
If String.IsNullOrWhiteSpace(input) Then
    e.Cancel = True
    If isManualEdit Then
        MessageBox.Show("日付は必須です。", "入力エラー")
    ElseIf _isPasting Then
        _pasteErrors.Add($"  行{e.Row + 1} 列{e.Col + 1}: 空文字")
    End If
    Return
End If
```

### 出力フォーマットの変更

`yyyy/MM/dd` 以外を使いたい場合は、以下の **3箇所** を統一して変更する。

1. `MonthCalendar_DateSelected` の `e.Start.ToString("yyyy/MM/dd")`
2. `FlexGrid_AfterEdit` の `dt.ToString("yyyy/MM/dd")`
3. `_dateFormats` 配列の先頭(出力フォーマットを最優先で許容するため)

### 複数日付列の対応

`DateCol` 定数を配列やリストに変更し、各イベント内の `If e.Col <> DateCol Then Return` を `If Not _dateCols.Contains(e.Col) Then Return` に置き換える。
