# C1FlexGrid ペースト時のセルスタイル伝播問題まとめ

## 環境
- .NET Framework 4.8 / WinForms
- C1FlexGrid（DataTable 連結）
- 特定列の値に応じて編集可否を判定し、編集不可セルをグレーアウト

## 症状
- セルの値をコピー＆ペーストすると、その列の先頭行のセルスタイルが列の全行に反映されてしまう。
- 単一行ペーストでは対処が効いたが、複数行ペーストで再発した。

## 原因
1. **共有スタイルインスタンスの参照**
   `Styles.Add("名前")` で生成した名前付きスタイルを全セルで使い回しているため、複数セルが同一インスタンスを参照している。
2. **ペースト後の再描画タイミングのズレ**
   自作ペーストロジックで複数行を DataTable に書き込むと、`ListChanged` / `RowChanged` が発火し、C1FlexGrid が後から行を再描画する。KeyDown 内で同期的に `ApplyGrayoutStyles` を呼んでも、その後に再描画が走りスタイルが巻き戻る。
   - 単一行：変更・再描画範囲が狭く露見しにくい。
   - 複数行：再描画範囲が広く、スタイル伝播が顕在化する。

## 前提（正しい実装）
- `ApplyGrayoutStyles` は各セルに `SetCellStyle(r, c, grayStyle)` で共有スタイルを**適用し直す**実装（スタイルオブジェクトのプロパティ自体は書き換えていない）。
  → 実装自体は正しく、残る問題は**タイミングのみ**。

## 対処

### 1. 描画停止 + 後回し実行（基本対応）
- 書き込み中の段階的再描画を `Redraw = False/True` で抑制。
- `ApplyGrayoutStyles` を `BeginInvoke` でメッセージキューの後ろに回し、DataTable のイベント連鎖と再描画が完了してから実行。

```vb
Private Sub _flex_KeyDown(sender As Object, e As KeyEventArgs) Handles _flex.KeyDown
    If e.Control AndAlso e.KeyCode = Keys.V Then
        DoCustomPaste()
        e.Handled = True
        _flex.BeginInvoke(New MethodInvoker(AddressOf ApplyGrayoutStyles))
    End If
End Sub

Private Sub DoCustomPaste()
    _flex.Redraw = False
    Try
        ' DataTable へ複数行の値を一括書き込み
    Finally
        _flex.Redraw = True
    End Try
End Sub
```

### 2. イベント一時解除（上記でも崩れる場合）
DataTable の `RowChanged` / `ListChanged` が `BeginInvoke` よりさらに遅延発火するケースでは、書き込み中だけイベントを止める。

```vb
Private Sub DoCustomPaste()
    _flex.Redraw = False
    RemoveHandler _dt.RowChanged, AddressOf Dt_RowChanged
    Try
        ' 一括書き込み
    Finally
        AddHandler _dt.RowChanged, AddressOf Dt_RowChanged
        _flex.Redraw = True
    End Try
End Sub
```

### 3. （任意）ペースト自体をブロック
編集不可セルへの貼り付けは本来不整合。`BeforePaste`（バージョンにより `ClipboardPasting`）で範囲内に編集不可セルが含まれる場合にキャンセルする方法も有効。

```vb
Private Sub _flex_BeforePaste(sender As Object, e As BeforePasteEventArgs) Handles _flex.BeforePaste
    For r As Integer = _flex.Selection.TopRow To _flex.Selection.BottomRow
        If Not IsEditable(r) Then
            e.Cancel = True
            Exit For
        End If
    Next
End Sub
```

## 対応順序
1. まず **対処1（Redraw 制御 + BeginInvoke）** を試す。→ 通常はこれで解決。
2. まだ崩れる場合のみ **対処2（イベント一時解除）** を追加。
3. 仕様上、編集不可セルへのペーストを禁止したい場合は **対処3** を併用。
