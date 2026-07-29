' =====================================================================
'  TemplateIntegrityChecker.vb   (VB.NET / .NET Framework 4.8 / NPOI 2.7.6)
'
'  「NPOI で原本を開いて書き出したとき、何が失われるか」を実際に試して検知する。
'
'  NPOI は原本をファイル全体として再構築するため、NPOI がモデル化していない
'  要素は静かに消える。しかも壊れるのは「ユーザーが原本を編集した後」なので、
'  開発時のテストでは絶対に見つからない。
'  → 原本を受け入れる時点で毎回この検査を通すのが唯一の現実的な防御。
'
'  【依存関係】追加 NuGet なし。
'    System.IO.Packaging は WindowsBase.dll（.NET Framework 標準）に含まれる。
'    プロジェクトの参照に WindowsBase を追加するだけ。
' =====================================================================
Option Strict On
Option Explicit On

Imports System.Collections.Generic
Imports System.IO
Imports System.IO.Packaging
Imports System.Linq
Imports System.Text
Imports NPOI.SS.UserModel
Imports NPOI.XSSF.UserModel

#Region "検査結果"

Public Class IntegrityFinding
    Public Property Level As IssueLevel
    Public Property Message As String
End Class

Public Class IntegrityReport

    Public ReadOnly Property Findings As New List(Of IntegrityFinding)()

    ''' <summary>NPOI 通過で消えた OPC パート。</summary>
    Public ReadOnly Property LostParts As New List(Of String)()

    Public Property SheetsBefore As Integer
    Public Property SheetsAfter As Integer
    Public Property NamesBefore As Integer
    Public Property NamesAfter As Integer
    Public Property MergedBefore As Integer
    Public Property MergedAfter As Integer
    Public Property ShapesBefore As Integer
    Public Property ShapesAfter As Integer
    Public Property PicturesBefore As Integer
    Public Property PicturesAfter As Integer

    Public ReadOnly Property IsSafe As Boolean
        Get
            Return Not Findings.Any(Function(f) f.Level = IssueLevel.Error)
        End Get
    End Property

    Friend Sub Add(level As IssueLevel, message As String)
        Findings.Add(New IntegrityFinding With {.Level = level, .Message = message})
    End Sub

    Public Overrides Function ToString() As String
        Dim sb As New StringBuilder()

        If IsSafe AndAlso Findings.Count = 0 Then
            sb.AppendLine("この原本は問題なく処理できます。")
        Else
            sb.AppendLine("原本の検査結果")
            sb.AppendLine()
            For Each f In Findings.OrderByDescending(Function(x) x.Level)
                sb.Append(If(f.Level = IssueLevel.Error, "【使用不可】", "【注意】"))
                sb.AppendLine(f.Message)
            Next
        End If

        sb.AppendLine()
        sb.AppendLine("― 構造の比較（処理前 → 処理後）―")
        sb.AppendLine($"  シート数　　: {SheetsBefore} → {SheetsAfter}")
        sb.AppendLine($"  名前定義　　: {NamesBefore} → {NamesAfter}")
        sb.AppendLine($"  結合セル　　: {MergedBefore} → {MergedAfter}")
        sb.AppendLine($"  図形　　　　: {ShapesBefore} → {ShapesAfter}")
        sb.AppendLine($"  画像　　　　: {PicturesBefore} → {PicturesAfter}")

        Return sb.ToString()
    End Function

End Class

#End Region


Public NotInheritable Class TemplateIntegrityChecker

    Private Sub New()
    End Sub

    ''' <summary>
    ''' NPOI が扱えない／扱いが不完全な要素。原本に入っていたら警告する。
    ''' キーは OPC パート URI に含まれる文字列。
    ''' </summary>
    Private Shared ReadOnly RiskyParts As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
        {"/xl/charts/", "グラフ"},
        {"/xl/pivotTables/", "ピボットテーブル"},
        {"/xl/pivotCache/", "ピボットテーブルのキャッシュ"},
        {"/xl/slicers/", "スライサー"},
        {"/xl/slicerCaches/", "スライサーのキャッシュ"},
        {"/xl/timelines/", "タイムライン"},
        {"/xl/tables/", "テーブル（テーブルとして書式設定）"},
        {"/xl/activeX/", "ActiveX コントロール"},
        {"/xl/ctrlProps/", "フォームコントロール"},
        {"/xl/threadedComments/", "スレッド形式のコメント"},
        {"/xl/queryTables/", "クエリテーブル"},
        {"/xl/connections.xml", "外部データ接続"},
        {"/xl/richData/", "リッチデータ型（株価・地理など）"},
        {"/xl/metadata.xml", "セルメタデータ（動的配列数式など）"},
        {"/customXml/", "カスタム XML"},
        {"vbaProject.bin", "マクロ（VBA）"}
    }

    ''' <summary>
    ''' 原本を検査する。実際に NPOI で開いて書き出し、前後を突き合わせる。
    ''' </summary>
    Public Shared Function Check(templatePath As String) As IntegrityReport

        Dim report As New IntegrityReport()
        Dim tempOut = Path.Combine(Path.GetTempPath(),
                                   "tmplchk_" & Guid.NewGuid().ToString("N") & ".xlsx")

        Try
            ' --- 1) 処理前の中身を記録 ---
            Dim partsBefore = GetPartUris(templatePath)

            ' --- 2) 危険な要素が最初から入っていないか ---
            For Each kv In RiskyParts
                If partsBefore.Any(Function(p) p.IndexOf(kv.Key, StringComparison.OrdinalIgnoreCase) >= 0) Then
                    report.Add(IssueLevel.Warning,
                        $"原本に「{kv.Value}」が含まれています。処理時に消える、" &
                        "または表示が崩れる可能性があります。取り除くことを推奨します。")
                End If
            Next

            ' --- 3) 実際に NPOI を通す ---
            Try
                Using wb = OpenReadOnly(templatePath)
                    report.SheetsBefore = wb.NumberOfSheets
                    report.NamesBefore = wb.NumberOfNames
                    report.MergedBefore = CountMerged(wb)
                    report.ShapesBefore = CountShapes(wb)
                    report.PicturesBefore = wb.GetAllPictures().Count

                    Using fs As New FileStream(tempOut, FileMode.Create, FileAccess.Write)
                        wb.Write(fs, leaveOpen:=False)
                    End Using
                End Using
            Catch ex As Exception
                report.Add(IssueLevel.Error,
                    "この原本は読み込みまたは書き出しに失敗しました。使用できません。" &
                    vbCrLf & "　詳細: " & ex.Message)
                Return report
            End Try

            ' --- 4) 書き出したものを開き直せるか（Excel が開けるかの一次判定） ---
            Try
                Using wb2 = OpenReadOnly(tempOut)
                    report.SheetsAfter = wb2.NumberOfSheets
                    report.NamesAfter = wb2.NumberOfNames
                    report.MergedAfter = CountMerged(wb2)
                    report.ShapesAfter = CountShapes(wb2)
                    report.PicturesAfter = wb2.GetAllPictures().Count
                End Using
            Catch ex As Exception
                report.Add(IssueLevel.Error,
                    "処理後のファイルを開き直せませんでした。ファイルが破損しています。" &
                    vbCrLf & "　詳細: " & ex.Message)
                Return report
            End Try

            ' --- 5) パートの欠落 ---
            Dim partsAfter = GetPartUris(tempOut)
            Dim lost = partsBefore.Except(partsAfter, StringComparer.OrdinalIgnoreCase).ToList()
            report.LostParts.AddRange(lost)

            For Each p In lost
                Dim label = RiskyParts.FirstOrDefault(
                    Function(kv) p.IndexOf(kv.Key, StringComparison.OrdinalIgnoreCase) >= 0).Value

                If Not String.IsNullOrEmpty(label) Then
                    report.Add(IssueLevel.Error, $"「{label}」が処理によって失われます。原本から取り除いてください。")
                ElseIf p.IndexOf("/xl/", StringComparison.OrdinalIgnoreCase) >= 0 AndAlso
                       p.EndsWith(".xml", StringComparison.OrdinalIgnoreCase) Then
                    report.Add(IssueLevel.Warning, $"内部データ {p} が失われます。")
                End If
            Next

            ' --- 6) 構造の増減 ---
            CompareCount(report, "シート", report.SheetsBefore, report.SheetsAfter, IssueLevel.Error)
            CompareCount(report, "名前定義", report.NamesBefore, report.NamesAfter, IssueLevel.Error)
            CompareCount(report, "結合セル", report.MergedBefore, report.MergedAfter, IssueLevel.Warning)
            CompareCount(report, "図形", report.ShapesBefore, report.ShapesAfter, IssueLevel.Error)
            CompareCount(report, "画像", report.PicturesBefore, report.PicturesAfter, IssueLevel.Error)

        Finally
            Try
                If File.Exists(tempOut) Then File.Delete(tempOut)
            Catch
            End Try
        End Try

        Return report
    End Function

    Private Shared Sub CompareCount(r As IntegrityReport, label As String,
                                    before As Integer, after As Integer, level As IssueLevel)
        If before <> after Then
            r.Add(level, $"{label}の数が変化します（{before} → {after}）。")
        End If
    End Sub

    ''' <summary>OPC パッケージ内のパート一覧。NPOI を介さず生の構造を見る。</summary>
    Private Shared Function GetPartUris(path As String) As List(Of String)
        Dim list As New List(Of String)()
        Using pkg = Package.Open(path, FileMode.Open, FileAccess.Read)
            For Each part In pkg.GetParts()
                list.Add(part.Uri.ToString())
            Next
        End Using
        list.Sort(StringComparer.OrdinalIgnoreCase)
        Return list
    End Function

    Private Shared Function OpenReadOnly(path As String) As XSSFWorkbook
        Using fs As New FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)
            Return New XSSFWorkbook(fs)
        End Using
    End Function

    Private Shared Function CountMerged(wb As IWorkbook) As Integer
        Dim n = 0
        For i = 0 To wb.NumberOfSheets - 1
            n += wb.GetSheetAt(i).NumMergedRegions
        Next
        Return n
    End Function

    Private Shared Function CountShapes(wb As IWorkbook) As Integer
        Dim n = 0
        For i = 0 To wb.NumberOfSheets - 1
            Dim xs = TryCast(wb.GetSheetAt(i), XSSFSheet)
            If xs Is Nothing Then Continue For
            ' DrawingPatriarch は描画が無ければ null を返す（パートを作らない）
            Dim dr = TryCast(xs.DrawingPatriarch, XSSFDrawing)
            If dr IsNot Nothing Then n += dr.GetShapes().Count
        Next
        Return n
    End Function

End Class
