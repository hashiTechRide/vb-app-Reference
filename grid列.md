## まず1点だけ訂正

`My.Resources` は**実行時は読み取り専用**です（アセンブリに埋め込まれるリソース）。保存先は `My.Settings` にしてください。

- プロジェクトのプロパティ → 設定 → `GridLayout_OrderForm` / 型 `String` / **スコープ = ユーザー**
- 保存は `My.Settings.Save()`（`FormClosing` で明示的に呼ぶ）

## 組み込みの `SaveGrid`/`LoadGrid` を使わない理由

C1FlexGrid の XML 入出力は「グリッド全体のスナップショット」であって、**列名でのマッチングをしてくれません**。DataTable の構成が変わった時に、

- 消えた列の設定が残る／新しい列の扱いが不定
- バインド中に `LoadGrid` するとグリッド構造ごと差し替わり `DataSource` との整合が崩れる

という問題が出ます。保持したいのは `Visible` と並び順という**ごく小さい情報**なので、自前で `列名 → {Visible, Width, Order}` のリストを持つ方が、はるかに壊れにくく、リカバリーも設計できます。

## リカバリー戦略（多層防御）

これが本題ですね。5層に分けて考えるのが実務的です。

**第1層：キーをインデックスではなく列名にする**
`Cols(i).Name` はバインド時に `DataColumn.ColumnName` が入るので、これが唯一の安定キーです。インデックスで持つと列が1本増減した瞬間に全部ずれます。

**第2層：スキーマフィンガープリント**
列名集合をソートして SHA256 → 先頭16文字を一緒に保存。起動時のキーと一致すれば「構成無変更」が確定するので、無条件で適用できます。不一致なら第3層へ。

**第3層：一致率による採否判定**
現在の列のうち何割が保存側に存在するか。既定 50% 未満なら「別物の画面になった」と判断して設定ごと破棄します。50% 以上なら**マージ適用**：

- 保存側にあって現在に無い列 → スキップ（削除された列）
- 現在にあって保存側に無い列 → **表示のまま末尾に残る**（新規追加列を勝手に隠さない）

`ApplyCore` で「一旦全列 Visible = True にしてから保存順に前詰め」しているのは、この2つを自動的に成立させるためです。

**第4層：適用後の健全性チェック**
一番怖いのは**全列非表示**です。こうなるとユーザーが列ヘッダを右クリックすることすらできず、自力復帰不能になります。適用後に表示列ゼロなら既定レイアウトへ強制復帰。

**第5層：既定レイアウトの保持と手動リセット**
`DataSource` を設定した直後に `Capture()` して `_defaultLayout` として持っておく。これが全フォールバックの着地点であり、「列表示をリセット」メニューの実体にもなります。**自動リカバリーは万能ではないので、手動の逃げ道は必ず用意してください。**

## 呼び出し側

```vb
Private _defaultLayout As GridLayout

Private Sub Form_Load(sender As Object, e As EventArgs) Handles MyBase.Load
    _flex.AllowDragging = AllowDraggingEnum.Columns
    _flex.DataSource = _dt                       ' ← 先にバインド（列が生成される）
    _defaultLayout = FlexGridLayoutPersister.Capture(_flex)

    Dim saved = FlexGridLayoutPersister.Deserialize(My.Settings.GridLayout_OrderForm)
    Dim st = FlexGridLayoutPersister.Apply(_flex, saved, _defaultLayout)

    If st <> FlexGridLayoutPersister.RestoreStatus.Applied Then
        Logger.Info($"列レイアウト復元: {st}")   ' 静かに記録。ユーザーには出さない
    End If
End Sub

Private Sub Form_FormClosing(sender As Object, e As FormClosingEventArgs) Handles MyBase.FormClosing
    Try
        My.Settings.GridLayout_OrderForm =
            FlexGridLayoutPersister.Serialize(FlexGridLayoutPersister.Capture(_flex))
        My.Settings.Save()
    Catch ex As Exception
        Logger.Warn(ex)   ' 保存失敗でクローズをブロックさせない
    End Try
End Sub
```

## ハマりどころ

- **`Cols.Fixed` を必ず起点にする。** 行ヘッダ列（index 0）を巻き込んで `Move` すると表示が崩壊します。ループも判定も全部 `Cols.Fixed` 始まりで統一しています。
- **復元は `DataSource` 設定後。** 再バインドすると列が再生成されて設定が飛ぶので、バインドし直す箇所があるなら復元処理もセットで呼ぶヘルパーにまとめておくと安全です。
- **`user.config` 破損。** 稀に `My.Settings` の初回アクセスで `ConfigurationErrorsException` が出ます。`ApplicationEvents.vb` の `Startup` でダミー読み出しを `Try` で囲み、例外なら `ex.Filename` のファイルを削除 → `My.Settings.Reload()` で復旧させておくと、起動不能事故を防げます。
- **アセンブリバージョンを上げると設定が別フォルダになる**（＝リセットされたように見える）。`SettingsUpgradeRequired` という Boolean 設定を用意して、初回起動時に `My.Settings.Upgrade()` を呼ぶ定番パターンを入れておいてください。複数グリッドで使い回す場合は、`My.Settings` のキーを `"{FormName}.{GridName}"` にして `StringDictionary` 相当（XML1本にまとめる）で持つ拡張も入れやすい構造にしてあります。


```vb
Imports System.Collections.Generic
Imports System.IO
Imports System.Linq
Imports System.Security.Cryptography
Imports System.Text
Imports System.Xml.Serialization
Imports C1.Win.C1FlexGrid

''' <summary>1列分の保持情報。キーは必ず列名（＝DataColumn.ColumnName）。</summary>
Public Class ColumnLayoutItem
    <XmlAttribute("name")>
    Public Property Name As String = String.Empty

    <XmlAttribute("visible")>
    Public Property Visible As Boolean = True

    <XmlAttribute("width")>
    Public Property Width As Integer = -1

    <XmlAttribute("order")>
    Public Property Order As Integer
End Class

''' <summary>グリッド1つ分のレイアウト。My.Settings に文字列として格納する。</summary>
<XmlRoot("GridLayout")>
Public Class GridLayout

    Public Const CurrentVersion As Integer = 1

    <XmlAttribute("version")>
    Public Property Version As Integer = CurrentVersion

    ''' <summary>列名集合のフィンガープリント。完全一致なら無条件で信用してよい。</summary>
    <XmlAttribute("schemaKey")>
    Public Property SchemaKey As String = String.Empty

    <XmlArray("Columns")>
    <XmlArrayItem("Column")>
    Public Property Columns As New List(Of ColumnLayoutItem)()
End Class


Public NotInheritable Class FlexGridLayoutPersister

    Private Sub New()
    End Sub

    Public Enum RestoreStatus
        ''' <summary>スキーマ完全一致。そのまま適用。</summary>
        Applied
        ''' <summary>列の増減あり。マージして適用（新列は末尾・表示）。</summary>
        AppliedWithDiff
        ''' <summary>一致率が低すぎる。設定を破棄して既定レイアウトへ。</summary>
        RejectedSchemaMismatch
        ''' <summary>適用結果、表示列がゼロになった。既定レイアウトへ。</summary>
        RejectedAllHidden
        ''' <summary>設定なし／壊れている／例外。既定レイアウトへ。</summary>
        Failed
    End Enum

#Region "Capture"

    ''' <summary>現在のグリッドからレイアウトを取得する。DataSource 設定後に呼ぶこと。</summary>
    Public Shared Function Capture(grid As C1FlexGrid) As GridLayout
        Dim layout As New GridLayout() With {.SchemaKey = BuildSchemaKey(grid)}

        Dim order As Integer = 0
        For i As Integer = grid.Cols.Fixed To grid.Cols.Count - 1
            Dim c As Column = grid.Cols(i)
            If String.IsNullOrEmpty(c.Name) Then Continue For

            layout.Columns.Add(New ColumnLayoutItem With {
                .Name = c.Name,
                .Visible = c.Visible,
                .Width = c.Width,
                .Order = order
            })
            order += 1
        Next

        Return layout
    End Function

#End Region

#Region "Serialize / Deserialize"

    Public Shared Function Serialize(layout As GridLayout) As String
        If layout Is Nothing Then Return String.Empty
        Try
            Dim ser As New XmlSerializer(GetType(GridLayout))
            Using sw As New StringWriter()
                ser.Serialize(sw, layout)
                Return sw.ToString()
            End Using
        Catch
            Return String.Empty
        End Try
    End Function

    ''' <summary>復元不能なら Nothing を返す（例外は投げない）。</summary>
    Public Shared Function Deserialize(xml As String) As GridLayout
        If String.IsNullOrWhiteSpace(xml) Then Return Nothing
        Try
            Dim ser As New XmlSerializer(GetType(GridLayout))
            Using sr As New StringReader(xml)
                Dim layout = TryCast(ser.Deserialize(sr), GridLayout)
                If layout Is Nothing Then Return Nothing
                If layout.Version <> GridLayout.CurrentVersion Then Return Nothing
                If layout.Columns Is Nothing OrElse layout.Columns.Count = 0 Then Return Nothing
                Return layout
            End Using
        Catch
            ' 壊れた XML / 型不整合 / 旧バージョン → 既定へフォールバックさせる
            Return Nothing
        End Try
    End Function

#End Region

#Region "Apply"

    ''' <summary>
    ''' 保存レイアウトを適用する。失敗・不整合時は fallback（起動直後に Capture した既定）へ戻す。
    ''' </summary>
    ''' <param name="minMatchRate">現在の列のうち、保存側に存在した割合の下限。下回ると設定を破棄。</param>
    Public Shared Function Apply(grid As C1FlexGrid,
                                 layout As GridLayout,
                                 fallback As GridLayout,
                                 Optional minMatchRate As Double = 0.5) As RestoreStatus

        If layout Is Nothing OrElse layout.Columns.Count = 0 Then
            ApplyCore(grid, fallback)
            Return RestoreStatus.Failed
        End If

        Dim currentKey = BuildSchemaKey(grid)
        Dim exactMatch = String.Equals(currentKey, layout.SchemaKey, StringComparison.Ordinal)

        If Not exactMatch Then
            ' スキーマが変わっている → 一致率で採否を判断
            Dim gridNames = GetColumnNames(grid)
            Dim matched = layout.Columns.Count(Function(x) gridNames.Contains(x.Name))
            Dim rate = If(gridNames.Count = 0, 0.0R, matched / CDbl(gridNames.Count))

            If rate < minMatchRate Then
                ApplyCore(grid, fallback)
                Return RestoreStatus.RejectedSchemaMismatch
            End If
        End If

        Try
            ApplyCore(grid, layout)
        Catch
            ApplyCore(grid, fallback)
            Return RestoreStatus.Failed
        End Try

        ' 最後の砦：全列非表示だと利用者が自力で戻せない
        If Not HasVisibleColumn(grid) Then
            ApplyCore(grid, fallback)
            Return RestoreStatus.RejectedAllHidden
        End If

        Return If(exactMatch, RestoreStatus.Applied, RestoreStatus.AppliedWithDiff)
    End Function

    ''' <summary>既定レイアウトへ戻す（「列表示をリセット」メニュー用）。</summary>
    Public Shared Sub Reset(grid As C1FlexGrid, defaultLayout As GridLayout)
        ApplyCore(grid, defaultLayout)
    End Sub

    Private Shared Sub ApplyCore(grid As C1FlexGrid, layout As GridLayout)
        If grid Is Nothing OrElse layout Is Nothing Then Return

        grid.Redraw = False
        Try
            ' 1) ベースラインへ戻す。保存側に無い列（＝新規追加列）は必ず表示のままにする。
            For i As Integer = grid.Cols.Fixed To grid.Cols.Count - 1
                grid.Cols(i).Visible = True
            Next

            ' 2) 保存順に先頭から詰めていく。見つからない列は自然にスキップされ、
            '    保存側に無い列は結果として末尾に残る。
            Dim target As Integer = grid.Cols.Fixed
            For Each item In layout.Columns.OrderBy(Function(x) x.Order)
                If String.IsNullOrEmpty(item.Name) Then Continue For

                Dim idx As Integer = IndexOfName(grid, item.Name)
                If idx < grid.Cols.Fixed Then Continue For   ' 削除された列

                If idx <> target Then
                    grid.Cols.Move(idx, target)
                End If

                Dim c As Column = grid.Cols(target)
                c.Visible = item.Visible
                If item.Width > 0 Then c.Width = item.Width

                target += 1
            Next
        Finally
            grid.Redraw = True
        End Try
    End Sub

#End Region

#Region "Helpers"

    Private Shared Function IndexOfName(grid As C1FlexGrid, name As String) As Integer
        For i As Integer = grid.Cols.Fixed To grid.Cols.Count - 1
            If String.Equals(grid.Cols(i).Name, name, StringComparison.Ordinal) Then Return i
        Next
        Return -1
    End Function

    Private Shared Function GetColumnNames(grid As C1FlexGrid) As HashSet(Of String)
        Dim names As New HashSet(Of String)(StringComparer.Ordinal)
        For i As Integer = grid.Cols.Fixed To grid.Cols.Count - 1
            Dim n = grid.Cols(i).Name
            If Not String.IsNullOrEmpty(n) Then names.Add(n)
        Next
        Return names
    End Function

    Private Shared Function HasVisibleColumn(grid As C1FlexGrid) As Boolean
        For i As Integer = grid.Cols.Fixed To grid.Cols.Count - 1
            If grid.Cols(i).Visible Then Return True
        Next
        Return False
    End Function

    ''' <summary>列名集合（順不同）のハッシュ。並び替えや表示/非表示では変化しない。</summary>
    Private Shared Function BuildSchemaKey(grid As C1FlexGrid) As String
        Dim joined = String.Join("|", GetColumnNames(grid).OrderBy(Function(n) n, StringComparer.Ordinal))
        Using sha = SHA256.Create()
            Dim bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(joined))
            Return BitConverter.ToString(bytes).Replace("-", "").Substring(0, 16)
        End Using
    End Function

#End Region

End Class
```
