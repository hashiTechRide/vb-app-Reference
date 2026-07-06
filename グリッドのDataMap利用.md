DataMap方式・選択分を随時追記する方針で、これまでの内容を統合してまとめます。ポイントは「表示はDataMapに任せ、DataMapに無いコードは選択時と初期読込時に追記して埋める」ことです。

## 全体像

```
セルの値      = 取引先コード（DataTableに入る・DBに保存される）
セルの表示    = 取引先名（DataMapがコード→名称に変換して見せる）
選択方法      = セルボタン("...") → 選択フォーム → コードを書き戻す
DataMapの中身 = 必要になったコードを随時追記して育てる
```

DataMapは最初から全件を持たず、「初期読込で出てきたコード」と「選択で選んだコード」を都度足していきます。

## 1. 列の設定

セルボタンで選択、DataMapで表示変換。両方を列に設定します。

```vb
' 取引先コード列の設定
grid.Cols("CLIENT_CODE").ComboList = "..."          ' セルボタン（直接編集不可）
grid.Cols("CLIENT_CODE").DataMap = _clientMap       ' コード→名称の表示変換
```

`_clientMap`は最初は空、または初期読込分だけ入った辞書です。

```vb
Private ReadOnly _clientMap As New Dictionary(Of String, String)
```

## 2. DataMapへの追記を1メソッドにまとめる

追記が「選択時」「初期読込時」の2箇所で必要になるので、共通メソッドにします。既にあるコードは二重登録しない。追記したら再描画で表示を更新します。

```vb
' コードと名称をDataMapに追記（無ければ足す）
Private Sub EnsureClientDisplay(code As String, name As String)
    If String.IsNullOrEmpty(code) Then Return
    If Not _clientMap.ContainsKey(code) Then
        _clientMap(code) = name
        grid.Cols("CLIENT_CODE").DataMap = _clientMap   ' 参照を差し直して反映
        grid.Invalidate()                               ' 表示を更新
    End If
End Sub
```

C1FlexGridは、DataMapの中身を変えただけだと表示に反映されないことがあるため、DataMapプロパティに辞書を再代入して認識させ、`Invalidate`で塗り直します。

## 3. セルボタンで選択 → コード書き戻し＋追記

ボタンクリックで選択フォームを開き、選んだ取引先のコードをセルに書き戻し、同時にコードと名称をDataMapへ追記します。

```vb
Private Sub grid_CellButtonClick(sender As Object, e As RowColEventArgs) Handles grid.CellButtonClick
    If grid.Cols(e.Col).Name <> "CLIENT_CODE" Then Return

    Dim currentCode = Convert.ToString(grid(e.Row, e.Col))
    Using dlg As New ClientSelectForm(currentCode)
        If dlg.ShowDialog() = DialogResult.OK Then
            ' 表示用にDataMapへ追記（選択したものは必ず名称が引ける状態にする）
            EnsureClientDisplay(dlg.SelectedCode, dlg.SelectedName)

            ' セルにはコードを書き戻す（表示はDataMapが名称に変換）
            Dim drv = DirectCast(grid.Rows(e.Row).DataSource, DataRowView)
            drv("CLIENT_CODE") = dlg.SelectedCode
        End If
    End Using
End Sub
```

セルに入れるのは**コード**。名称はDataMapが表示に使うだけで、DataTableには入りません。だから保存時はコードがそのままDBに行きます。

## 4. 初期読込時にも追記する（重要）

DBからデータを読み込んだ直後、各行の取引先コードに対応する名称がDataMapに無いと、画面がコードのまま表示されます。**読み込んだデータに含まれるコードの名称を、まとめてDataMapに入れる**必要があります。

やり方は、読み込んだコードの一覧でマスタを引き、名称を追記する。

```vb
Public Sub Load(parentSeq As Long)
    _table = _repository.GetByParent(parentSeq)
    grid.DataSource = _table

    ' 読み込んだ行の取引先コードに対応する名称をDataMapへ流し込む
    Dim codes = _table.AsEnumerable().
        Select(Function(r) r.Field(Of String)("CLIENT_CODE")).
        Where(Function(c) Not String.IsNullOrEmpty(c)).
        Distinct().ToList()

    ' マスタから名称をまとめて取得（IN句などで一括、都度引かない）
    Dim names = _clientRepository.GetNames(codes)   ' code→name の辞書を返す
    For Each kv In names
        EnsureClientDisplay(kv.Key, kv.Value)
    Next
End Sub
```

ここで**コードごとに1件ずつマスタを引くとN回クエリが飛ぶ**ので、読み込んだコードをまとめて渡して一括取得します（`GetNames(codes)`）。取引先は件数が多い前提なので、この一括化は性能上重要です。

## 5. マスタ取得の窓口

DataMapを埋めるための名称取得を、取引先用のRepositoryに持たせます。単体取得と一括取得の両方を用意すると使い分けられます。

```vb
Public Interface IClientRepository
    ' 選択フォーム用：全件 or 検索
    Function Search(keyword As String) As IList(Of ClientItem)
    ' DataMap補完用：コード群→名称群を一括取得
    Function GetNames(codes As IEnumerable(Of String)) As IDictionary(Of String, String)
End Interface
```

`GetNames`はIN句でまとめて引く。コード数が非常に多い場合はチャンク分割（Oracleは IN の要素数上限があるため1000件ごとなど）します。

## 6. ColumnDefinitionへの組み込み

前回の`LookupColumn`に、DataMap追記の仕組みを結び付けます。列定義に「表示用DataMap」と「選択フォームを開く関数」を持たせ、追記もここ起点にします。

```vb
Public Class LookupColumn
    Inherits ColumnDefinition

    Public Property Map As IDictionary                    ' コード→名称（随時追記）
    Public Property PickValue As Func(Of Object, LookupResult)  ' 選択フォームを開く

    Public Overrides Sub ApplyToColumn(grid As C1FlexGrid, col As Column)
        col.ComboList = "..."          ' セルボタン
        col.DataMap = Map              ' 表示変換
    End Sub
End Class

Public Class LookupResult
    Public Property Selected As Boolean
    Public Property Code As Object
    Public Property DisplayName As String
End Class
```

グリッド共通のボタンハンドラは、対象列の定義を引いて追記＋書き戻しします。

```vb
Private Sub grid_CellButtonClick(sender As Object, e As RowColEventArgs) Handles grid.CellButtonClick
    Dim def = TryCast(_defs(grid.Cols(e.Col).Name), LookupColumn)
    If def Is Nothing Then Return

    Dim r = def.PickValue(grid(e.Row, e.Col))
    If Not r.Selected Then Return

    ' DataMapに追記（無ければ）
    Dim code = Convert.ToString(r.Code)
    If Not def.Map.Contains(code) Then
        def.Map(code) = r.DisplayName
        grid.Cols(e.Col).DataMap = def.Map    ' 再認識
        grid.Invalidate()
    End If

    ' コード書き戻し
    Dim drv = DirectCast(grid.Rows(e.Row).DataSource, DataRowView)
    drv(grid.Cols(e.Col).Name) = r.Code
End Sub
```

## 7. Format問題との関係（前回の続き）

前に「DataMap列でFormatを呼ぶと内部値が表示される」問題がありました。この方針では、**取引先列（DataMap列）はFormat対象にしない**を徹底します。表示変換はDataMapに一任し、`AfterEdit`等で自作Formatを呼ばない。`LookupColumn`は`UsesValueFormatting = False`（既定）のままにします。

```vb
' DataMap列はFormat整形しない（既定Falseのまま）
' AfterEditのFormat適用対象から外れる → 名称が正しく表示される
```

## 8. 注意点まとめ

**表示が反映されないとき** … DataMapの中身を書き換えても、C1FlexGridが古い状態をキャッシュしていることがある。DataMapプロパティに辞書を再代入し、`Invalidate`で再描画する。

**名称の鮮度** … DataMapに一度入れた名称は、マスタ側で名称が変わっても自動更新されない。名称変更を追従したいなら、画面を開くたびに（Load時に）該当コードの名称を引き直してDataMapを上書きする。

**書き戻すのは常にコード** … 選択フォームからも、初期読込からも、セルに入れるのはコード。DataMapは表示にしか使わない。名称をセルに入れると壊れる。

**一括取得を守る** … 初期読込のDataMap補完は、コードを集めて`GetNames`で一括。1件ずつ引かない。

## まとめ

- DataMap方式で、**セルの値＝取引先コード（DataTable・DBに保存）／表示＝取引先名（DataMapが変換）**にする。列は`ComboList = "..."`（セルボタン）＋`DataMap`。
- DataMapは全件を持たず**随時追記**。追記は`EnsureClientDisplay`のような1メソッドに集約し、辞書再代入＋`Invalidate`で反映。
- **選択時**（ボタン→フォーム）にコードを書き戻し、同時にコードと名称をDataMapへ追記。**初期読込時**にも読み込んだコードの名称を一括取得してDataMapへ流し込む(これを忘れると既存データがコード表示になる)。
- 名称の一括取得は`IClientRepository.GetNames(codes)`でIN句一括。1件ずつ引かない。多数なら1000件等でチャンク分割。
- `LookupColumn`にDataMapと選択関数を持たせ、ボタンハンドラで追記＋コード書き戻しを共通化。
- DataMap列は**Format対象にしない**（前回のFormat競合を避ける）。書き戻すのは常にコードで、名称をセルに入れない。
- 名称の鮮度が要るならLoadのたびに名称を引き直してDataMapを上書きする。

この方針の肝は、DataMapを「最初に全部埋める」のではなく「必要になったら足す」で運用しつつ、**初期読込時の一括補完だけは必ずやる**ことです。ここが抜けると既存データの表示がコードのままになるので、選択時の追記とセットで、Load時の補完を忘れないようにしてください。
