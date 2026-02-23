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

### 仕組み

```
┌─────────────────────────────────────────────────────────┐
│                    ログイン成功時                        │
├─────────────────────────────────────────────────────────┤
│  1. トークンを生成                                      │
│  2. DBのLOGIN_SESSIONSテーブルに登録                    │
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
      | **セキュリティ** | ○ 標準的 | ◎ より堅牢 |
| **実装難易度** | ○ 簡単 | △ やや複雑 |
| **DB負荷** | ◎ なし | △ ログイン時にDB問い合わせ |
| **強制ログアウト** | × 不可 | ◎ 可能（DB側でトークン無効化） |
| **複数端末制御** | × 不可 | ◎ 可能（1端末のみ許可など） |
| **オフライン利用** | ◎ 可能 | × 不可 |
| **推奨ケース** | 小規模・社内専用 | セキュリティ重視・管理機能必要 |

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

### 仕組み

```
┌─────────────────────────────────────────────────────────┐
│                    ログイン成功時                        │
├─────────────────────────────────────────────────────────┤
│  1. トークンを生成                                      │
│  2. DBのLOGIN_SESSIONSテーブルに登録                    │
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

## 共通: ログインフォームでの使用例

どちらの方式でも、呼び出し方はほぼ同じです。

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

---

## セキュリティ考慮事項

### 共通の対策

| 対策 | 説明 |
|------|------|
| **パスワード非保存** | パスワードは絶対にローカルに保存しない |
| **DPAPI暗号化** | Windows標準の暗号化。他ユーザーは復号不可 |
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

---

## ライセンス

このドキュメントおよびコードサンプルはMITライセンスで公開されています。

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2024-XX-XX | 初版作成 |
