## 1. 原本方式 vs コード生成 — 分岐点

結論を先に言うと、**「レイアウトが固定で複雑」なら原本、「構造が動的」ならコード**です。

| | 原本(テンプレート) | コード生成 |
|---|---|---|
| 罫線・結合セル・条件付き書式が凝っている | ◎ Excelで作れる | ✗ 記述量が爆発する |
| 列数・シート数が実行時に変わる | ✗ | ◎ |
| 非開発者が体裁を直せる | ◎ | ✗ |
| 単体テスト・差分管理 | △ | ◎ |
| 配布・ファイル管理 | △ 事故要因 | ◎ 不要 |

正直に言うと、**画像と図形を多用する固定帳票はコード生成が一番つらい領域**です。「1mmずらす → ビルド → Excelで確認」を何十回も回すことになります。列が可変・件数が可変の一覧表ならコード生成でまったく問題ありません。将来つらくなったら「原本に値だけ流し込むハイブリッド」に逃げられるよう、値の生成と体裁の適用は分けておくと後が楽です。

ひとまずコード生成で進める方針は了解しました。

## 2. ライブラリ選定

**COM参照は新規開発では避けてください。** Excelのインストールが必須、遅い、そして RCW の解放漏れで `EXCEL.EXE` がゾンビ化する典型的な事故が起きます。既存資産の保守以外に使う理由はほぼないです。

NuGet 各種を、**社内業務＝営利利用**という前提で整理します（これが選定を大きく左右します）。

| ライブラリ | 営利利用のライセンス | .NET FW 4.8 | 画像の精密配置 | 図形 |
|---|---|---|---|---|
| **NPOI 2.7.x** | Apache 2.0 / 無償 | ✓ | ◎ EMU単位 | ○ |
| NPOI 2.8.0+ | **有償**（後述） | ✓ (4.7.2+) | ◎ | ○ |
| ClosedXML 0.105 | MIT / 無償 | ✓ (4.6.2+) | ○ px単位 | **✗ 非対応** |
| EPPlus 5+ | **要商用ライセンス** | ✓ | ◎ | ◎ |
| C1Excel | C1ライセンス内 | ✓ | △ | △ 貧弱 |

**推奨は NPOI** です。図形を操作したいという要件で ClosedXML が脱落し（画像は扱えますが Shape/テキストボックスの API がありません）、EPPlus は v5 以降 Polyform Noncommercial ライセンスとなり、商用環境での利用には商用ライセンスが必要なので、社内システムでも有償になります。

ただし NPOI にも注意点があります。2026年4月の 2.8.0 で Open Source Maintenance Fee の EULA が追加され、収益を上げている組織・利用者は GitHub Sponsors 経由で月額のメンテナンス費を支払うことが求められるようになりました。ビルド時に EULA 同意タグをチェックする MSBuild ターゲットも入っています。選択肢は2つ:

- **2.7.x に固定する**（`Install-Package NPOI -Version 2.7.4`）— Apache 2.0 のままで完全に無償・合法
- **費用を払って 2.8.x を使う** — 額は小さく、継続的にお世話になるなら妥当

社内稟議の手間を考えると、まず 2.7.x で始めるのが現実的だと思います。

## 3. 画像・図形の位置指定の考え方

ここが本題ですね。OOXML の図形座標は **EMU (English Metric Unit)** です。

```
1 inch = 914,400 EMU / 1 pt = 12,700 EMU / 1 px(96dpi) = 9,525 EMU / 1 mm = 36,000 EMU
```

そして位置指定の主役が `XSSFClientAnchor` です。

```
XSSFClientAnchor(dx1, dy1, dx2, dy2, col1, row1, col2, row2)
                 └起点セル内の  └終点セル内の  └起点セル  └終点セル
                   オフセット     オフセット
```

これで「**B3セルの左から3mm・上から1mmの位置に、15mm角**」という指定が素直に書けます。起点セルと終点セルを**同じにして** dx2/dy2 でサイズを表現すると、列幅を変えても画像サイズがずれません（印影やロゴはこれが正解）。

`AnchorType` も忘れずに:
- `MoveAndResize` — セルに追従して伸縮
- `MoveDontResize` — 移動のみ（**印影・ロゴはこれ**）
- `DontMoveAndResize` — 完全固定

図形側は `XSSFDrawing` から生やします。

```vb
Dim drawing = CType(sheet.CreateDrawingPatriarch(), XSSFDrawing)
drawing.CreateSimpleShape(anchor)   ' 四角・楕円・矢印など
drawing.CreateTextbox(anchor)       ' テキストボックス
drawing.CreateConnector(anchor)     ' 直線・コネクタ
drawing.CreateGroup(anchor)         ' グループ化
```

`CreateDrawingPatriarch()` は同一インスタンスを返す実装ですが、自前でキャッシュしておく方が安全です。

## 4. 実装

上記を全部まとめたクラスを作りました。**先に潰しておくべき落とし穴を3つ:**

1. **CellStyle は必ずキャッシュする。** XLSX の CellStyle 上限は約64,000です。セルごとに `CreateCellStyle()` を呼ぶループを書くと、数千行でファイルが壊れて開けなくなります。NPOI の事故で一番多いパターンなので、コード内では `_styleCache` で握っています。

2. **日付セルは `DataFormat` を設定しないとシリアル値（45000みたいな数値）で表示されます。** `SetCellValue(Date)` だけでは書式が付きません。

3. **`AutoSizeColumn` は遅い。** フォント計測が走るので、数千行だと体感で止まります。列幅は明示指定してください（`SetColumnWidth` の単位は「半角文字数 × 256」です）。

なお `ShapeTypes.RoundRectangle` の定数名だけは NPOI のバージョンによって綴りが違う可能性があるので、IntelliSense で確認してください（`ShapeTypes.Rectangle` は確認済みです）。10万行を超えるようなら `XSSFWorkbook` ではなく `SXSSFWorkbook`（ストリーミング）への切り替えも検討対象になります。

```vb
' =====================================================================
'  ExcelExporter.vb   (VB.NET / .NET Framework 4.8 / NPOI)
'
'  NuGet:  Install-Package NPOI
'  ※ NPOI 2.8.0 以降は OSMF EULA（営利組織は月額メンテナンス費）が付いています。
'    費用を避けるなら 2.7.x に固定してください:
'      Install-Package NPOI -Version 2.7.4
' =====================================================================
Imports System.Collections.Generic
Imports System.Data
Imports System.Drawing
Imports System.IO
Imports NPOI.SS.UserModel
Imports NPOI.SS.Util
Imports NPOI.XSSF.UserModel

#Region "単位変換"

''' <summary>
''' OOXML の図形座標は EMU (English Metric Unit)。
'''   1 inch = 914,400 EMU / 1 pt = 12,700 EMU / 1 px(96dpi) = 9,525 EMU / 1 mm = 36,000 EMU
''' </summary>
Public NotInheritable Class Emu
    Private Sub New()
    End Sub

    Public Const PerPixel As Integer = 9525
    Public Const PerPoint As Integer = 12700
    Public Const PerMm As Integer = 36000
    Public Const PerInch As Integer = 914400

    Public Shared Function FromMm(mm As Double) As Integer
        Return CInt(Math.Round(mm * PerMm))
    End Function

    Public Shared Function FromPixel(px As Double) As Integer
        Return CInt(Math.Round(px * PerPixel))
    End Function

    Public Shared Function FromPoint(pt As Double) As Integer
        Return CInt(Math.Round(pt * PerPoint))
    End Function
End Class

#End Region

#Region "列定義"

Public Enum ExcelAlign
    [Default]
    Left
    Center
    Right
End Enum

''' <summary>出力する1列分の仕様。</summary>
Public Class ExcelColumnSpec

    ''' <summary>DataTable 側の列名。</summary>
    Public Property SourceColumn As String

    ''' <summary>見出し文字列。未指定なら SourceColumn。</summary>
    Public Property Header As String

    ''' <summary>列幅（半角文字数）。</summary>
    Public Property WidthChars As Double = 12

    ''' <summary>表示書式。例: "#,##0" / "#,##0.00" / "yyyy/mm/dd" / "@"</summary>
    Public Property NumberFormat As String

    Public Property Align As ExcelAlign = ExcelAlign.Default

    Public Property WrapText As Boolean = False

    Public Sub New(sourceColumn As String)
        Me.SourceColumn = sourceColumn
        Me.Header = sourceColumn
    End Sub
End Class

#End Region


Public Class ExcelExporter
    Implements IDisposable

    Private ReadOnly _wb As XSSFWorkbook
    ' ★重要★ CellStyle は必ずキャッシュする。
    '   XLSX の CellStyle 上限は約 64,000。セルごとに CreateCellStyle すると
    '   数千行で破綻し、ファイルが開けなくなる（NPOI 最頻出の事故）。
    Private ReadOnly _styleCache As New Dictionary(Of String, ICellStyle)(StringComparer.Ordinal)
    Private ReadOnly _drawings As New Dictionary(Of String, XSSFDrawing)(StringComparer.Ordinal)
    Private _disposed As Boolean

    Public ReadOnly Property Workbook As XSSFWorkbook
        Get
            Return _wb
        End Get
    End Property

    ''' <summary>既定フォント名。日本語帳票は "游ゴシック" / "MS Pゴシック" など。</summary>
    Public Property FontName As String = "游ゴシック"
    Public Property FontSize As Short = 9

    Public Sub New()
        _wb = New XSSFWorkbook()
    End Sub

#Region "DataTable 出力"

    ''' <summary>
    ''' DataTable を1シートに出力する。
    ''' </summary>
    ''' <param name="specs">出力する列と書式。Nothing なら DataTable の全列を既定書式で。</param>
    ''' <param name="startRow">0 起点。タイトル行を上に置く場合はここをずらす。</param>
    Public Function WriteTable(sheetName As String,
                               table As DataTable,
                               Optional specs As IList(Of ExcelColumnSpec) = Nothing,
                               Optional startRow As Integer = 0,
                               Optional startCol As Integer = 0) As ISheet

        If table Is Nothing Then Throw New ArgumentNullException(NameOf(table))

        Dim sheet = TryCast(_wb.GetSheet(sheetName), ISheet)
        If sheet Is Nothing Then sheet = _wb.CreateSheet(sheetName)

        If specs Is Nothing OrElse specs.Count = 0 Then
            Dim tmp As New List(Of ExcelColumnSpec)()
            For Each dc As DataColumn In table.Columns
                tmp.Add(New ExcelColumnSpec(dc.ColumnName) With {
                    .NumberFormat = GuessFormat(dc.DataType)
                })
            Next
            specs = tmp
        End If

        ' ---- ヘッダー ----
        Dim headerStyle = GetStyle("HDR", Nothing, ExcelAlign.Center, bold:=True,
                                   bordered:=True, fillArgb:=Color.FromArgb(221, 235, 247), wrap:=True)
        Dim hr = GetOrCreateRow(sheet, startRow)
        hr.HeightInPoints = 22.0F
        For i = 0 To specs.Count - 1
            Dim cell = hr.CreateCell(startCol + i)
            cell.SetCellValue(If(specs(i).Header, specs(i).SourceColumn))
            cell.CellStyle = headerStyle
            sheet.SetColumnWidth(startCol + i, CInt(specs(i).WidthChars * 256))
        Next

        ' ---- 明細 ----
        Dim bodyStyles(specs.Count - 1) As ICellStyle
        For i = 0 To specs.Count - 1
            bodyStyles(i) = GetStyle("BODY", specs(i).NumberFormat, specs(i).Align,
                                     bold:=False, bordered:=True, fillArgb:=Nothing,
                                     wrap:=specs(i).WrapText)
        Next

        For r = 0 To table.Rows.Count - 1
            Dim dr = table.Rows(r)
            Dim row = GetOrCreateRow(sheet, startRow + 1 + r)
            For i = 0 To specs.Count - 1
                Dim cell = row.CreateCell(startCol + i)
                cell.CellStyle = bodyStyles(i)
                If table.Columns.Contains(specs(i).SourceColumn) Then
                    SetCellValue(cell, dr(specs(i).SourceColumn))
                End If
            Next
        Next

        ' ---- 仕上げ ----
        sheet.CreateFreezePane(startCol, startRow + 1)
        If table.Rows.Count > 0 Then
            sheet.SetAutoFilter(New CellRangeAddress(startRow, startRow,
                                                     startCol, startCol + specs.Count - 1))
        End If

        Return sheet
    End Function

    Private Shared Function GuessFormat(t As Type) As String
        If t Is GetType(Date) Then Return "yyyy/mm/dd"
        If t Is GetType(Decimal) OrElse t Is GetType(Double) OrElse t Is GetType(Single) Then Return "#,##0.00"
        If t Is GetType(Integer) OrElse t Is GetType(Long) OrElse t Is GetType(Short) Then Return "#,##0"
        Return Nothing
    End Function

    Private Shared Sub SetCellValue(cell As ICell, value As Object)
        If value Is Nothing OrElse value Is DBNull.Value Then
            cell.SetCellType(CellType.Blank)
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

    Private Shared Function GetOrCreateRow(sheet As ISheet, index As Integer) As IRow
        Dim row = sheet.GetRow(index)
        If row Is Nothing Then row = sheet.CreateRow(index)
        Return row
    End Function

#End Region

#Region "スタイル（キャッシュ必須）"

    Public Function GetStyle(tag As String,
                             numberFormat As String,
                             align As ExcelAlign,
                             Optional bold As Boolean = False,
                             Optional bordered As Boolean = True,
                             Optional fillArgb As Color? = Nothing,
                             Optional wrap As Boolean = False) As ICellStyle

        Dim key = String.Join("/", tag, If(numberFormat, ""), CInt(align).ToString(),
                              bold.ToString(), bordered.ToString(),
                              If(fillArgb.HasValue, fillArgb.Value.ToArgb().ToString(), ""),
                              wrap.ToString())

        Dim cached As ICellStyle = Nothing
        If _styleCache.TryGetValue(key, cached) Then Return cached

        Dim st = DirectCast(_wb.CreateCellStyle(), XSSFCellStyle)

        Dim f = DirectCast(_wb.CreateFont(), XSSFFont)
        f.FontName = FontName
        f.FontHeightInPoints = FontSize
        f.IsBold = bold
        st.SetFont(f)

        Select Case align
            Case ExcelAlign.Left : st.Alignment = HorizontalAlignment.Left
            Case ExcelAlign.Center : st.Alignment = HorizontalAlignment.Center
            Case ExcelAlign.Right : st.Alignment = HorizontalAlignment.Right
            Case Else : st.Alignment = HorizontalAlignment.General
        End Select
        st.VerticalAlignment = VerticalAlignment.Center
        st.WrapText = wrap

        If bordered Then
            st.BorderTop = BorderStyle.Thin
            st.BorderBottom = BorderStyle.Thin
            st.BorderLeft = BorderStyle.Thin
            st.BorderRight = BorderStyle.Thin
        End If

        If fillArgb.HasValue Then
            st.SetFillForegroundColor(New XSSFColor(fillArgb.Value))
            st.FillPattern = FillPattern.SolidForeground
        End If

        If Not String.IsNullOrEmpty(numberFormat) Then
            st.DataFormat = _wb.CreateDataFormat().GetFormat(numberFormat)
        End If

        _styleCache(key) = st
        Return st
    End Function

#End Region

#Region "画像配置"

    ''' <summary>
    ''' 画像をセル基準＋EMU オフセットで配置する。
    '''
    ''' XSSFClientAnchor(dx1, dy1, dx2, dy2, col1, row1, col2, row2)
    '''   col1/row1 … 起点セル（0起点）、dx1/dy1 … そのセル左上からのオフセット
    '''   col2/row2 … 終点セル、       dx2/dy2 … そのセル左上からのオフセット
    ''' → 「B3 の左から 2mm、上から 1.5mm の位置に 15mm 角」といった指定ができる。
    ''' </summary>
    ''' <param name="anchorType">
    '''   MoveAndResize      : セルに合わせて移動・サイズ変更
    '''   MoveDontResize     : 移動のみ（印影・ロゴはこれが無難）
    '''   DontMoveAndResize  : 固定
    ''' </param>
    Public Function AddPicture(sheet As ISheet,
                               imagePath As String,
                               col As Integer, row As Integer,
                               offsetXmm As Double, offsetYmm As Double,
                               widthMm As Double, heightMm As Double,
                               Optional anchorType As AnchorType = AnchorType.MoveDontResize) As IPicture

        Dim bytes = File.ReadAllBytes(imagePath)
        Dim picType = DetectPictureType(imagePath)
        Dim picIdx = _wb.AddPicture(bytes, picType)

        Dim drawing = GetDrawing(sheet)

        ' 終点セルは起点と同じにして、dx2/dy2 でサイズを表現する
        ' （列幅・行高を跨いでも幅がずれない絶対サイズ指定）
        Dim anchor As New XSSFClientAnchor(
            Emu.FromMm(offsetXmm),
            Emu.FromMm(offsetYmm),
            Emu.FromMm(offsetXmm + widthMm),
            Emu.FromMm(offsetYmm + heightMm),
            col, row, col, row)
        anchor.AnchorType = anchorType

        Return drawing.CreatePicture(anchor, picIdx)
    End Function

    ''' <summary>元画像サイズのまま、指定セル＋オフセット位置に置く。</summary>
    Public Function AddPictureOriginalSize(sheet As ISheet,
                                           imagePath As String,
                                           col As Integer, row As Integer,
                                           offsetXmm As Double, offsetYmm As Double,
                                           Optional scale As Double = 1.0) As IPicture

        Dim bytes = File.ReadAllBytes(imagePath)
        Dim picIdx = _wb.AddPicture(bytes, DetectPictureType(imagePath))
        Dim drawing = GetDrawing(sheet)

        Dim anchor As New XSSFClientAnchor(
            Emu.FromMm(offsetXmm), Emu.FromMm(offsetYmm), 0, 0,
            col, row, col, row)
        anchor.AnchorType = AnchorType.MoveDontResize

        Dim pic = drawing.CreatePicture(anchor, picIdx)
        pic.Resize(scale)   ' 元サイズ×scale で dx2/dy2 を再計算
        Return pic
    End Function

    Private Shared Function DetectPictureType(path As String) As PictureType
        Select Case Path.GetExtension(path).ToLowerInvariant()
            Case ".png" : Return PictureType.PNG
            Case ".jpg", ".jpeg" : Return PictureType.JPEG
            Case ".gif" : Return PictureType.GIF
            Case ".bmp" : Return PictureType.BMP
            Case ".emf" : Return PictureType.EMF
            Case ".wmf" : Return PictureType.WMF
            Case Else : Return PictureType.PNG
        End Select
    End Function

#End Region

#Region "図形"

    ''' <summary>四角形（テキスト入り）。承認欄・注記枠など。</summary>
    Public Function AddRectangle(sheet As ISheet,
                                 col As Integer, row As Integer,
                                 offsetXmm As Double, offsetYmm As Double,
                                 widthMm As Double, heightMm As Double,
                                 text As String,
                                 Optional fill As Color? = Nothing,
                                 Optional line As Color? = Nothing,
                                 Optional shapeType As Integer = ShapeTypes.Rectangle) As XSSFSimpleShape

        Dim drawing = GetDrawing(sheet)
        Dim anchor As New XSSFClientAnchor(
            Emu.FromMm(offsetXmm), Emu.FromMm(offsetYmm),
            Emu.FromMm(offsetXmm + widthMm), Emu.FromMm(offsetYmm + heightMm),
            col, row, col, row)
        anchor.AnchorType = AnchorType.MoveDontResize

        Dim shape = drawing.CreateSimpleShape(anchor)
        shape.ShapeType = shapeType

        If fill.HasValue Then
            shape.SetFillColor(fill.Value.R, fill.Value.G, fill.Value.B)
        Else
            shape.SetNoFill(True)
        End If

        Dim lc = If(line.HasValue, line.Value, Color.Black)
        shape.SetLineStyleColor(lc.R, lc.G, lc.B)
        shape.LineWidth = 1.0

        If Not String.IsNullOrEmpty(text) Then
            Dim f = DirectCast(_wb.CreateFont(), XSSFFont)
            f.FontName = FontName
            f.FontHeightInPoints = FontSize
            Dim rt As New XSSFRichTextString(text)
            rt.ApplyFont(f)
            shape.SetText(rt)
        End If

        Return shape
    End Function

    ''' <summary>テキストボックス（枠線なし文字。注釈用）。</summary>
    Public Function AddTextBox(sheet As ISheet,
                               col As Integer, row As Integer,
                               offsetXmm As Double, offsetYmm As Double,
                               widthMm As Double, heightMm As Double,
                               text As String) As XSSFTextBox

        Dim drawing = GetDrawing(sheet)
        Dim anchor As New XSSFClientAnchor(
            Emu.FromMm(offsetXmm), Emu.FromMm(offsetYmm),
            Emu.FromMm(offsetXmm + widthMm), Emu.FromMm(offsetYmm + heightMm),
            col, row, col, row)
        anchor.AnchorType = AnchorType.MoveDontResize

        Dim tb = drawing.CreateTextbox(anchor)
        tb.SetNoFill(True)

        Dim f = DirectCast(_wb.CreateFont(), XSSFFont)
        f.FontName = FontName
        f.FontHeightInPoints = FontSize
        Dim rt As New XSSFRichTextString(text)
        rt.ApplyFont(f)
        tb.SetText(rt)

        Return tb
    End Function

    ''' <summary>直線／コネクタ。</summary>
    Public Function AddLine(sheet As ISheet,
                            col1 As Integer, row1 As Integer, x1mm As Double, y1mm As Double,
                            col2 As Integer, row2 As Integer, x2mm As Double, y2mm As Double,
                            Optional width As Double = 1.0,
                            Optional style As LineStyle = LineStyle.Solid) As XSSFConnector

        Dim drawing = GetDrawing(sheet)
        Dim anchor As New XSSFClientAnchor(
            Emu.FromMm(x1mm), Emu.FromMm(y1mm),
            Emu.FromMm(x2mm), Emu.FromMm(y2mm),
            col1, row1, col2, row2)
        anchor.AnchorType = AnchorType.MoveDontResize

        Dim c = drawing.CreateConnector(anchor)
        c.LineWidth = width
        c.LineStyle = style
        Return c
    End Function

    ''' <summary>シートごとの Drawing は必ず使い回す（毎回作ると図形が消える／重複する）。</summary>
    Private Function GetDrawing(sheet As ISheet) As XSSFDrawing
        Dim d As XSSFDrawing = Nothing
        If _drawings.TryGetValue(sheet.SheetName, d) Then Return d
        d = DirectCast(sheet.CreateDrawingPatriarch(), XSSFDrawing)
        _drawings(sheet.SheetName) = d
        Return d
    End Function

#End Region

#Region "印刷設定・保存"

    Public Sub SetupPrint(sheet As ISheet,
                          Optional landscape As Boolean = False,
                          Optional fitToWidthPages As Short = 1,
                          Optional repeatHeaderRow As Integer = -1)

        sheet.PrintSetup.Landscape = landscape
        sheet.PrintSetup.PaperSize = CShort(PaperSize.A4)
        sheet.FitToPage = True
        sheet.PrintSetup.FitWidth = fitToWidthPages
        sheet.PrintSetup.FitHeight = 0     ' 0 = 高さ方向は制限なし
        sheet.SetMargin(MarginType.LeftMargin, 0.5)
        sheet.SetMargin(MarginType.RightMargin, 0.5)

        If repeatHeaderRow >= 0 Then
            sheet.RepeatingRows = New CellRangeAddress(repeatHeaderRow, repeatHeaderRow, -1, -1)
        End If
    End Sub

    Public Sub Save(path As String)
        Dim dir = Path.GetDirectoryName(path)
        If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
            Directory.CreateDirectory(dir)
        End If
        Using fs As New FileStream(path, FileMode.Create, FileAccess.Write)
            _wb.Write(fs, leaveOpen:=False)
        End Using
    End Sub

#End Region

    Public Sub Dispose() Implements IDisposable.Dispose
        If _disposed Then Return
        _disposed = True
        _wb.Close()
    End Sub

End Class


' =====================================================================
'  使用例
' =====================================================================
Public Module ExcelExporterSample

    Public Sub Export(dt As DataTable, outPath As String)

        Using ex As New ExcelExporter()

            Dim specs As New List(Of ExcelColumnSpec) From {
                New ExcelColumnSpec("品番") With {.Header = "品番", .WidthChars = 14, .Align = ExcelAlign.Left},
                New ExcelColumnSpec("品名") With {.Header = "品名", .WidthChars = 30, .Align = ExcelAlign.Left, .WrapText = True},
                New ExcelColumnSpec("数量") With {.Header = "数量", .WidthChars = 10, .NumberFormat = "#,##0", .Align = ExcelAlign.Right},
                New ExcelColumnSpec("単価") With {.Header = "単価", .WidthChars = 12, .NumberFormat = "#,##0.00", .Align = ExcelAlign.Right},
                New ExcelColumnSpec("納期") With {.Header = "納期", .WidthChars = 12, .NumberFormat = "yyyy/mm/dd", .Align = ExcelAlign.Center}
            }

            ' 3行目(index=2)から表を出力。上2行はタイトル用に空けておく。
            Dim sheet = ex.WriteTable("明細", dt, specs, startRow:=2, startCol:=0)

            ' タイトル
            Dim title = sheet.CreateRow(0).CreateCell(0)
            title.SetCellValue("受注明細一覧")
            title.CellStyle = ex.GetStyle("TITLE", Nothing, ExcelAlign.Left, bold:=True, bordered:=False)

            ' 印影を F1 セルの「左から 3mm・上から 1mm」に 15mm 角で
            ' ex.AddPicture(sheet, "C:\stamp\hanko.png", col:=5, row:=0,
            '               offsetXmm:=3, offsetYmm:=1, widthMm:=15, heightMm:=15)

            ' 承認枠（角丸四角）
            ex.AddRectangle(sheet, col:=6, row:=0, offsetXmm:=0, offsetYmm:=0,
                            widthMm:=25, heightMm:=12, text:="承 認",
                            fill:=Color.White, line:=Color.Black,
                            shapeType:=ShapeTypes.RoundRectangle)

            ' 注記
            ex.AddTextBox(sheet, col:=0, row:=1, offsetXmm:=0, offsetYmm:=0,
                          widthMm:=80, heightMm:=6, text:="※単価は税抜表示です")

            ex.SetupPrint(sheet, landscape:=True, fitToWidthPages:=1, repeatHeaderRow:=2)
            ex.Save(outPath)
        End Using
    End Sub

End Module
```
