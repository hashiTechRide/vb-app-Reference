# WinForms 自動ログイン機能 実装ガイド

.NET Framework 4.8 WinFormsアプリケーションで、Webアプリのような「一度ログインしたらその日は自動ログイン」を実現するための実装パターンをまとめています。

## 目次

- [概要](#概要)
- [方式比較](#方式比較)
- [方式1: ローカルトークン方式](#方式1-ローカルトークン方式)
- [方式2: DBトークン検証方式](#方式2-dbトークン検証方式)
- [方式3: 標準ライブラリのみ方式](#方式3-標準ライブラリのみ方式)
- [共通: ログインフォームでの使用例](#共通-ログインフォームでの使用例)
- [セキュリティ考慮事項](#セキュリティ考慮事項)
- [導入時のチェックリスト](#導入時のチェックリスト)

---

## 概要

### 解決したい課題

アプリを起動するたびにログインが必要で手間がかかる。Webアプリのように、一日の最初にログインすれば、その日は明示的にログアウトしない限り自動ログインしたい。

### 基本方針

- **パスワードは保存しない** - セキュリティリスクを避ける
- **認証トークンと有効期限を保存** - 当日中のみ有効
- **Windows DPAPIで暗号化** - 他ユーザーからの保護

---

## 方式比較

| 項目 | 方式1: ローカルトークン | 方式2: DBトークン検証 | 方式3: 標準ライブラリのみ |
|------|------------------------|----------------------|--------------------------|
| **概要** | ローカルファイルのみで完結 | DBでトークンを管理・検証 | NuGetパッケージ不要で完結 |
| **セキュリティ** | ○ 標準的 | ◎ より堅牢 | ○ 標準的 |
| **実装難易度** | ○ 簡単 | △ やや複雑 | ◎ 最も簡単 |
| **外部依存** | △ NuGetパッケージ必要 | △ NuGetパッケージ必要 | ◎ なし（標準ライブラリのみ） |
| **DB負荷** | ◎ なし | △ ログイン時にDB問い合わせ | ◎ なし |
| **強制ログアウト** | × 不可 | ◎ 可能（DB側でトークン無効化） | × 不可 |
| **複数端末制御** | × 不可 | ◎ 可能（1端末のみ許可など） | × 不可 |
| **オフライン利用** | ◎ 可能 | × 不可 | ◎ 可能 |
| **暗号化方式** | DPAPI（OS標準） | DPAPI（OS標準） | AES-256 + マシン固有鍵 |
| **推奨ケース** | 小規模・社内専用 | セキュリティ重視・管理機能必要 | NuGet制約あり・最小構成 |

---

## 方式1: ローカルトークン方式

ローカルファイルにセッション情報を暗号化して保存する方式。DBへの追加変更が不要で、最もシンプルに実装できます。

### 必要なNuGetパッケージ

```
System.Security.Cryptography.ProtectedData
```

### SessionManager クラス

```csharp
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace YourAppNamespace
{
    /// <summary>
    /// ローカルファイルベースのセッション管理クラス
    /// </summary>
    public static class LocalSessionManager
    {
        // セッションファイルの保存先
        private static readonly string TokenFilePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",  // ← アプリ名に変更
            "session.dat"
        );

        /// <summary>
        /// セッション情報
        /// </summary>
        private class SessionData
        {
            public string EmployeeId { get; set; }
            public string Token { get; set; }
            public DateTime ExpiresAt { get; set; }
            public string MachineId { get; set; }
        }

        /// <summary>
        /// ログイン成功時にセッションを保存
        /// </summary>
        /// <param name="employeeId">社員ID</param>
        public static void SaveSession(string employeeId)
        {
            var session = new SessionData
            {
                EmployeeId = employeeId,
                Token = GenerateToken(),
                ExpiresAt = GetEndOfToday(),
                MachineId = GetMachineId()
            };

            // ディレクトリがなければ作成
            var directory = Path.GetDirectoryName(TokenFilePath);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            // JSON化して暗号化して保存
            var json = JsonSerializer.Serialize(session);
            var encrypted = ProtectData(json);
            File.WriteAllBytes(TokenFilePath, encrypted);
        }

        /// <summary>
        /// 保存されたセッションで自動ログインを試行
        /// </summary>
        /// <returns>成功時は(true, 社員ID)、失敗時は(false, null)</returns>
        public static (bool isValid, string employeeId) TryAutoLogin()
        {
            try
            {
                // ファイルがなければ失敗
                if (!File.Exists(TokenFilePath))
                {
                    return (false, null);
                }

                // 復号化してデシリアライズ
                var encrypted = File.ReadAllBytes(TokenFilePath);
                var json = UnprotectData(encrypted);
                var session = JsonSerializer.Deserialize<SessionData>(json);

                // 有効期限チェック
                if (DateTime.Now > session.ExpiresAt)
                {
                    ClearSession();
                    return (false, null);
                }

                // 同一PCチェック（他PCへのコピー対策）
                if (session.MachineId != GetMachineId())
                {
                    ClearSession();
                    return (false, null);
                }

                return (true, session.EmployeeId);
            }
            catch (CryptographicException)
            {
                // 他ユーザーのファイルを読もうとした場合など
                ClearSession();
                return (false, null);
            }
            catch (Exception)
            {
                ClearSession();
                return (false, null);
            }
        }

        /// <summary>
        /// ログアウト時にセッションを削除
        /// </summary>
        public static void ClearSession()
        {
            try
            {
                if (File.Exists(TokenFilePath))
                {
                    File.Delete(TokenFilePath);
                }
            }
            catch
            {
                // 削除失敗は無視（次回有効期限切れで無効になる）
            }
        }

        #region Private Methods

        /// <summary>
        /// 今日の23:59:59を取得
        /// </summary>
        private static DateTime GetEndOfToday()
        {
            return DateTime.Today.AddDays(1).AddSeconds(-1);
        }

        /// <summary>
        /// ランダムなトークンを生成
        /// </summary>
        private static string GenerateToken()
        {
            var bytes = new byte[32];
            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }
            return Convert.ToBase64String(bytes);
        }

        /// <summary>
        /// PC識別子を取得
        /// </summary>
        private static string GetMachineId()
        {
            return $"{Environment.MachineName}_{Environment.UserName}";
        }

        /// <summary>
        /// Windows DPAPIで暗号化（現在のWindowsユーザーのみ復号可能）
        /// </summary>
        private static byte[] ProtectData(string data)
        {
            var bytes = Encoding.UTF8.GetBytes(data);
            return ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
        }

        /// <summary>
        /// Windows DPAPIで復号化
        /// </summary>
        private static string UnprotectData(byte[] encrypted)
        {
            var bytes = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }

        #endregion
    }
}
```

### SessionManager クラス（VB.NET版）

```vb
Imports System.IO
Imports System.Security.Cryptography
Imports System.Text
Imports System.Text.Json

Namespace YourAppNamespace

    ''' <summary>
    ''' ローカルファイルベースのセッション管理クラス
    ''' </summary>
    Public NotInheritable Class LocalSessionManager

        ' インスタンス化禁止
        Private Sub New()
        End Sub

        ' セッションファイルの保存先
        Private Shared ReadOnly TokenFilePath As String = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",
            "session.dat"
        )

        ''' <summary>
        ''' セッション情報
        ''' </summary>
        Private Class SessionData
            Public Property EmployeeId As String
            Public Property Token As String
            Public Property ExpiresAt As DateTime
            Public Property MachineId As String
        End Class

        ''' <summary>
        ''' ログイン成功時にセッションを保存
        ''' </summary>
        ''' <param name="employeeId">社員ID</param>
        Public Shared Sub SaveSession(employeeId As String)
            Dim session As New SessionData With {
                .EmployeeId = employeeId,
                .Token = GenerateToken(),
                .ExpiresAt = GetEndOfToday(),
                .MachineId = GetMachineId()
            }

            ' ディレクトリがなければ作成
            Dim directory As String = Path.GetDirectoryName(TokenFilePath)
            If Not IO.Directory.Exists(directory) Then
                IO.Directory.CreateDirectory(directory)
            End If

            ' JSON化して暗号化して保存
            Dim json As String = JsonSerializer.Serialize(session)
            Dim encrypted As Byte() = ProtectData(json)
            File.WriteAllBytes(TokenFilePath, encrypted)
        End Sub

        ''' <summary>
        ''' 保存されたセッションで自動ログインを試行
        ''' </summary>
        ''' <returns>成功時は(True, 社員ID)、失敗時は(False, Nothing)</returns>
        Public Shared Function TryAutoLogin() As (isValid As Boolean, employeeId As String)
            Try
                ' ファイルがなければ失敗
                If Not File.Exists(TokenFilePath) Then
                    Return (False, Nothing)
                End If

                ' 復号化してデシリアライズ
                Dim encrypted As Byte() = File.ReadAllBytes(TokenFilePath)
                Dim json As String = UnprotectData(encrypted)
                Dim session As SessionData = JsonSerializer.Deserialize(Of SessionData)(json)

                ' 有効期限チェック
                If DateTime.Now > session.ExpiresAt Then
                    ClearSession()
                    Return (False, Nothing)
                End If

                ' 同一PCチェック（他PCへのコピー対策）
                If session.MachineId <> GetMachineId() Then
                    ClearSession()
                    Return (False, Nothing)
                End If

                Return (True, session.EmployeeId)

            Catch ex As CryptographicException
                ' 他ユーザーのファイルを読もうとした場合など
                ClearSession()
                Return (False, Nothing)
            Catch ex As Exception
                ClearSession()
                Return (False, Nothing)
            End Try
        End Function

        ''' <summary>
        ''' ログアウト時にセッションを削除
        ''' </summary>
        Public Shared Sub ClearSession()
            Try
                If File.Exists(TokenFilePath) Then
                    File.Delete(TokenFilePath)
                End If
            Catch
                ' 削除失敗は無視（次回有効期限切れで無効になる）
            End Try
        End Sub

#Region "Private Methods"

        ''' <summary>
        ''' 今日の23:59:59を取得
        ''' </summary>
        Private Shared Function GetEndOfToday() As DateTime
            Return DateTime.Today.AddDays(1).AddSeconds(-1)
        End Function

        ''' <summary>
        ''' ランダムなトークンを生成
        ''' </summary>
        Private Shared Function GenerateToken() As String
            Dim bytes(31) As Byte
            Using rng = RandomNumberGenerator.Create()
                rng.GetBytes(bytes)
            End Using
            Return Convert.ToBase64String(bytes)
        End Function

        ''' <summary>
        ''' PC識別子を取得
        ''' </summary>
        Private Shared Function GetMachineId() As String
            Return $"{Environment.MachineName}_{Environment.UserName}"
        End Function

        ''' <summary>
        ''' Windows DPAPIで暗号化（現在のWindowsユーザーのみ復号可能）
        ''' </summary>
        Private Shared Function ProtectData(data As String) As Byte()
            Dim bytes As Byte() = Encoding.UTF8.GetBytes(data)
            Return ProtectedData.Protect(bytes, Nothing, DataProtectionScope.CurrentUser)
        End Function

        ''' <summary>
        ''' Windows DPAPIで復号化
        ''' </summary>
        Private Shared Function UnprotectData(encrypted As Byte()) As String
            Dim bytes As Byte() = ProtectedData.Unprotect(encrypted, Nothing, DataProtectionScope.CurrentUser)
            Return Encoding.UTF8.GetString(bytes)
        End Function

#End Region

    End Class

End Namespace
```

### 仕組み

```
┌─────────────────────────────────────────────────────────┐
│                    アプリ起動時                          │
├─────────────────────────────────────────────────────────┤
│  1. ローカルファイル（session.dat）を読み込み            │
│  2. Windows DPAPIで復号化                               │
│  3. 有効期限チェック（当日中か？）                       │
│  4. PC識別子チェック（同一PCか？）                       │
│  5. すべてOKなら自動ログイン成功                         │
└─────────────────────────────────────────────────────────┘
```

---

## 方式2: DBトークン検証方式

DBにトークンを保存し、アプリ起動時にDBと照合する方式。管理者による強制ログアウトや、複数端末からのログイン制御が可能です。

### 必要なDB変更

#### テーブル追加: LOGIN_SESSIONS

```sql
CREATE TABLE LOGIN_SESSIONS (
    SESSION_ID      VARCHAR2(64)  PRIMARY KEY,
    EMPLOYEE_ID     VARCHAR2(20)  NOT NULL,
    TOKEN           VARCHAR2(64)  NOT NULL,
    MACHINE_ID      VARCHAR2(100) NOT NULL,
    CREATED_AT      TIMESTAMP     DEFAULT SYSTIMESTAMP,
    EXPIRES_AT      TIMESTAMP     NOT NULL,
    IS_VALID        NUMBER(1)     DEFAULT 1,
    CONSTRAINT FK_LOGIN_SESSIONS_EMP 
        FOREIGN KEY (EMPLOYEE_ID) REFERENCES EMPLOYEES(EMPLOYEE_ID)
);

-- インデックス
CREATE INDEX IDX_LOGIN_SESSIONS_EMP ON LOGIN_SESSIONS(EMPLOYEE_ID);
CREATE INDEX IDX_LOGIN_SESSIONS_TOKEN ON LOGIN_SESSIONS(TOKEN);

-- 有効期限切れセッションを削除するジョブ（オプション）
-- 日次で実行することを推奨
DELETE FROM LOGIN_SESSIONS WHERE EXPIRES_AT < SYSTIMESTAMP;
```

### DbSessionManager クラス

```csharp
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Oracle.ManagedDataAccess.Client;

namespace YourAppNamespace
{
    /// <summary>
    /// DBトークン検証方式のセッション管理クラス
    /// </summary>
    public static class DbSessionManager
    {
        // ローカルキャッシュファイルの保存先
        private static readonly string CacheFilePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",
            "session_cache.dat"
        );

        // DB接続文字列（実際の環境に合わせて変更）
        private static readonly string ConnectionString = 
            "Data Source=YOUR_ORACLE;User Id=YOUR_USER;Password=YOUR_PASSWORD;";

        /// <summary>
        /// ローカルキャッシュ情報
        /// </summary>
        private class SessionCache
        {
            public string SessionId { get; set; }
            public string EmployeeId { get; set; }
            public string Token { get; set; }
            public string MachineId { get; set; }
        }

        /// <summary>
        /// ログイン成功時にセッションを作成
        /// </summary>
        /// <param name="employeeId">社員ID</param>
        public static void CreateSession(string employeeId)
        {
            var sessionId = Guid.NewGuid().ToString("N");
            var token = GenerateToken();
            var machineId = GetMachineId();
            var expiresAt = GetEndOfToday();

            // 同一社員の既存セッションを無効化（1端末のみ許可する場合）
            InvalidateExistingSessions(employeeId);

            // DBにセッション登録
            using (var conn = new OracleConnection(ConnectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = @"
                        INSERT INTO LOGIN_SESSIONS 
                            (SESSION_ID, EMPLOYEE_ID, TOKEN, MACHINE_ID, EXPIRES_AT, IS_VALID)
                        VALUES 
                            (:sessionId, :employeeId, :token, :machineId, :expiresAt, 1)";
                    
                    cmd.Parameters.Add(":sessionId", sessionId);
                    cmd.Parameters.Add(":employeeId", employeeId);
                    cmd.Parameters.Add(":token", token);
                    cmd.Parameters.Add(":machineId", machineId);
                    cmd.Parameters.Add(":expiresAt", expiresAt);
                    
                    cmd.ExecuteNonQuery();
                }
            }

            // ローカルにキャッシュ保存
            SaveLocalCache(new SessionCache
            {
                SessionId = sessionId,
                EmployeeId = employeeId,
                Token = token,
                MachineId = machineId
            });
        }

        /// <summary>
        /// 保存されたセッションで自動ログインを試行
        /// </summary>
        /// <returns>成功時は(true, 社員ID)、失敗時は(false, null)</returns>
        public static (bool isValid, string employeeId) TryAutoLogin()
        {
            try
            {
                // ローカルキャッシュを読み込み
                var cache = LoadLocalCache();
                if (cache == null)
                {
                    return (false, null);
                }

                // PC識別子チェック
                if (cache.MachineId != GetMachineId())
                {
                    ClearSession();
                    return (false, null);
                }

                // DBでトークン検証
                using (var conn = new OracleConnection(ConnectionString))
                {
                    conn.Open();
                    using (var cmd = conn.CreateCommand())
                    {
                        cmd.CommandText = @"
                            SELECT EMPLOYEE_ID 
                            FROM LOGIN_SESSIONS 
                            WHERE SESSION_ID = :sessionId 
                              AND TOKEN = :token 
                              AND MACHINE_ID = :machineId
                              AND EXPIRES_AT > SYSTIMESTAMP
                              AND IS_VALID = 1";
                        
                        cmd.Parameters.Add(":sessionId", cache.SessionId);
                        cmd.Parameters.Add(":token", cache.Token);
                        cmd.Parameters.Add(":machineId", cache.MachineId);

                        var result = cmd.ExecuteScalar();
                        
                        if (result != null)
                        {
                            return (true, result.ToString());
                        }
                    }
                }

                // DB検証失敗 → ローカルキャッシュも削除
                ClearSession();
                return (false, null);
            }
            catch (Exception)
            {
                // DB接続エラーなど → 通常ログインへ
                return (false, null);
            }
        }

        /// <summary>
        /// ログアウト時にセッションを削除
        /// </summary>
        public static void ClearSession()
        {
            var cache = LoadLocalCache();
            
            // DBのセッションを無効化
            if (cache != null)
            {
                try
                {
                    using (var conn = new OracleConnection(ConnectionString))
                    {
                        conn.Open();
                        using (var cmd = conn.CreateCommand())
                        {
                            cmd.CommandText = @"
                                UPDATE LOGIN_SESSIONS 
                                SET IS_VALID = 0 
                                WHERE SESSION_ID = :sessionId";
                            
                            cmd.Parameters.Add(":sessionId", cache.SessionId);
                            cmd.ExecuteNonQuery();
                        }
                    }
                }
                catch
                {
                    // DB更新失敗は無視
                }
            }

            // ローカルキャッシュを削除
            ClearLocalCache();
        }

        /// <summary>
        /// 管理者用: 指定社員のセッションを強制無効化
        /// </summary>
        /// <param name="employeeId">社員ID</param>
        public static void ForceLogout(string employeeId)
        {
            using (var conn = new OracleConnection(ConnectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = @"
                        UPDATE LOGIN_SESSIONS 
                        SET IS_VALID = 0 
                        WHERE EMPLOYEE_ID = :employeeId AND IS_VALID = 1";
                    
                    cmd.Parameters.Add(":employeeId", employeeId);
                    cmd.ExecuteNonQuery();
                }
            }
        }

        #region Private Methods

        /// <summary>
        /// 同一社員の既存セッションを無効化
        /// </summary>
        private static void InvalidateExistingSessions(string employeeId)
        {
            using (var conn = new OracleConnection(ConnectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = @"
                        UPDATE LOGIN_SESSIONS 
                        SET IS_VALID = 0 
                        WHERE EMPLOYEE_ID = :employeeId AND IS_VALID = 1";
                    
                    cmd.Parameters.Add(":employeeId", employeeId);
                    cmd.ExecuteNonQuery();
                }
            }
        }

        private static DateTime GetEndOfToday()
        {
            return DateTime.Today.AddDays(1).AddSeconds(-1);
        }

        private static string GenerateToken()
        {
            var bytes = new byte[32];
            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }
            return Convert.ToBase64String(bytes);
        }

        private static string GetMachineId()
        {
            return $"{Environment.MachineName}_{Environment.UserName}";
        }

        private static void SaveLocalCache(SessionCache cache)
        {
            var directory = Path.GetDirectoryName(CacheFilePath);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var json = JsonSerializer.Serialize(cache);
            var encrypted = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(json), 
                null, 
                DataProtectionScope.CurrentUser
            );
            File.WriteAllBytes(CacheFilePath, encrypted);
        }

        private static SessionCache LoadLocalCache()
        {
            if (!File.Exists(CacheFilePath))
            {
                return null;
            }

            try
            {
                var encrypted = File.ReadAllBytes(CacheFilePath);
                var bytes = ProtectedData.Unprotect(
                    encrypted, 
                    null, 
                    DataProtectionScope.CurrentUser
                );
                var json = Encoding.UTF8.GetString(bytes);
                return JsonSerializer.Deserialize<SessionCache>(json);
            }
            catch
            {
                return null;
            }
        }

        private static void ClearLocalCache()
        {
            try
            {
                if (File.Exists(CacheFilePath))
                {
                    File.Delete(CacheFilePath);
                }
            }
            catch
            {
                // 削除失敗は無視
            }
        }

        #endregion
    }
}
```

### DbSessionManager クラス（VB.NET版）

```vb
Imports System.IO
Imports System.Security.Cryptography
Imports System.Text
Imports System.Text.Json
Imports Oracle.ManagedDataAccess.Client

Namespace YourAppNamespace

    ''' <summary>
    ''' DBトークン検証方式のセッション管理クラス
    ''' </summary>
    Public NotInheritable Class DbSessionManager

        Private Sub New()
        End Sub

        ' ローカルキャッシュファイルの保存先
        Private Shared ReadOnly CacheFilePath As String = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",
            "session_cache.dat"
        )

        ' DB接続文字列（実際の環境に合わせて変更）
        Private Shared ReadOnly ConnectionString As String =
            "Data Source=YOUR_ORACLE;User Id=YOUR_USER;Password=YOUR_PASSWORD;"

        ''' <summary>
        ''' ローカルキャッシュ情報
        ''' </summary>
        Private Class SessionCache
            Public Property SessionId As String
            Public Property EmployeeId As String
            Public Property Token As String
            Public Property MachineId As String
        End Class

        ''' <summary>
        ''' ログイン成功時にセッションを作成
        ''' </summary>
        ''' <param name="employeeId">社員ID</param>
        Public Shared Sub CreateSession(employeeId As String)
            Dim sessionId As String = Guid.NewGuid().ToString("N")
            Dim token As String = GenerateToken()
            Dim machineId As String = GetMachineId()
            Dim expiresAt As DateTime = GetEndOfToday()

            ' 同一社員の既存セッションを無効化（1端末のみ許可する場合）
            InvalidateExistingSessions(employeeId)

            ' DBにセッション登録
            Using conn As New OracleConnection(ConnectionString)
                conn.Open()
                Using cmd = conn.CreateCommand()
                    cmd.CommandText = "
                        INSERT INTO LOGIN_SESSIONS 
                            (SESSION_ID, EMPLOYEE_ID, TOKEN, MACHINE_ID, EXPIRES_AT, IS_VALID)
                        VALUES 
                            (:sessionId, :employeeId, :token, :machineId, :expiresAt, 1)"

                    cmd.Parameters.Add(":sessionId", sessionId)
                    cmd.Parameters.Add(":employeeId", employeeId)
                    cmd.Parameters.Add(":token", token)
                    cmd.Parameters.Add(":machineId", machineId)
                    cmd.Parameters.Add(":expiresAt", expiresAt)

                    cmd.ExecuteNonQuery()
                End Using
            End Using

            ' ローカルにキャッシュ保存
            SaveLocalCache(New SessionCache With {
                .SessionId = sessionId,
                .EmployeeId = employeeId,
                .Token = token,
                .MachineId = machineId
            })
        End Sub

        ''' <summary>
        ''' 保存されたセッションで自動ログインを試行
        ''' </summary>
        ''' <returns>成功時は(True, 社員ID)、失敗時は(False, Nothing)</returns>
        Public Shared Function TryAutoLogin() As (isValid As Boolean, employeeId As String)
            Try
                ' ローカルキャッシュを読み込み
                Dim cache As SessionCache = LoadLocalCache()
                If cache Is Nothing Then
                    Return (False, Nothing)
                End If

                ' PC識別子チェック
                If cache.MachineId <> GetMachineId() Then
                    ClearSession()
                    Return (False, Nothing)
                End If

                ' DBでトークン検証
                Using conn As New OracleConnection(ConnectionString)
                    conn.Open()
                    Using cmd = conn.CreateCommand()
                        cmd.CommandText = "
                            SELECT EMPLOYEE_ID 
                            FROM LOGIN_SESSIONS 
                            WHERE SESSION_ID = :sessionId 
                              AND TOKEN = :token 
                              AND MACHINE_ID = :machineId
                              AND EXPIRES_AT > SYSTIMESTAMP
                              AND IS_VALID = 1"

                        cmd.Parameters.Add(":sessionId", cache.SessionId)
                        cmd.Parameters.Add(":token", cache.Token)
                        cmd.Parameters.Add(":machineId", cache.MachineId)

                        Dim result = cmd.ExecuteScalar()

                        If result IsNot Nothing Then
                            Return (True, result.ToString())
                        End If
                    End Using
                End Using

                ' DB検証失敗 → ローカルキャッシュも削除
                ClearSession()
                Return (False, Nothing)

            Catch ex As Exception
                ' DB接続エラーなど → 通常ログインへ
                Return (False, Nothing)
            End Try
        End Function

        ''' <summary>
        ''' ログアウト時にセッションを削除
        ''' </summary>
        Public Shared Sub ClearSession()
            Dim cache As SessionCache = LoadLocalCache()

            ' DBのセッションを無効化
            If cache IsNot Nothing Then
                Try
                    Using conn As New OracleConnection(ConnectionString)
                        conn.Open()
                        Using cmd = conn.CreateCommand()
                            cmd.CommandText = "
                                UPDATE LOGIN_SESSIONS 
                                SET IS_VALID = 0 
                                WHERE SESSION_ID = :sessionId"

                            cmd.Parameters.Add(":sessionId", cache.SessionId)
                            cmd.ExecuteNonQuery()
                        End Using
                    End Using
                Catch
                    ' DB更新失敗は無視
                End Try
            End If

            ' ローカルキャッシュを削除
            ClearLocalCache()
        End Sub

        ''' <summary>
        ''' 管理者用: 指定社員のセッションを強制無効化
        ''' </summary>
        ''' <param name="employeeId">社員ID</param>
        Public Shared Sub ForceLogout(employeeId As String)
            Using conn As New OracleConnection(ConnectionString)
                conn.Open()
                Using cmd = conn.CreateCommand()
                    cmd.CommandText = "
                        UPDATE LOGIN_SESSIONS 
                        SET IS_VALID = 0 
                        WHERE EMPLOYEE_ID = :employeeId AND IS_VALID = 1"

                    cmd.Parameters.Add(":employeeId", employeeId)
                    cmd.ExecuteNonQuery()
                End Using
            End Using
        End Sub

#Region "Private Methods"

        ''' <summary>
        ''' 同一社員の既存セッションを無効化
        ''' </summary>
        Private Shared Sub InvalidateExistingSessions(employeeId As String)
            Using conn As New OracleConnection(ConnectionString)
                conn.Open()
                Using cmd = conn.CreateCommand()
                    cmd.CommandText = "
                        UPDATE LOGIN_SESSIONS 
                        SET IS_VALID = 0 
                        WHERE EMPLOYEE_ID = :employeeId AND IS_VALID = 1"

                    cmd.Parameters.Add(":employeeId", employeeId)
                    cmd.ExecuteNonQuery()
                End Using
            End Using
        End Sub

        Private Shared Function GetEndOfToday() As DateTime
            Return DateTime.Today.AddDays(1).AddSeconds(-1)
        End Function

        Private Shared Function GenerateToken() As String
            Dim bytes(31) As Byte
            Using rng = RandomNumberGenerator.Create()
                rng.GetBytes(bytes)
            End Using
            Return Convert.ToBase64String(bytes)
        End Function

        Private Shared Function GetMachineId() As String
            Return $"{Environment.MachineName}_{Environment.UserName}"
        End Function

        Private Shared Sub SaveLocalCache(cache As SessionCache)
            Dim directory As String = Path.GetDirectoryName(CacheFilePath)
            If Not IO.Directory.Exists(directory) Then
                IO.Directory.CreateDirectory(directory)
            End If

            Dim json As String = JsonSerializer.Serialize(cache)
            Dim encrypted As Byte() = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(json),
                Nothing,
                DataProtectionScope.CurrentUser
            )
            File.WriteAllBytes(CacheFilePath, encrypted)
        End Sub

        Private Shared Function LoadLocalCache() As SessionCache
            If Not File.Exists(CacheFilePath) Then
                Return Nothing
            End If

            Try
                Dim encrypted As Byte() = File.ReadAllBytes(CacheFilePath)
                Dim bytes As Byte() = ProtectedData.Unprotect(
                    encrypted,
                    Nothing,
                    DataProtectionScope.CurrentUser
                )
                Dim json As String = Encoding.UTF8.GetString(bytes)
                Return JsonSerializer.Deserialize(Of SessionCache)(json)
            Catch
                Return Nothing
            End Try
        End Function

        Private Shared Sub ClearLocalCache()
            Try
                If File.Exists(CacheFilePath) Then
                    File.Delete(CacheFilePath)
                End If
            Catch
                ' 削除失敗は無視
            End Try
        End Sub

#End Region

    End Class

End Namespace
```

### 仕組み
│  3. ローカルにセッションIDとトークンをキャッシュ         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                    アプリ起動時                          │
├─────────────────────────────────────────────────────────┤
│  1. ローカルキャッシュを読み込み                         │
│  2. DBに問い合わせてトークン検証                         │
│     - セッションID一致？                                │
│     - トークン一致？                                    │
│     - 有効期限内？                                      │
│     - IS_VALID = 1？                                   │
│  3. すべてOKなら自動ログイン成功                         │
└─────────────────────────────────────────────────────────┘
```

---

## 方式3: 標準ライブラリのみ方式

NuGetパッケージを一切使わず、.NET Framework 4.8 の標準ライブラリだけで実装する方式。`System.Security.Cryptography.ProtectedData` が使えない環境や、NuGetの利用に制約がある場合に適しています。

### 必要なNuGetパッケージ

```
なし（すべて標準ライブラリで実装）
```

### 使用する標準ライブラリ

| 名前空間 | 用途 |
|----------|------|
| `System.Security.Cryptography` | AES暗号化、SHA256ハッシュ、乱数生成 |
| `System.IO` | ファイル読み書き |
| `System.Text` | エンコーディング |
| `System.Runtime.Serialization.Json` | JSONシリアライズ（`DataContractJsonSerializer`） |
| `System.Runtime.Serialization` | データコントラクト属性 |

### StdLibSessionManager クラス

```csharp
using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using System.Text;

namespace YourAppNamespace
{
    /// <summary>
    /// 標準ライブラリのみで実装するセッション管理クラス
    /// NuGetパッケージ不要。.NET Framework 4.8 標準のみ使用。
    /// </summary>
    public static class StdLibSessionManager
    {
        // セッションファイルの保存先
        private static readonly string TokenFilePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",  // ← アプリ名に変更
            "session.dat"
        );

        /// <summary>
        /// セッション情報（DataContract で JSON シリアライズ）
        /// </summary>
        [DataContract]
        private class SessionData
        {
            [DataMember] public string EmployeeId { get; set; }
            [DataMember] public string Token { get; set; }
            [DataMember] public long ExpiresAtTicks { get; set; }
            [DataMember] public string MachineId { get; set; }
        }

        /// <summary>
        /// ログイン成功時にセッションを保存
        /// </summary>
        /// <param name="employeeId">社員ID</param>
        public static void SaveSession(string employeeId)
        {
            var session = new SessionData
            {
                EmployeeId = employeeId,
                Token = GenerateToken(),
                ExpiresAtTicks = GetEndOfToday().Ticks,
                MachineId = GetMachineId()
            };

            // ディレクトリがなければ作成
            var directory = Path.GetDirectoryName(TokenFilePath);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            // JSON化して暗号化して保存
            var json = SerializeToJson(session);
            var encrypted = AesEncrypt(json, GetMachineKey());
            File.WriteAllBytes(TokenFilePath, encrypted);
        }

        /// <summary>
        /// 保存されたセッションで自動ログインを試行
        /// </summary>
        /// <returns>成功時は(true, 社員ID)、失敗時は(false, null)</returns>
        public static (bool isValid, string employeeId) TryAutoLogin()
        {
            try
            {
                // ファイルがなければ失敗
                if (!File.Exists(TokenFilePath))
                {
                    return (false, null);
                }

                // 復号化してデシリアライズ
                var encrypted = File.ReadAllBytes(TokenFilePath);
                var json = AesDecrypt(encrypted, GetMachineKey());
                var session = DeserializeFromJson(json);

                // 有効期限チェック
                var expiresAt = new DateTime(session.ExpiresAtTicks);
                if (DateTime.Now > expiresAt)
                {
                    ClearSession();
                    return (false, null);
                }

                // 同一PCチェック（他PCへのコピー対策）
                if (session.MachineId != GetMachineId())
                {
                    ClearSession();
                    return (false, null);
                }

                return (true, session.EmployeeId);
            }
            catch (CryptographicException)
            {
                // 復号失敗（鍵の不一致など）
                ClearSession();
                return (false, null);
            }
            catch (Exception)
            {
                ClearSession();
                return (false, null);
            }
        }

        /// <summary>
        /// ログアウト時にセッションを削除
        /// </summary>
        public static void ClearSession()
        {
            try
            {
                if (File.Exists(TokenFilePath))
                {
                    File.Delete(TokenFilePath);
                }
            }
            catch
            {
                // 削除失敗は無視（次回有効期限切れで無効になる）
            }
        }

        #region Private Methods

        /// <summary>
        /// 今日の23:59:59を取得
        /// </summary>
        private static DateTime GetEndOfToday()
        {
            return DateTime.Today.AddDays(1).AddSeconds(-1);
        }

        /// <summary>
        /// ランダムなトークンを生成
        /// </summary>
        private static string GenerateToken()
        {
            var bytes = new byte[32];
            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }
            return Convert.ToBase64String(bytes);
        }

        /// <summary>
        /// PC識別子を取得
        /// </summary>
        private static string GetMachineId()
        {
            return $"{Environment.MachineName}_{Environment.UserName}";
        }

        /// <summary>
        /// マシン固有の暗号化キーを生成（SHA256ハッシュ）
        /// マシン名 + ユーザー名 + 固定ソルトから256ビット鍵を導出
        /// </summary>
        private static byte[] GetMachineKey()
        {
            var source = $"{Environment.MachineName}_{Environment.UserName}_YourAppName_Salt";
            using (var sha256 = SHA256.Create())
            {
                return sha256.ComputeHash(Encoding.UTF8.GetBytes(source));
            }
        }

        /// <summary>
        /// AES-256-CBC で暗号化（IV はランダム生成し先頭に付加）
        /// </summary>
        private static byte[] AesEncrypt(string plainText, byte[] key)
        {
            using (var aes = Aes.Create())
            {
                aes.Key = key;
                aes.GenerateIV();
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;

                using (var encryptor = aes.CreateEncryptor())
                {
                    var plainBytes = Encoding.UTF8.GetBytes(plainText);
                    var cipherBytes = encryptor.TransformFinalBlock(plainBytes, 0, plainBytes.Length);

                    // IV（16バイト）+ 暗号文 を結合して返す
                    var result = new byte[aes.IV.Length + cipherBytes.Length];
                    Array.Copy(aes.IV, 0, result, 0, aes.IV.Length);
                    Array.Copy(cipherBytes, 0, result, aes.IV.Length, cipherBytes.Length);
                    return result;
                }
            }
        }

        /// <summary>
        /// AES-256-CBC で復号化（先頭16バイトをIVとして使用）
        /// </summary>
        private static string AesDecrypt(byte[] cipherData, byte[] key)
        {
            using (var aes = Aes.Create())
            {
                aes.Key = key;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;

                // 先頭16バイトをIVとして取り出す
                var iv = new byte[16];
                Array.Copy(cipherData, 0, iv, 0, 16);
                aes.IV = iv;

                var cipherBytes = new byte[cipherData.Length - 16];
                Array.Copy(cipherData, 16, cipherBytes, 0, cipherBytes.Length);

                using (var decryptor = aes.CreateDecryptor())
                {
                    var plainBytes = decryptor.TransformFinalBlock(cipherBytes, 0, cipherBytes.Length);
                    return Encoding.UTF8.GetString(plainBytes);
                }
            }
        }

        /// <summary>
        /// DataContractJsonSerializer で JSON シリアライズ
        /// </summary>
        private static string SerializeToJson(SessionData data)
        {
            var serializer = new DataContractJsonSerializer(typeof(SessionData));
            using (var ms = new MemoryStream())
            {
                serializer.WriteObject(ms, data);
                return Encoding.UTF8.GetString(ms.ToArray());
            }
        }

        /// <summary>
        /// DataContractJsonSerializer で JSON デシリアライズ
        /// </summary>
        private static SessionData DeserializeFromJson(string json)
        {
            var serializer = new DataContractJsonSerializer(typeof(SessionData));
            using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(json)))
            {
                return (SessionData)serializer.ReadObject(ms);
            }
        }

        #endregion
    }
}
```

### StdLibSessionManager クラス（VB.NET版）

```vb
Imports System.IO
Imports System.Runtime.Serialization
Imports System.Runtime.Serialization.Json
Imports System.Security.Cryptography
Imports System.Text

Namespace YourAppNamespace

    ''' <summary>
    ''' 標準ライブラリのみで実装するセッション管理クラス
    ''' NuGetパッケージ不要。.NET Framework 4.8 標準のみ使用。
    ''' </summary>
    Public NotInheritable Class StdLibSessionManager

        Private Sub New()
        End Sub

        ' セッションファイルの保存先
        Private Shared ReadOnly TokenFilePath As String = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAppName",
            "session.dat"
        )

        ''' <summary>
        ''' セッション情報（DataContract で JSON シリアライズ）
        ''' </summary>
        <DataContract>
        Private Class SessionData
            <DataMember> Public Property EmployeeId As String
            <DataMember> Public Property Token As String
            <DataMember> Public Property ExpiresAtTicks As Long
            <DataMember> Public Property MachineId As String
        End Class

        ''' <summary>
        ''' ログイン成功時にセッションを保存
        ''' </summary>
        ''' <param name="employeeId">社員ID</param>
        Public Shared Sub SaveSession(employeeId As String)
            Dim session As New SessionData With {
                .EmployeeId = employeeId,
                .Token = GenerateToken(),
                .ExpiresAtTicks = GetEndOfToday().Ticks,
                .MachineId = GetMachineId()
            }

            ' ディレクトリがなければ作成
            Dim directory As String = Path.GetDirectoryName(TokenFilePath)
            If Not IO.Directory.Exists(directory) Then
                IO.Directory.CreateDirectory(directory)
            End If

            ' JSON化して暗号化して保存
            Dim json As String = SerializeToJson(session)
            Dim encrypted As Byte() = AesEncrypt(json, GetMachineKey())
            File.WriteAllBytes(TokenFilePath, encrypted)
        End Sub

        ''' <summary>
        ''' 保存されたセッションで自動ログインを試行
        ''' </summary>
        ''' <returns>成功時は(True, 社員ID)、失敗時は(False, Nothing)</returns>
        Public Shared Function TryAutoLogin() As (isValid As Boolean, employeeId As String)
            Try
                ' ファイルがなければ失敗
                If Not File.Exists(TokenFilePath) Then
                    Return (False, Nothing)
                End If

                ' 復号化してデシリアライズ
                Dim encrypted As Byte() = File.ReadAllBytes(TokenFilePath)
                Dim json As String = AesDecrypt(encrypted, GetMachineKey())
                Dim session As SessionData = DeserializeFromJson(json)

                ' 有効期限チェック
                Dim expiresAt As New DateTime(session.ExpiresAtTicks)
                If DateTime.Now > expiresAt Then
                    ClearSession()
                    Return (False, Nothing)
                End If

                ' 同一PCチェック（他PCへのコピー対策）
                If session.MachineId <> GetMachineId() Then
                    ClearSession()
                    Return (False, Nothing)
                End If

                Return (True, session.EmployeeId)

            Catch ex As CryptographicException
                ' 復号失敗（鍵の不一致など）
                ClearSession()
                Return (False, Nothing)
            Catch ex As Exception
                ClearSession()
                Return (False, Nothing)
            End Try
        End Function

        ''' <summary>
        ''' ログアウト時にセッションを削除
        ''' </summary>
        Public Shared Sub ClearSession()
            Try
                If File.Exists(TokenFilePath) Then
                    File.Delete(TokenFilePath)
                End If
            Catch
                ' 削除失敗は無視（次回有効期限切れで無効になる）
            End Try
        End Sub

#Region "Private Methods"

        ''' <summary>
        ''' 今日の23:59:59を取得
        ''' </summary>
        Private Shared Function GetEndOfToday() As DateTime
            Return DateTime.Today.AddDays(1).AddSeconds(-1)
        End Function

        ''' <summary>
        ''' ランダムなトークンを生成
        ''' </summary>
        Private Shared Function GenerateToken() As String
            Dim bytes(31) As Byte
            Using rng = RandomNumberGenerator.Create()
                rng.GetBytes(bytes)
            End Using
            Return Convert.ToBase64String(bytes)
        End Function

        ''' <summary>
        ''' PC識別子を取得
        ''' </summary>
        Private Shared Function GetMachineId() As String
            Return $"{Environment.MachineName}_{Environment.UserName}"
        End Function

        ''' <summary>
        ''' マシン固有の暗号化キーを生成（SHA256ハッシュ）
        ''' マシン名 + ユーザー名 + 固定ソルトから256ビット鍵を導出
        ''' </summary>
        Private Shared Function GetMachineKey() As Byte()
            Dim source As String = $"{Environment.MachineName}_{Environment.UserName}_YourAppName_Salt"
            Using sha256 = SHA256.Create()
                Return sha256.ComputeHash(Encoding.UTF8.GetBytes(source))
            End Using
        End Function

        ''' <summary>
        ''' AES-256-CBC で暗号化（IV はランダム生成し先頭に付加）
        ''' </summary>
        Private Shared Function AesEncrypt(plainText As String, key As Byte()) As Byte()
            Using aes = System.Security.Cryptography.Aes.Create()
                aes.Key = key
                aes.GenerateIV()
                aes.Mode = CipherMode.CBC
                aes.Padding = PaddingMode.PKCS7

                Using encryptor = aes.CreateEncryptor()
                    Dim plainBytes As Byte() = Encoding.UTF8.GetBytes(plainText)
                    Dim cipherBytes As Byte() = encryptor.TransformFinalBlock(plainBytes, 0, plainBytes.Length)

                    ' IV（16バイト）+ 暗号文 を結合して返す
                    Dim result(aes.IV.Length + cipherBytes.Length - 1) As Byte
                    Array.Copy(aes.IV, 0, result, 0, aes.IV.Length)
                    Array.Copy(cipherBytes, 0, result, aes.IV.Length, cipherBytes.Length)
                    Return result
                End Using
            End Using
        End Function

        ''' <summary>
        ''' AES-256-CBC で復号化（先頭16バイトをIVとして使用）
        ''' </summary>
        Private Shared Function AesDecrypt(cipherData As Byte(), key As Byte()) As String
            Using aes = System.Security.Cryptography.Aes.Create()
                aes.Key = key
                aes.Mode = CipherMode.CBC
                aes.Padding = PaddingMode.PKCS7

                ' 先頭16バイトをIVとして取り出す
                Dim iv(15) As Byte
                Array.Copy(cipherData, 0, iv, 0, 16)
                aes.IV = iv

                Dim cipherBytes(cipherData.Length - 17) As Byte
                Array.Copy(cipherData, 16, cipherBytes, 0, cipherBytes.Length)

                Using decryptor = aes.CreateDecryptor()
                    Dim plainBytes As Byte() = decryptor.TransformFinalBlock(cipherBytes, 0, cipherBytes.Length)
                    Return Encoding.UTF8.GetString(plainBytes)
                End Using
            End Using
        End Function

        ''' <summary>
        ''' DataContractJsonSerializer で JSON シリアライズ
        ''' </summary>
        Private Shared Function SerializeToJson(data As SessionData) As String
            Dim serializer As New DataContractJsonSerializer(GetType(SessionData))
            Using ms As New MemoryStream()
                serializer.WriteObject(ms, data)
                Return Encoding.UTF8.GetString(ms.ToArray())
            End Using
        End Function

        ''' <summary>
        ''' DataContractJsonSerializer で JSON デシリアライズ
        ''' </summary>
        Private Shared Function DeserializeFromJson(json As String) As SessionData
            Dim serializer As New DataContractJsonSerializer(GetType(SessionData))
            Using ms As New MemoryStream(Encoding.UTF8.GetBytes(json))
                Return DirectCast(serializer.ReadObject(ms), SessionData)
            End Using
        End Function

#End Region

    End Class

End Namespace
```

### 仕組み
│  3. 有効期限チェック（当日中か？）                       │
│  4. PC識別子チェック（同一PCか？）                       │
│  5. すべてOKなら自動ログイン成功                         │
└─────────────────────────────────────────────────────────┘
```

### 方式1との違い

| 項目 | 方式1（DPAPI） | 方式3（AES） |
|------|----------------|--------------|
| **暗号化** | Windows DPAPI（OS任せ） | AES-256-CBC（自前実装） |
| **鍵管理** | OSが自動管理 | マシン名+ユーザー名から導出 |
| **NuGet** | `ProtectedData` パッケージ必要 | 不要 |
| **他ユーザー保護** | ◎ OS レベルで保護 | ○ 鍵が異なるため復号不可 |
| **JSONライブラリ** | `System.Text.Json`（NuGet） | `DataContractJsonSerializer`（標準） |

---

## 共通: ログインフォームでの使用例

どの方式でも、呼び出し方はほぼ同じです。

```csharp
public partial class LoginForm : Form
{
    public LoginForm()
    {
        InitializeComponent();
    }

    private void LoginForm_Load(object sender, EventArgs e)
    {
        // 起動時に自動ログインを試行
        var (isValid, employeeId) = LocalSessionManager.TryAutoLogin();
        // または
        // var (isValid, employeeId) = DbSessionManager.TryAutoLogin();
        // var (isValid, employeeId) = StdLibSessionManager.TryAutoLogin();
        
        if (isValid)
        {
            // 自動ログイン成功 → メイン画面へ
            ShowMainForm(employeeId);
            this.Close();
            return;
        }
        
        // 失敗した場合は通常のログイン画面を表示
    }

    private void btnLogin_Click(object sender, EventArgs e)
    {
        string employeeId = txtEmployeeId.Text.Trim();
        string password = txtPassword.Text;

        // 入力チェック
        if (string.IsNullOrEmpty(employeeId) || string.IsNullOrEmpty(password))
        {
            MessageBox.Show("社員IDとパスワードを入力してください。", 
                "入力エラー", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        // DB認証
        if (ValidateCredentials(employeeId, password))
        {
            // セッション保存
            LocalSessionManager.SaveSession(employeeId);
            // または
            // DbSessionManager.CreateSession(employeeId);
            // StdLibSessionManager.SaveSession(employeeId);
            
            ShowMainForm(employeeId);
            this.Close();
        }
        else
        {
            MessageBox.Show("社員IDまたはパスワードが正しくありません。", 
                "認証エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
            txtPassword.Clear();
            txtPassword.Focus();
        }
    }

    private void btnLogout_Click(object sender, EventArgs e)
    {
        // 明示的なログアウト
        LocalSessionManager.ClearSession();
        // または
        // DbSessionManager.ClearSession();
        // StdLibSessionManager.ClearSession();

        MessageBox.Show("ログアウトしました。", "完了", 
            MessageBoxButtons.OK, MessageBoxIcon.Information);
        
        // ログイン画面を再表示
        txtEmployeeId.Clear();
        txtPassword.Clear();
        txtEmployeeId.Focus();
    }

    /// <summary>
    /// DBで認証
    /// </summary>
    private bool ValidateCredentials(string employeeId, string password)
    {
        // 実際のDB認証処理を実装
        // パスワードはハッシュ化して比較することを推奨
        throw new NotImplementedException();
    }

    private void ShowMainForm(string employeeId)
    {
        var mainForm = new MainForm(employeeId);
        mainForm.Show();
    }
}
```

### ログインフォーム（VB.NET版）

```vb
Public Class LoginForm

    Private Sub LoginForm_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        ' 起動時に自動ログインを試行
        Dim result = LocalSessionManager.TryAutoLogin()
        ' または
        ' Dim result = DbSessionManager.TryAutoLogin()
        ' Dim result = StdLibSessionManager.TryAutoLogin()

        If result.isValid Then
            ' 自動ログイン成功 → メイン画面へ
            ShowMainForm(result.employeeId)
            Me.Close()
            Return
        End If

        ' 失敗した場合は通常のログイン画面を表示
    End Sub

    Private Sub btnLogin_Click(sender As Object, e As EventArgs) Handles btnLogin.Click
        Dim employeeId As String = txtEmployeeId.Text.Trim()
        Dim password As String = txtPassword.Text

        ' 入力チェック
        If String.IsNullOrEmpty(employeeId) OrElse String.IsNullOrEmpty(password) Then
            MessageBox.Show("社員IDとパスワードを入力してください。",
                "入力エラー", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If

        ' DB認証
        If ValidateCredentials(employeeId, password) Then
            ' セッション保存
            LocalSessionManager.SaveSession(employeeId)
            ' または
            ' DbSessionManager.CreateSession(employeeId)
            ' StdLibSessionManager.SaveSession(employeeId)

            ShowMainForm(employeeId)
            Me.Close()
        Else
            MessageBox.Show("社員IDまたはパスワードが正しくありません。",
                "認証エラー", MessageBoxButtons.OK, MessageBoxIcon.Error)
            txtPassword.Clear()
            txtPassword.Focus()
        End If
    End Sub

    Private Sub btnLogout_Click(sender As Object, e As EventArgs) Handles btnLogout.Click
        ' 明示的なログアウト
        LocalSessionManager.ClearSession()
        ' または
        ' DbSessionManager.ClearSession()
        ' StdLibSessionManager.ClearSession()

        MessageBox.Show("ログアウトしました。", "完了",
            MessageBoxButtons.OK, MessageBoxIcon.Information)

        ' ログイン画面を再表示
        txtEmployeeId.Clear()
        txtPassword.Clear()
        txtEmployeeId.Focus()
    End Sub

    ''' <summary>
    ''' DBで認証
    ''' </summary>
    Private Function ValidateCredentials(employeeId As String, password As String) As Boolean
        ' 実際のDB認証処理を実装
        ' パスワードはハッシュ化して比較することを推奨
        Throw New NotImplementedException()
    End Function

    Private Sub ShowMainForm(employeeId As String)
        Dim mainForm As New MainForm(employeeId)
        mainForm.Show()
    End Sub

End Class
```

---

## セキュリティ考慮事項

### 共通の対策

| 対策 | 説明 |
|------|------|
| **パスワード非保存** | パスワードは絶対にローカルに保存しない |
| **暗号化** | 方式1・2: Windows DPAPI / 方式3: AES-256-CBC |
| **有効期限** | 当日中のみ有効（カスタマイズ可能） |
| **PC識別** | 別PCにファイルをコピーしても使用不可 |
| **ランダムトークン** | 推測不可能な32バイトのトークン |

### 方式2（DB方式）の追加対策

| 対策 | 説明 |
|------|------|
| **DB側での無効化** | 管理者が強制ログアウト可能 |
| **複数端末制御** | 1社員1端末のみログイン許可 |
| **監査ログ** | ログイン履歴をDBで管理可能 |

### 注意事項

- **HTTPSでないDB通信**: 社内ネットワークでも可能であればTLS接続を推奨
- **トークンの長さ**: 32バイト（256ビット）以上を推奨
- **有効期限の調整**: 用途に応じて1日・1週間・1ヶ月などに変更可能

---

## 導入時のチェックリスト

### 方式1（ローカル方式）

- [ ] NuGetパッケージ `System.Security.Cryptography.ProtectedData` を追加
- [ ] `LocalSessionManager` クラスをプロジェクトに追加
- [ ] アプリ名（TokenFilePath内）を変更
- [ ] LoginForm に自動ログイン処理を追加
- [ ] ログアウトボタンに `ClearSession()` を追加

### 方式2（DB方式）

- [ ] NuGetパッケージを追加
  - [ ] `System.Security.Cryptography.ProtectedData`
  - [ ] `Oracle.ManagedDataAccess`
- [ ] DBに `LOGIN_SESSIONS` テーブルを作成
- [ ] `DbSessionManager` クラスをプロジェクトに追加
- [ ] 接続文字列を変更
- [ ] LoginForm に自動ログイン処理を追加
- [ ] ログアウトボタンに `ClearSession()` を追加
- [ ] （オプション）有効期限切れセッション削除ジョブを設定

### 方式3（標準ライブラリのみ方式）

- [ ] `StdLibSessionManager` クラスをプロジェクトに追加
- [ ] アプリ名（TokenFilePath内）を変更
- [ ] `GetMachineKey()` 内のソルト文字列をアプリ固有の値に変更
- [ ] LoginForm に自動ログイン処理を追加
- [ ] ログアウトボタンに `ClearSession()` を追加

---

## ライセンス

このドキュメントおよびコードサンプルはMITライセンスで公開されています。

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2024-XX-XX | 初版作成 |
| 2024-XX-XX | 方式3（標準ライブラリのみ方式）を追加、ドキュメント構造を整理 |
| 2024-XX-XX | 全方式・ログインフォーム例に VB.NET 版コードを追加 |
