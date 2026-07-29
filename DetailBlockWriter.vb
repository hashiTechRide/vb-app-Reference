' =====================================================================
'  DetailBlockWriter.vb   (VB.NET / .NET Framework 4.8 / NPOI 2.7.6)
'
'  原本の「明細ブロック」に DataTable を流し込む。
'
'  ★ NPOI 2.7.6 の ShiftRows について（実装をソースで確認済み）
'
'    XSSFSheet.ShiftRows は以下を追随させる:
'        結合セル / 名前定義 / 数式 / 条件付き書式 / ハイパーリンク /
'        コメント / 行の高さ
'
'    追随させない:
'        ★★ 図形・画像（Drawing）★★
'
'    XSSFRowShifter に ShiftDrawings 相当の処理が存在しないため、
'    行を挿入してもアンカー済みの図形・画像はその場に留まる。
'    結果、セルだけが下にずれて図形が本文に重なる。
'
'    → 明細ブロックより下に図形がある原本では ShiftRows を使ってはいけない。
'      本クラスは事前に検出して例外を投げる。
' =====================================================================
Option Strict On
Option Explicit On

Imports System.Collections.Generic
Imports System.Data
Imports System.Linq
Imports System.Text
Imports NPOI.SS.UserModel
Imports NPOI.SS.Util
Imports NPOI.XSSF.UserModel

#Region "設定"

Public Enum DetailExpandMode
    ''' <summary>
    ''' 原本にあらかじめ用意された行数の範囲で書く。行を挿入しないので
    ''' 図形・画像が絶対にずれない。件数上限が決まっている帳票はこちらを推奨。
    ''' </summary>
    FixedRows

    ''' <summary>
    ''' 足りない分を ShiftRows で挿入する。件数可変の一覧向け。
    ''' 明細ブロック以降に図形・画像があると使用不可（例外になる）。
    ''' </summary>
    ShiftAndCopy
End Enum

Public Enum SurplusRowAction
    ''' <summary>余った行を空欄にする。罫線は残るので帳票の体裁を保てる。</summary>
    KeepBlank
    ''' <summary>余った行を非表示にする。</summary>
    Hide
    ''' <summary>何もしない。雛形の内容がそのまま残るので通常は使わない。</summary>
    Leave
End Enum

''' <summary>明細ブロック内の1列の割り当て。</summary>
Public Class DetailColumn

    ''' <summary>明細ブロックの左端からのオフセット（0起点）。</summary>
    Public Property Offset As Integer

    ''' <summary>
    ''' DataTable の列名。Nothing にすると書き込まないので、
    ''' 原本側に仕込んだ数式（小計など）をそのまま活かせる。
    ''' </summary>
    Public Property SourceColumn As String

    Public Sub New(offset As Integer, sourceColumn As String)
        Me.Offset = offset
        Me.SourceColumn = sourceColumn
    End Sub
End Class

Public Class DetailFillResult
    ''' <summary>実際に書き込んだ行数。</summary>
    Public Property WrittenRows As Integer
    ''' <summary>明細ブロックの最終行（0起点）。合計行の位置決めに使う。</summary>
    Public Property LastRowIndex As Integer
    ''' <summary>挿入した行数。</summary>
    Public Property InsertedRows As Integer
End Class

#End Region


Public NotInheritable Class DetailBlockWriter

    Private Sub New()
    End Sub

    ''' <summary>
    ''' 名前定義で指定した明細ブロックに DataTable を流し込む。
    ''' </summary>
    ''' <param name="areaName">明細ブロックを指す名前定義（範囲）。</param>
    Public Shared Function Fill(wb As IWorkbook,
                                areaName As String,
                                table As DataTable,
                                columns As IList(Of DetailColumn),
                                Optional mode As DetailExpandMode = DetailExpandMode.FixedRows,
                                Optional surplus As SurplusRowAction = SurplusRowAction.KeepBlank) As DetailFillResult

        If wb Is Nothing Then Throw New ArgumentNullException(NameOf(wb))
        If table Is Nothing Then Throw New ArgumentNullException(NameOf(table))

        Dim area = NamedCell.GetArea(wb, areaName)
        Dim sheet = wb.GetSheet(area.FirstCell.SheetName)
        If sheet Is Nothing Then
            Throw New InvalidOperationException(
                $"名前定義「{areaName}」の参照先シート「{area.FirstCell.SheetName}」がありません。")
        End If

        Dim firstRow = area.FirstCell.Row
        Dim lastRow = area.LastCell.Row
        Dim firstCol As Integer = area.FirstCell.Col

        Dim capacity = lastRow - firstRow + 1
        Dim need = table.Rows.Count
        Dim inserted = 0

        ' ---------- 行数の調整 ----------
        If need > capacity Then
            Select Case mode

                Case DetailExpandMode.FixedRows
                    Throw New InvalidOperationException(
                        $"明細が {need} 件ありますが、この帳票原本に用意されている明細行は " &
                        $"{capacity} 行です。" & vbCrLf &
                        "件数を絞って出力するか、原本の明細行を増やしてください。")

                Case DetailExpandMode.ShiftAndCopy
                    inserted = need - capacity

                    ' ★ 図形がずれる事故を未然に止める
                    EnsureNoDrawingsAtOrBelow(sheet, lastRow + 1, areaName)

                    ' 明細ブロックの直下から下を、必要分だけ押し下げる
                    If lastRow + 1 <= sheet.LastRowNum Then
                        sheet.ShiftRows(lastRow + 1, sheet.LastRowNum, inserted,
                                        copyRowHeight:=True, resetOriginalRowHeight:=False)
                    End If

                    ' 空いた領域に雛形行（ブロック最終行）を複製する
                    Dim xs = TryCast(sheet, XSSFSheet)
                    If xs Is Nothing Then
                        Throw New NotSupportedException("行の挿入は .xlsx（XSSF）でのみ対応します。")
                    End If

                    Dim policy = New CellCopyPolicy.Builder() _
                        .CellValue(False) _
                        .CellStyle(True) _
                        .CellFormula(True) _
                        .RowHeight(True) _
                        .MergedRegions(True) _
                        .Build()

                    For i = 0 To inserted - 1
                        xs.CopyRows(lastRow, lastRow, lastRow + 1 + i, policy)
                    Next

                    lastRow += inserted
            End Select
        End If

        ' ---------- 値の書き込み ----------
        Dim written = Math.Min(need, lastRow - firstRow + 1)

        For i = 0 To written - 1
            Dim rowIndex = firstRow + i
            Dim row = sheet.GetRow(rowIndex)
            If row Is Nothing Then row = sheet.CreateRow(rowIndex)

            Dim dr = table.Rows(i)

            For Each c In columns
                If String.IsNullOrEmpty(c.SourceColumn) Then Continue For   ' 数式温存
                If Not table.Columns.Contains(c.SourceColumn) Then Continue For

                Dim cell = GetOrCreateCell(sheet, row, firstCol + c.Offset, firstRow)
                SetValue(cell, dr(c.SourceColumn))
            Next
        Next

        ' ---------- 余った行の処理 ----------
        If written < (lastRow - firstRow + 1) Then
            For rowIndex = firstRow + written To lastRow
                Dim row = sheet.GetRow(rowIndex)
                If row Is Nothing Then Continue For

                Select Case surplus
                    Case SurplusRowAction.Hide
                        row.ZeroHeight = True

                    Case SurplusRowAction.KeepBlank
                        For Each c In columns
                            Dim cell = row.GetCell(firstCol + c.Offset)
                            If cell IsNot Nothing Then cell.SetBlank()
                        Next

                    Case SurplusRowAction.Leave
                        ' 何もしない
                End Select
            Next
        End If

        Return New DetailFillResult With {
            .WrittenRows = written,
            .LastRowIndex = lastRow,
            .InsertedRows = inserted
        }
    End Function


#Region "内部"

    ''' <summary>
    ''' 指定行以降にアンカーされた図形・画像があれば例外にする。
    ''' NPOI の ShiftRows は Drawing を移動しないため、これを許すと
    ''' 図形が本文に重なった帳票が静かに出力されてしまう。
    ''' </summary>
    Private Shared Sub EnsureNoDrawingsAtOrBelow(sheet As ISheet, rowIndex As Integer, areaName As String)

        Dim xs = TryCast(sheet, XSSFSheet)
        If xs Is Nothing Then Return

        ' DrawingPatriarch は描画が無ければ null（パートを新規作成しない）
        Dim drawing = TryCast(xs.DrawingPatriarch, XSSFDrawing)
        If drawing Is Nothing Then Return

        Dim offenders As New List(Of String)()

        For Each shape In drawing.GetShapes()
            Dim anchor = TryCast(shape.GetAnchor(), XSSFClientAnchor)
            If anchor Is Nothing Then Continue For

            If anchor.Row2 >= rowIndex Then
                offenders.Add($"{shape.GetType().Name}（{anchor.Row1 + 1}行目付近）")
            End If
        Next

        If offenders.Count > 0 Then
            Dim sb As New StringBuilder()
            sb.AppendLine($"明細ブロック「{areaName}」より下に図形・画像が配置されているため、")
            sb.AppendLine("行を挿入すると図形の位置がずれます。処理を中止しました。")
            sb.AppendLine()
            sb.AppendLine("該当:")
            For Each o In offenders.Take(10)
                sb.AppendLine("　・" & o)
            Next
            sb.AppendLine()
            sb.AppendLine("対処: 原本の明細行をあらかじめ必要数用意して FixedRows で使うか、")
            sb.AppendLine("　　　図形を明細ブロックより上へ移動してください。")
            Throw New InvalidOperationException(sb.ToString())
        End If
    End Sub

    ''' <summary>
    ''' セルを取得する。無ければ作り、雛形行の同じ列から書式を引き継ぐ。
    ''' 引き継がないと罫線も表示形式も失われる。
    ''' </summary>
    Private Shared Function GetOrCreateCell(sheet As ISheet, row As IRow,
                                            colIndex As Integer, templateRowIndex As Integer) As ICell
        Dim cell = row.GetCell(colIndex)
        If cell IsNot Nothing Then Return cell

        cell = row.CreateCell(colIndex)

        Dim tmplRow = sheet.GetRow(templateRowIndex)
        If tmplRow IsNot Nothing Then
            Dim tmplCell = tmplRow.GetCell(colIndex)
            If tmplCell IsNot Nothing Then cell.CellStyle = tmplCell.CellStyle
        End If

        Return cell
    End Function

    Private Shared Sub SetValue(cell As ICell, value As Object)
        If value Is Nothing OrElse value Is DBNull.Value Then
            cell.SetBlank()
            Return
        End If

        Select Case Type.GetTypeCode(value.GetType())
            Case TypeCode.Boolean
                cell.SetCellValue(CBool(value))
            Case TypeCode.DateTime
                cell.SetCellValue(CDate(value))
            Case TypeCode.Byte, TypeCode.SByte, TypeCode.Int16, TypeCode.UInt16,
                 TypeCode.Int32, TypeCode.UInt32, TypeCode.Int64, TypeCode.UInt64,
                 TypeCode.Single, TypeCode.Double, TypeCode.Decimal
                cell.SetCellValue(Convert.ToDouble(value))
            Case Else
                cell.SetCellValue(value.ToString())
        End Select
    End Sub

#End Region

End Class


#Region "使用例"

Public Module DetailSample

    Public Sub Example(wb As IWorkbook, dt As DataTable)

        Dim cols As New List(Of DetailColumn) From {
            New DetailColumn(0, "行番号"),
            New DetailColumn(1, "品番"),
            New DetailColumn(2, "品名"),
            New DetailColumn(3, "数量"),
            New DetailColumn(4, "単価"),
            New DetailColumn(5, Nothing)      ' 金額は原本の数式（=D*E）に任せる
        }

        Dim result = DetailBlockWriter.Fill(
            wb, "明細_雛形行", dt, cols,
            mode:=DetailExpandMode.FixedRows,
            surplus:=SurplusRowAction.KeepBlank)

        ' 合計行の位置は返り値から決める。番地を直書きしない
        Dim sheet = wb.GetSheet("帳票")
        Dim totalRow = sheet.GetRow(result.LastRowIndex + 1)
        If totalRow IsNot Nothing Then
            Dim c = totalRow.GetCell(5)
            If c IsNot Nothing Then
                c.SetCellFormula($"SUM(F{result.LastRowIndex - result.WrittenRows + 2}:F{result.LastRowIndex + 1})")
            End If
        End If

        ' 数式を入れたら再計算を強制する（NPOI は計算しないため）
        sheet.ForceFormulaRecalculation = True
    End Sub

End Module

#End Region
