' =====================================================================
'  FlexGridRebindScope.vb   (VB.NET / .NET Framework 4.8)
'
'  DataSource の差し替え（再検索）をまたいで、
'  列レイアウトと選択行を維持するためのスコープ。
'
'  【方針】
'   ・列の並び順 / 表示・非表示 / 列幅 … 維持（ユーザーが決めた見せ方）
'   ・スクロール位置                  … リセット（別データなので無意味）
'   ・選択行                          … キー一致時のみ復元。
'                                       インデックスでの復元は絶対にしない
'
'  ※ そもそも同じ DataTable インスタンスを Clear + Fill で詰め替えられるなら、
'    列は再生成されないのでこのクラスは不要。
'    列構成が変わりうる場合だけ使うこと。
' =====================================================================
Option Strict On
Option Explicit On

Imports System.Windows.Forms
Imports C1.Win.C1FlexGrid

Public NotInheritable Class FlexGridRebindScope
    Implements IDisposable

    Private ReadOnly _grid As C1FlexGrid
    Private ReadOnly _keyColumnName As String
    Private ReadOnly _savedLayout As GridLayout
    Private ReadOnly _savedKey As Object
    Private _disposed As Boolean

    ''' <summary>
    ''' 再バインドを囲む。
    ''' </summary>
    ''' <param name="keyColumnName">
    '''   選択行を復元するためのキー列名（主キー相当）。
    '''   Nothing なら選択は先頭行にリセットされる。
    ''' </param>
    ''' <example>
    ''' Using FlexGridRebindScope.Begin(_flex, "受注番号")
    '''     _flex.DataSource = LoadData(condition)
    ''' End Using
    ''' </example>
    Public Shared Function Begin(grid As C1FlexGrid,
                                 Optional keyColumnName As String = Nothing) As FlexGridRebindScope
        Return New FlexGridRebindScope(grid, keyColumnName)
    End Function

    Private Sub New(grid As C1FlexGrid, keyColumnName As String)
        If grid Is Nothing Then Throw New ArgumentNullException(NameOf(grid))

        _grid = grid
        _keyColumnName = keyColumnName

        ' 現在の見た目を退避
        _savedLayout = FlexGridLayoutPersister.Capture(_grid)

        ' 選択行のキー値を退避（インデックスではなく値で覚える）
        _savedKey = GetCurrentKey()

        _grid.Redraw = False
    End Sub

    Public Sub Dispose() Implements IDisposable.Dispose
        If _disposed Then Return
        _disposed = True

        Try
            ' 新しい列構成での既定レイアウトを取得しておく。
            ' 列構成が大きく変わっていた場合のフォールバック先になる。
            Dim newDefault = FlexGridLayoutPersister.Capture(_grid)

            ' 退避したレイアウトを適用。
            ' 列が増減していても Apply 側の一致率判定が吸収する。
            FlexGridLayoutPersister.Apply(_grid, _savedLayout, newDefault)

            RestoreSelection()

        Finally
            _grid.Redraw = True
        End Try
    End Sub

#Region "選択行"

    Private Function GetCurrentKey() As Object
        If String.IsNullOrEmpty(_keyColumnName) Then Return Nothing

        Dim col = IndexOfColumn(_keyColumnName)
        If col < 0 Then Return Nothing

        Dim r = _grid.Row
        If r < _grid.Rows.Fixed OrElse r >= _grid.Rows.Count Then Return Nothing

        Try
            Return _grid(r, col)
        Catch
            Return Nothing
        End Try
    End Function

    Private Sub RestoreSelection()
        ' スクロール位置は常にリセットする
        If _grid.Rows.Count > _grid.Rows.Fixed Then
            _grid.TopRow = _grid.Rows.Fixed
        End If

        Dim target = _grid.Rows.Fixed

        If _savedKey IsNot Nothing Then
            Dim col = IndexOfColumn(_keyColumnName)
            If col >= 0 Then
                For r = _grid.Rows.Fixed To _grid.Rows.Count - 1
                    Dim v = _grid(r, col)
                    If v IsNot Nothing AndAlso _savedKey.Equals(v) Then
                        target = r
                        Exit For
                    End If
                Next
            End If
        End If

        If target < _grid.Rows.Count Then
            Try
                _grid.Select(target, _grid.Cols.Fixed, False)
                _grid.ShowCell(target, _grid.Cols.Fixed)
            Catch
                ' 選択できなくても処理は続行する
            End Try
        End If
    End Sub

    Private Function IndexOfColumn(name As String) As Integer
        For i = 0 To _grid.Cols.Count - 1
            If String.Equals(_grid.Cols(i).Name, name, StringComparison.Ordinal) Then Return i
        Next
        Return -1
    End Function

#End Region

End Class


' =====================================================================
'  使用例
' =====================================================================
Public Module RebindSample

    ''' <summary>再検索ボタンの処理。</summary>
    Public Sub OnSearchClick(flex As C1FlexGrid, condition As Object)

        ' --- 1) 編集中の内容を確認する。黙って捨てない ---
        If flex.IsCurrentCellInEditMode Then flex.FinishEditing()

        If HasPendingChanges(flex) Then
            If MessageBox.Show("未保存の変更があります。破棄して再検索しますか？",
                               "確認",
                               MessageBoxButtons.OKCancel,
                               MessageBoxIcon.Warning) <> DialogResult.OK Then
                Return
            End If
        End If

        ' --- 2) DB ロックを取っているなら解放する ---
        ' _lockService.Release()

        ' --- 3) 再バインド。レイアウトと選択行は Using が面倒を見る ---
        Using FlexGridRebindScope.Begin(flex, "受注番号")
            flex.DataSource = LoadData(condition)
        End Using
    End Sub

    ''' <summary>
    ''' 【推奨】列構成が変わらないなら、そもそも再バインドしない。
    ''' 列が再生成されないのでレイアウト復元自体が不要になる。
    ''' </summary>
    Public Sub RefillWithoutRebind(flex As C1FlexGrid, dt As DataTable, adapter As Object)
        flex.Redraw = False
        Try
            dt.BeginLoadData()
            dt.Clear()
            ' adapter.Fill(dt)
            dt.EndLoadData()
        Finally
            flex.Redraw = True
        End Try
    End Sub

    Private Function HasPendingChanges(flex As C1FlexGrid) As Boolean
        Dim dv = TryCast(flex.DataSource, DataView)
        If dv IsNot Nothing Then Return dv.Table.GetChanges() IsNot Nothing

        Dim dt = TryCast(flex.DataSource, DataTable)
        If dt IsNot Nothing Then Return dt.GetChanges() IsNot Nothing

        Return False
    End Function

    Private Function LoadData(condition As Object) As DataTable
        Return New DataTable()
    End Function

End Module
