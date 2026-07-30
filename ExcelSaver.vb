' =====================================================================
'  ExcelSaver.vb   (VB.NET / .NET Framework 4.8 / NPOI 2.7.6)
'
'  NPOI で生成したブックを、業務で必要な各種パターンで保存する。
'
'  【押さえている実務上の要点】
'   1. 原子的書き込み
'        いきなり本番パスへ書かない。同一フォルダの一時ファイルへ書いてから
'        差し替える。途中で落ちても「新しいファイルが無い上に古いファイルも
'        壊れている」という最悪の状態を作らない。
'   2. ファイルロックの事前検知
'        「前回の出力を Excel で開いたまま再出力」が現場で最も多い失敗。
'        IOException をそのまま見せず、誰が開いているかまで伝える。
'   3. ファイル名のサニタイズ
'        得意先名や品名からファイル名を組むと必ず禁則文字を踏む。
' =====================================================================
Option Strict On
Option Explicit On

Imports System.Collections.Generic
Imports System.Diagnostics
Imports System.IO
Imports System.Linq
Imports System.Text
Imports System.Windows.Forms
Imports NPOI.SS.UserModel

#Region "設定・結果"

Public Enum FileExistsAction
    ''' <summary>確認せず上書き。バッチ出力向け。</summary>
    Overwrite
    ''' <summary>既に在れば例外。誤上書きを絶対に避けたい場合。</summary>
    Fail
    ''' <summary>ユーザーに確認する。対話操作向け。</summary>
    Confirm
    ''' <summary>連番を付けて別名にする（例: 受注一覧 (2).xlsx）。</summary>
    AutoNumber
    ''' <summary>日時を付けて別名にする（例: 受注一覧_20260730_143022.xlsx）。</summary>
    AppendTimestamp
End Enum

Public Class ExcelSaveOptions
    Public Property ExistsAction As FileExistsAction = FileExistsAction.Confirm

    ''' <summary>上書き時に旧ファイルを .bak として残す。</summary>
    Public Property CreateBackup As Boolean = False

    ''' <summary>読み取り専用属性が付いていても、確認の上で解除して上書きする。</summary>
    Public Property ClearReadOnly As Boolean = True

    ''' <summary>保存後に既定のアプリで開く。</summary>
    Public Property OpenAfterSave As Boolean = False

    ''' <summary>確認ダイアログの親ウィンドウ。</summary>
    Public Property Owner As IWin32Window
End Class

Public Class ExcelSaveResult
    Public Property Saved As Boolean
    Public Property Canceled As Boolean
    ''' <summary>実際に保存されたパス。連番や日時付与で変わることがある。</summary>
    Public Property FinalPath As String
    ''' <summary>要求されたパスと異なる名前で保存された。</summary>
    Public Property Renamed As Boolean
    ''' <summary>バックアップを作成した場合のパス。</summary>
    Public Property BackupPath As String
End Class

''' <summary>保存できない状態を、原因が分かる形で伝えるための例外。</summary>
Public Class ExcelSaveException
    Inherits Exception

    Public Sub New(message As String, Optional inner As Exception = Nothing)
        MyBase.New(message, inner)
    End Sub
End Class

#End Region


Public NotInheritable Class ExcelSaver

    Private Sub New()
    End Sub

#Region "保存"

    ''' <summary>指定パスへ保存する。</summary>
    Public Shared Function Save(wb As IWorkbook,
                                path As String,
                                Optional options As ExcelSaveOptions = Nothing) As ExcelSaveResult

        If wb Is Nothing Then Throw New ArgumentNullException(NameOf(wb))
        If String.IsNullOrWhiteSpace(path) Then Throw New ArgumentException("保存先が未指定です。", NameOf(path))

        If options Is Nothing Then options = New ExcelSaveOptions()

        Dim result As New ExcelSaveResult()
        Dim finalPath = Path.GetFullPath(path)

        ' ---------- 1) 既存ファイルの扱いを決める ----------
        If File.Exists(finalPath) Then
            Select Case options.ExistsAction

                Case FileExistsAction.Fail
                    Throw New ExcelSaveException(
                        "同名のファイルが既に存在します。" & vbCrLf & finalPath)

                Case FileExistsAction.Confirm
                    Dim answer = MessageBox.Show(options.Owner,
                        "同名のファイルが既に存在します。上書きしますか？" & vbCrLf & vbCrLf &
                        Path.GetFileName(finalPath),
                        "上書きの確認",
                        MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                        MessageBoxDefaultButton.Button2)

                    If answer <> DialogResult.Yes Then
                        result.Canceled = True
                        Return result
                    End If

                Case FileExistsAction.AutoNumber
                    finalPath = NextAvailablePath(finalPath)
                    result.Renamed = True

                Case FileExistsAction.AppendTimestamp
                    finalPath = AppendTimestamp(finalPath)
                    result.Renamed = True

                Case FileExistsAction.Overwrite
                    ' そのまま進む
            End Select
        End If

        ' ---------- 2) 書き込める状態か事前に確認 ----------
        EnsureWritable(finalPath, options)

        ' ---------- 3) 原子的に書き込む ----------
        result.BackupPath = WriteAtomic(wb, finalPath, options.CreateBackup)
        result.FinalPath = finalPath
        result.Saved = True

        ' ---------- 4) 後処理 ----------
        If options.OpenAfterSave Then
            Try
                Process.Start(New ProcessStartInfo(finalPath) With {.UseShellExecute = True})
            Catch
                ' 開けなくても保存は成功しているので握りつぶす
            End Try
        End If

        Return result
    End Function

    ''' <summary>
    ''' 「名前を付けて保存」ダイアログを出して保存する。
    ''' ダイアログ側で上書き確認が行われるので、ExistsAction は Overwrite で足りる。
    ''' </summary>
    Public Shared Function SaveAs(wb As IWorkbook,
                                  defaultFileName As String,
                                  Optional initialDirectory As String = Nothing,
                                  Optional options As ExcelSaveOptions = Nothing) As ExcelSaveResult

        If options Is Nothing Then options = New ExcelSaveOptions()

        Using dlg As New SaveFileDialog()
            dlg.Filter = "Excel ブック (*.xlsx)|*.xlsx|すべてのファイル (*.*)|*.*"
            dlg.DefaultExt = "xlsx"
            dlg.AddExtension = True
            dlg.OverwritePrompt = True          ' 上書き確認はダイアログに任せる
            dlg.FileName = SanitizeFileName(defaultFileName)

            If Not String.IsNullOrEmpty(initialDirectory) AndAlso Directory.Exists(initialDirectory) Then
                dlg.InitialDirectory = initialDirectory
            End If

            If dlg.ShowDialog(options.Owner) <> DialogResult.OK Then
                Return New ExcelSaveResult With {.Canceled = True}
            End If

            Dim opt = New ExcelSaveOptions With {
                .ExistsAction = FileExistsAction.Overwrite,
                .CreateBackup = options.CreateBackup,
                .ClearReadOnly = options.ClearReadOnly,
                .OpenAfterSave = options.OpenAfterSave,
                .Owner = options.Owner
            }
            Return Save(wb, dlg.FileName, opt)
        End Using
    End Function

    ''' <summary>
    ''' 出力フォルダへ、データから組んだ名前で自動保存する（バッチ向け）。
    ''' 名前は必ずサニタイズされる。
    ''' </summary>
    Public Shared Function SaveToFolder(wb As IWorkbook,
                                        folder As String,
                                        fileNameWithoutExt As String,
                                        Optional existsAction As FileExistsAction = FileExistsAction.Overwrite) As ExcelSaveResult

        Dim name = SanitizeFileName(fileNameWithoutExt) & ".xlsx"
        Return Save(wb, Path.Combine(folder, name),
                    New ExcelSaveOptions With {.ExistsAction = existsAction})
    End Function

#End Region


#Region "書き込み可否の判定"

    Private Shared Sub EnsureWritable(path As String, options As ExcelSaveOptions)

        Dim dir = Path.GetDirectoryName(path)
        If String.IsNullOrEmpty(dir) Then
            Throw New ExcelSaveException("保存先フォルダを特定できません。" & vbCrLf & path)
        End If

        ' フォルダが無ければ作る（ネットワーク断はここで露見する）
        Try
            If Not Directory.Exists(dir) Then Directory.CreateDirectory(dir)
        Catch ex As Exception
            Throw New ExcelSaveException(
                "保存先フォルダを作成できません。" & vbCrLf & dir & vbCrLf &
                "ネットワーク接続とアクセス権限を確認してください。", ex)
        End Try

        If Not File.Exists(path) Then Return

        ' --- 読み取り専用属性 ---
        Dim attr = File.GetAttributes(path)
        If (attr And FileAttributes.ReadOnly) = FileAttributes.ReadOnly Then
            If Not options.ClearReadOnly Then
                Throw New ExcelSaveException(
                    "ファイルが読み取り専用のため上書きできません。" & vbCrLf & path)
            End If

            Dim answer = MessageBox.Show(options.Owner,
                "ファイルが読み取り専用です。属性を解除して上書きしますか？" & vbCrLf & vbCrLf &
                Path.GetFileName(path),
                "確認", MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2)

            If answer <> DialogResult.Yes Then
                Throw New ExcelSaveException("読み取り専用のため保存を中止しました。")
            End If

            File.SetAttributes(path, attr And Not FileAttributes.ReadOnly)
        End If

        ' --- 他プロセスが開いているか ---
        If IsFileLocked(path) Then
            Dim who = TryGetExcelLockOwner(path)
            Dim sb As New StringBuilder()
            sb.AppendLine("ファイルが他のプログラムで開かれているため上書きできません。")
            sb.AppendLine()
            sb.AppendLine(Path.GetFileName(path))
            If Not String.IsNullOrEmpty(who) Then
                sb.AppendLine()
                sb.AppendLine("開いている可能性のあるユーザー: " & who)
            End If
            sb.AppendLine()
            sb.AppendLine("Excel で開いている場合は閉じてから再実行してください。")
            Throw New ExcelSaveException(sb.ToString())
        End If
    End Sub

    ''' <summary>他プロセスが排他的に握っているか。</summary>
    Public Shared Function IsFileLocked(path As String) As Boolean
        If Not File.Exists(path) Then Return False
        Try
            Using fs As New FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None)
            End Using
            Return False
        Catch ex As IOException
            Return True
        Catch ex As UnauthorizedAccessException
            ' 権限の問題はロックとは別。ここでは false を返し、
            ' 実書き込み時のエラーに委ねる。
            Return False
        End Try
    End Function

    ''' <summary>
    ''' Excel が作る一時ロックファイル（~$名前.xlsx）から開いているユーザー名を推定する。
    ''' フォーマットは非公開なのでベストエフォート。取れなければ Nothing。
    ''' 共有フォルダでは「誰が開いているか」が分かると問い合わせが激減する。
    ''' </summary>
    Public Shared Function TryGetExcelLockOwner(path As String) As String
        Try
            Dim dir = Path.GetDirectoryName(path)
            Dim lockFile = Path.Combine(dir, "~$" & Path.GetFileName(path))
            If Not File.Exists(lockFile) Then Return Nothing

            Dim bytes As Byte()
            Using fs As New FileStream(lockFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)
                bytes = New Byte(CInt(Math.Min(fs.Length, 512L)) - 1) {}
                fs.Read(bytes, 0, bytes.Length)
            End Using

            If bytes.Length < 2 Then Return Nothing

            ' 先頭バイトが名前の長さ。以降が UTF-16LE の場合と ANSI の場合がある
            Dim len As Integer = bytes(0)
            If len <= 0 Then Return Nothing

            Dim candidate As String = Nothing
            If 1 + len * 2 <= bytes.Length Then
                candidate = Encoding.Unicode.GetString(bytes, 1, len * 2)
            End If
            If String.IsNullOrWhiteSpace(candidate) OrElse candidate.Contains(vbNullChar) Then
                If 1 + len <= bytes.Length Then
                    candidate = Encoding.Default.GetString(bytes, 1, len)
                End If
            End If

            candidate = If(candidate, "").Trim().Trim(ChrW(0))
            Return If(String.IsNullOrWhiteSpace(candidate), Nothing, candidate)

        Catch
            Return Nothing
        End Try
    End Function

#End Region


#Region "原子的書き込み"

    ''' <summary>
    ''' 同一フォルダの一時ファイルへ書いてから差し替える。
    ''' 別ボリュームの一時フォルダを使うと差し替えが原子的にならないので、
    ''' 必ず保存先と同じフォルダを使う。
    ''' </summary>
    ''' <returns>バックアップを作成した場合そのパス。作らなければ Nothing。</returns>
    Private Shared Function WriteAtomic(wb As IWorkbook, finalPath As String, createBackup As Boolean) As String

        Dim dir = Path.GetDirectoryName(finalPath)
        Dim tmp = Path.Combine(dir, "~tmp_" & Guid.NewGuid().ToString("N").Substring(0, 8) & ".xlsx")
        Dim backupPath As String = Nothing

        Try
            Using fs As New FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None)
                wb.Write(fs, leaveOpen:=False)
            End Using

            If Not File.Exists(finalPath) Then
                File.Move(tmp, finalPath)
                Return Nothing
            End If

            If createBackup Then backupPath = finalPath & ".bak"

            Try
                ' File.Replace は差し替えを原子的に行う
                File.Replace(tmp, finalPath, backupPath, ignoreMetadataErrors:=True)
            Catch ex As PlatformNotSupportedException
                ' 一部の SMB 実装では Replace が使えないためフォールバック
                ReplaceFallback(tmp, finalPath, backupPath)
            Catch ex As IOException
                ReplaceFallback(tmp, finalPath, backupPath)
            End Try

            Return backupPath

        Catch ex As IOException
            Throw New ExcelSaveException(
                "ファイルの書き込みに失敗しました。" & vbCrLf & finalPath & vbCrLf & vbCrLf &
                "ファイルが開かれていないか、ディスクの空き容量とアクセス権限を確認してください。", ex)

        Catch ex As UnauthorizedAccessException
            Throw New ExcelSaveException(
                "保存先への書き込み権限がありません。" & vbCrLf & finalPath, ex)

        Finally
            If File.Exists(tmp) Then
                Try : File.Delete(tmp) : Catch : End Try
            End If
        End Try
    End Function

    Private Shared Sub ReplaceFallback(tmp As String, finalPath As String, backupPath As String)
        If Not String.IsNullOrEmpty(backupPath) Then
            If File.Exists(backupPath) Then File.Delete(backupPath)
            File.Move(finalPath, backupPath)
        Else
            File.Delete(finalPath)
        End If
        File.Move(tmp, finalPath)
    End Sub

#End Region


#Region "ファイル名"

    Private Shared ReadOnly ReservedNames As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    }

    ''' <summary>
    ''' DB のデータからファイル名を組むときに必ず通す。
    ''' 得意先名や品名には「/」「:」「*」などが平然と入っている。
    ''' </summary>
    Public Shared Function SanitizeFileName(name As String,
                                            Optional replacement As Char = "_"c) As String
        If String.IsNullOrWhiteSpace(name) Then Return "output"

        Dim sb As New StringBuilder(name.Length)
        Dim invalid = Path.GetInvalidFileNameChars()

        For Each c In name
            If invalid.Contains(c) OrElse Char.IsControl(c) Then
                sb.Append(replacement)
            Else
                sb.Append(c)
            End If
        Next

        ' Windows は末尾のドットと空白を黙って落とすため、先に除去する
        Dim result = sb.ToString().TrimEnd(" "c, "."c).Trim()

        If result.Length = 0 Then Return "output"

        ' デバイス名と衝突すると作成できない（CON.xlsx なども不可）
        Dim stem = Path.GetFileNameWithoutExtension(result)
        If ReservedNames.Contains(stem) Then result = "_" & result

        ' パス長対策。拡張子とフォルダ分を考えて余裕を持たせる
        Const maxLen As Integer = 120
        If result.Length > maxLen Then result = result.Substring(0, maxLen).TrimEnd(" "c, "."c)

        Return result
    End Function

    ''' <summary>受注一覧.xlsx → 受注一覧 (2).xlsx → 受注一覧 (3).xlsx …</summary>
    Public Shared Function NextAvailablePath(path As String) As String
        Dim dir = Path.GetDirectoryName(path)
        Dim stem = Path.GetFileNameWithoutExtension(path)
        Dim ext = Path.GetExtension(path)

        For i = 2 To 9999
            Dim candidate = Path.Combine(dir, $"{stem} ({i}){ext}")
            If Not File.Exists(candidate) Then Return candidate
        Next

        Throw New ExcelSaveException(
            "連番の上限に達したため保存先を決められません。出力フォルダを整理してください。")
    End Function

    ''' <summary>受注一覧.xlsx → 受注一覧_20260730_143022.xlsx</summary>
    Public Shared Function AppendTimestamp(path As String) As String
        Dim dir = Path.GetDirectoryName(path)
        Dim stem = Path.GetFileNameWithoutExtension(path)
        Dim ext = Path.GetExtension(path)
        Dim stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss")
        Return Path.Combine(dir, $"{stem}_{stamp}{ext}")
    End Function

#End Region

End Class


#Region "使用例"

Public Module SaveSample

    ''' <summary>対話操作: 「名前を付けて保存」</summary>
    Public Sub OnSaveAsClick(wb As IWorkbook, owner As Form)
        Dim r = ExcelSaver.SaveAs(wb, "受注一覧_" & Date.Today.ToString("yyyyMMdd"),
                                  initialDirectory:=Environment.GetFolderPath(
                                      Environment.SpecialFolder.MyDocuments),
                                  options:=New ExcelSaveOptions With {
                                      .Owner = owner,
                                      .OpenAfterSave = True
                                  })
        If r.Canceled Then Return
        ' r.FinalPath に保存済み
    End Sub

    ''' <summary>対話操作: 既定パスへ上書き（確認あり）</summary>
    Public Sub OnSaveClick(wb As IWorkbook, path As String, owner As Form)
        Try
            ExcelSaver.Save(wb, path, New ExcelSaveOptions With {
                .ExistsAction = FileExistsAction.Confirm,
                .CreateBackup = True,
                .Owner = owner
            })
        Catch ex As ExcelSaveException
            ' 原因が日本語で入っているのでそのまま見せられる
            MessageBox.Show(owner, ex.Message, "保存できません",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning)
        End Try
    End Sub

    ''' <summary>
    ''' バッチ出力: 確認ダイアログを出してはいけない。
    ''' 上書きか連番のどちらかを方針として決めておく。
    ''' </summary>
    Public Sub BatchExport(items As IEnumerable(Of String), folder As String)
        Dim failures As New List(Of String)()

        For Each key In items
            Try
                Dim wb = BuildWorkbook(key)
                ExcelSaver.SaveToFolder(wb, folder, $"明細_{key}",
                                        FileExistsAction.Overwrite)
            Catch ex As ExcelSaveException
                ' 1件の失敗で全体を止めない。最後にまとめて報告する
                failures.Add($"{key}: {ex.Message}")
            End Try
        Next

        If failures.Count > 0 Then
            ' ログ出力・レポート表示
        End If
    End Sub

    Private Function BuildWorkbook(key As String) As IWorkbook
        Return Nothing
    End Function

End Module

#End Region
