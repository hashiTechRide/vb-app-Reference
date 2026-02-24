# .NET Framework 4.8 SQLファイル埋め込み＆バインド変数NULL対応ガイド

## 目次

1. [はじめに](#はじめに)
2. [SQLファイルを埋め込みリソースとしてビルドに取り込む](#sqlファイルを埋め込みリソースとしてビルドに取り込む)
3. [バインド変数（パラメータクエリ）の基本](#バインド変数パラメータクエリの基本)
4. [NULLを扱う際の基本ルール](#nullを扱う際の基本ルール)
5. [SELECT文でのNULL対応](#select文でのnull対応)
6. [UPDATE文でのNULL対応](#update文でのnull対応)
7. [MERGE文でのNULL対応](#merge文でのnull対応)
8. [共通ヘルパークラスの実装例](#共通ヘルパークラスの実装例)
9. [よくあるハマりどころと対策](#よくあるハマりどころと対策)
10. [関連知識：知っておくと役立つポイント](#関連知識知っておくと役立つポイント)
11. [C# と VB.NET の構文対応早見表](#c-と-vbnet-の構文対応早見表)

---

## はじめに

本ドキュメントでは、.NET Framework 4.8 の環境において以下を実現する方法を解説します。

- SQLファイル（`.sql`）をプロジェクトに埋め込み、コンパイル時にアセンブリに取り込む
- バインド変数（パラメータ化クエリ）を使用してSQLを実行する
- SELECT / UPDATE / MERGE 各文において `NULL` を正しく扱う

対象データベースは **SQL Server** を想定しています。
コード例は **C#** と **VB.NET** の両方を掲載しています。

---

## SQLファイルを埋め込みリソースとしてビルドに取り込む

### 手順

#### ステップ1：プロジェクトにSQLファイルを追加する

プロジェクト内に `Queries` フォルダなどを作成し、`.sql` ファイルを配置します。

**C# プロジェクトの場合：**
```
MyProject/
├── Queries/
│   ├── SelectUsers.sql
│   ├── UpdateUser.sql
│   └── MergeUser.sql
├── Helpers/
│   └── SqlHelper.cs
└── Program.cs
```

**VB.NET プロジェクトの場合：**
```
MyProject/
├── Queries/
│   ├── SelectUsers.sql
│   ├── UpdateUser.sql
│   └── MergeUser.sql
├── Helpers/
│   └── SqlHelper.vb
└── Program.vb
```

#### ステップ2：ビルドアクションを「埋め込みリソース」に設定する

1. ソリューションエクスプローラーで `.sql` ファイルを右クリック → **プロパティ**
2. **ビルドアクション** を `埋め込みリソース (Embedded Resource)` に変更
3. **出力ディレクトリにコピー** は `コピーしない` でOK

> **補足：ビルドアクションの選択肢の違い**
>
> | ビルドアクション | 説明 |
> |---|---|
> | `なし (None)` | ビルドに含まれない |
> | `コンテンツ (Content)` | 出力フォルダにコピーされる（外部ファイルとして配布） |
> | `埋め込みリソース (Embedded Resource)` | **アセンブリ（DLL/EXE）内部に格納される** |

埋め込みリソースを選択すると、SQLファイルがアセンブリ内に含まれるため、実行時に外部ファイルを配置する必要がなくなります。改ざん防止や配布の簡素化にもつながります。

#### ステップ3：コードから埋め込みリソースを読み出す

**C#**

```csharp
using System.IO;
using System.Reflection;

public static class SqlResourceLoader
{
    /// <summary>
    /// 埋め込みリソースからSQLを読み出す
    /// </summary>
    /// <param name="resourceName">
    /// 完全修飾リソース名（例: "MyProject.Queries.SelectUsers.sql"）
    /// </param>
    public static string Load(string resourceName)
    {
        var assembly = Assembly.GetExecutingAssembly();

        using (var stream = assembly.GetManifestResourceStream(resourceName))
        {
            if (stream == null)
            {
                // デバッグ用：存在するリソース名を列挙
                var names = assembly.GetManifestResourceNames();
                throw new FileNotFoundException(
                    $"リソース '{resourceName}' が見つかりません。" +
                    $"登録済みリソース: {string.Join(", ", names)}");
            }

            using (var reader = new StreamReader(stream))
            {
                return reader.ReadToEnd();
            }
        }
    }
}
```

**VB.NET**

```vb
Imports System.IO
Imports System.Reflection

Public Class SqlResourceLoader

    ''' <summary>
    ''' 埋め込みリソースからSQLを読み出す
    ''' </summary>
    ''' <param name="resourceName">
    ''' 完全修飾リソース名（例: "MyProject.Queries.SelectUsers.sql"）
    ''' </param>
    Public Shared Function Load(resourceName As String) As String
        Dim asm As Assembly = Assembly.GetExecutingAssembly()

        Using stream As Stream = asm.GetManifestResourceStream(resourceName)
            If stream Is Nothing Then
                ' デバッグ用：存在するリソース名を列挙
                Dim names() As String = asm.GetManifestResourceNames()
                Throw New FileNotFoundException(
                    $"リソース '{resourceName}' が見つかりません。" &
                    $"登録済みリソース: {String.Join(", ", names)}")
            End If

            Using reader As New StreamReader(stream)
                Return reader.ReadToEnd()
            End Using
        End Using
    End Function

End Class
```

#### リソース名の命名規則

リソース名は以下のルールで自動的に決まります。

```
<デフォルト名前空間>.<フォルダパス（.区切り）>.<ファイル名>
```

例：デフォルト名前空間が `MyProject`、ファイルパスが `Queries/SelectUsers.sql` の場合

```
MyProject.Queries.SelectUsers.sql
```

> **VB.NET での注意点：ルート名前空間**
>
> VB.NET ではプロジェクトプロパティに「ルート名前空間」の設定があります。
> リソース名はこのルート名前空間を基準に決まります。
> C# とは異なり、ソースファイル内の `Namespace` 宣言はリソース名に影響しません。
>
> 確認方法：プロジェクトのプロパティ → アプリケーション → ルート名前空間

> **Tips：リソース名が分からないとき**
>
> **C#**
> ```csharp
> // 全リソース名を出力して確認
> foreach (var name in Assembly.GetExecutingAssembly().GetManifestResourceNames())
> {
>     Console.WriteLine(name);
> }
> ```
>
> **VB.NET**
> ```vb
> ' 全リソース名を出力して確認
> For Each name As String In Assembly.GetExecutingAssembly().GetManifestResourceNames()
>     Console.WriteLine(name)
> Next
> ```

---

## バインド変数（パラメータクエリ）の基本

### なぜバインド変数を使うのか

| 観点 | 文字列連結 | バインド変数（パラメータ化） |
|---|---|---|
| SQLインジェクション | **脆弱** | **安全** |
| 実行プランキャッシュ | クエリごとに別プランになる | パラメータ違いでもプラン再利用 |
| 可読性・保守性 | 低い | 高い |
| NULL の扱い | 煩雑（文字列 "NULL" を組み立てる） | `DBNull.Value` で統一的に扱える |

### 基本的な使い方

**C#**

```csharp
using (var conn = new SqlConnection(connectionString))
using (var cmd = new SqlCommand())
{
    conn.Open();
    cmd.Connection = conn;
    cmd.CommandText = SqlResourceLoader.Load("MyProject.Queries.SelectUsers.sql");

    cmd.Parameters.Add(new SqlParameter("@Id", SqlDbType.Int) { Value = 1 });

    using (var reader = cmd.ExecuteReader())
    {
        while (reader.Read())
        {
            // データ読み出し
        }
    }
}
```

**VB.NET**

```vb
Using conn As New SqlConnection(connectionString)
    Using cmd As New SqlCommand()
        conn.Open()
        cmd.Connection = conn
        cmd.CommandText = SqlResourceLoader.Load("MyProject.Queries.SelectUsers.sql")

        cmd.Parameters.Add(New SqlParameter("@Id", SqlDbType.Int) With {.Value = 1})

        Using reader As SqlDataReader = cmd.ExecuteReader()
            Do While reader.Read()
                ' データ読み出し
            Loop
        End Using
    End Using
End Using
```

---

## NULLを扱う際の基本ルール

### ルール1：C# の null / VB.NET の Nothing ではなく DBNull.Value を使う

`SqlParameter.Value` に C# の `null` や VB.NET の `Nothing` を設定すると、パラメータ自体が「未設定」扱いになり、SQL Server 側でエラーになります。

**C#**

```csharp
// NG — パラメータ未指定エラーになる
param.Value = null;

// OK — SQL上で NULL として扱われる
param.Value = DBNull.Value;
```

**VB.NET**

```vb
' NG — パラメータ未指定エラーになる
param.Value = Nothing

' OK — SQL上で NULL として扱われる
param.Value = DBNull.Value
```

### ルール2：SqlDbType を明示的に指定する

`Value` が `DBNull.Value` のとき、型の自動推論ができません。必ず `SqlDbType` を指定してください。

**C#**

```csharp
// NG — 型が推論できない
new SqlParameter("@Name", DBNull.Value);

// OK — 型を明示
new SqlParameter("@Name", SqlDbType.NVarChar) { Value = DBNull.Value };
```

**VB.NET**

```vb
' NG — 型が推論できない
New SqlParameter("@Name", DBNull.Value)

' OK — 型を明示
New SqlParameter("@Name", SqlDbType.NVarChar) With {.Value = DBNull.Value}
```

### ルール3：NULLの用途によってSQL側の書き方が変わる

| 用途 | SQL側の対処 | 説明 |
|---|---|---|
| 列に NULL を代入したい | `SET Column = @Param` | そのまま。`DBNull.Value` が NULL として書き込まれる |
| NULL のとき条件を無視したい | `WHERE (@Param IS NULL OR Column = @Param)` | パラメータが NULL なら全行マッチ |
| NULL の行を検索したい | `WHERE Column IS NULL` | バインド変数では `= NULL` は使えない |

---

## SELECT文でのNULL対応

### パターン1：NULLのときは条件を無視する（動的検索）

ユーザーが検索条件を入力しなかった項目を無視する、よくある検索画面のパターンです。

**SelectUsers.sql**

```sql
SELECT
    Id,
    Name,
    Email,
    Age,
    DepartmentId
FROM
    Users
WHERE
    (@Name         IS NULL OR Name         = @Name)
    AND (@Age      IS NULL OR Age          = @Age)
    AND (@DeptId   IS NULL OR DepartmentId = @DeptId)
ORDER BY
    Id
```

**C# 側**

```csharp
string sql = SqlResourceLoader.Load("MyProject.Queries.SelectUsers.sql");

using (var conn = new SqlConnection(connectionString))
using (var cmd = new SqlCommand(sql, conn))
{
    // ユーザーが入力しなかった項目は null を渡す → 条件無視
    cmd.Parameters.Add(new SqlParameter("@Name",   SqlDbType.NVarChar, 100) { Value = (object)inputName ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@Age",    SqlDbType.Int)           { Value = (object)inputAge  ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@DeptId", SqlDbType.Int)           { Value = (object)inputDept ?? DBNull.Value });

    conn.Open();
    using (var reader = cmd.ExecuteReader())
    {
        while (reader.Read())
        {
            // 結果の読み出し
        }
    }
}
```

**VB.NET 側**

```vb
Dim sql As String = SqlResourceLoader.Load("MyProject.Queries.SelectUsers.sql")

Using conn As New SqlConnection(connectionString)
    Using cmd As New SqlCommand(sql, conn)
        ' ユーザーが入力しなかった項目は Nothing を渡す → 条件無視
        cmd.Parameters.Add(New SqlParameter("@Name",   SqlDbType.NVarChar, 100) With {
            .Value = If(inputName, DirectCast(DBNull.Value, Object))
        })
        cmd.Parameters.Add(New SqlParameter("@Age",    SqlDbType.Int) With {
            .Value = If(inputAge.HasValue, DirectCast(inputAge.Value, Object), DBNull.Value)
        })
        cmd.Parameters.Add(New SqlParameter("@DeptId", SqlDbType.Int) With {
            .Value = If(inputDept.HasValue, DirectCast(inputDept.Value, Object), DBNull.Value)
        })

        conn.Open()
        Using reader As SqlDataReader = cmd.ExecuteReader()
            Do While reader.Read()
                ' 結果の読み出し
            Loop
        End Using
    End Using
End Using
```

> **VB.NET での注意点：If 演算子と IIf 関数の違い**
>
> | 構文 | 評価方式 | NULL安全性 |
> |---|---|---|
> | `If(条件, 値A, 値B)` | **短絡評価（推奨）** | 条件が True なら値Bは評価されない |
> | `IIf(条件, 値A, 値B)` | **両方を評価する** | 両辺が評価されるため、NullReferenceException のリスクあり |
>
> バインド変数のNULL変換には必ず **`If` 演算子** を使ってください。

> **注意：パフォーマンスへの影響**
>
> `@Param IS NULL OR Column = @Param` パターンは「パラメータスニッフィング問題」を起こすことがあります。
> SQL Server が最初の実行時のパラメータ値に基づいて実行プランをキャッシュするため、NULL で実行された後に
> 具体的な値で実行すると最適でないプランが使われることがあります。
>
> **対策：**
> - クエリヒントに `OPTION (RECOMPILE)` を付ける（小～中規模のクエリ向け）
> - 動的SQLを使う（大規模・高頻度の場合）

### パターン2：NULL の行を明示的に検索したい

```sql
-- Column が NULL の行を取得（バインド変数では不可。直接 IS NULL を使う）
SELECT * FROM Users WHERE Email IS NULL
```

`WHERE Email = @Email` で `@Email` に `DBNull.Value` を渡しても **マッチしません**。SQL の仕様で `NULL = NULL` は `UNKNOWN`（偽と同等）になるためです。

NULL の行も検索対象にしたい場合は以下のようにします。

```sql
WHERE (@Email IS NULL AND Email IS NULL)
   OR (Email = @Email)
```

---

## UPDATE文でのNULL対応

UPDATE 文では、バインド変数に `DBNull.Value` を渡すとそのまま列に `NULL` が書き込まれます。

**UpdateUser.sql**

```sql
UPDATE Users
SET
    Name           = @Name,
    Email          = @Email,
    Age            = @Age,
    DepartmentId   = @DepartmentId,
    UpdatedAt      = GETDATE()
WHERE
    Id = @Id
```

**C# 側**

```csharp
string sql = SqlResourceLoader.Load("MyProject.Queries.UpdateUser.sql");

using (var conn = new SqlConnection(connectionString))
using (var cmd = new SqlCommand(sql, conn))
{
    cmd.Parameters.Add(new SqlParameter("@Id",     SqlDbType.Int)           { Value = userId });
    cmd.Parameters.Add(new SqlParameter("@Name",   SqlDbType.NVarChar, 100) { Value = (object)name  ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@Email",  SqlDbType.NVarChar, 256) { Value = (object)email ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@Age",    SqlDbType.Int)           { Value = (object)age   ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@DeptId", SqlDbType.Int)           { Value = (object)deptId ?? DBNull.Value });

    conn.Open();
    int affected = cmd.ExecuteNonQuery();
}
```

**VB.NET 側**

```vb
Dim sql As String = SqlResourceLoader.Load("MyProject.Queries.UpdateUser.sql")

Using conn As New SqlConnection(connectionString)
    Using cmd As New SqlCommand(sql, conn)
        cmd.Parameters.Add(New SqlParameter("@Id",     SqlDbType.Int) With {.Value = userId})
        cmd.Parameters.Add(New SqlParameter("@Name",   SqlDbType.NVarChar, 100) With {
            .Value = If(name, DirectCast(DBNull.Value, Object))
        })
        cmd.Parameters.Add(New SqlParameter("@Email",  SqlDbType.NVarChar, 256) With {
            .Value = If(email, DirectCast(DBNull.Value, Object))
        })
        cmd.Parameters.Add(New SqlParameter("@Age",    SqlDbType.Int) With {
            .Value = If(age.HasValue, DirectCast(age.Value, Object), DBNull.Value)
        })
        cmd.Parameters.Add(New SqlParameter("@DeptId", SqlDbType.Int) With {
            .Value = If(deptId.HasValue, DirectCast(deptId.Value, Object), DBNull.Value)
        })

        conn.Open()
        Dim affected As Integer = cmd.ExecuteNonQuery()
    End Using
End Using
```

### 部分更新（NULL のときは更新しない）

一部の列だけ更新し、NULL が渡された列は元の値を維持したい場合は `COALESCE` を使います。

```sql
UPDATE Users
SET
    Name         = COALESCE(@Name,   Name),      -- @Name が NULL なら現在値を維持
    Email        = COALESCE(@Email,  Email),
    Age          = COALESCE(@Age,    Age),
    UpdatedAt    = GETDATE()
WHERE
    Id = @Id
```

> **注意：** この方法では「意図的に NULL をセットしたい」ケースに対応できません。
> その場合は「更新するかどうか」を示す別のフラグパラメータを用意するか、
> NULL 代入用の別のSQLを用意する設計が必要です。

---

## MERGE文でのNULL対応

MERGE 文は INSERT と UPDATE を1文で実行できる構文です。NULL の扱いは INSERT / UPDATE と同じですが、1文に両方含まれるため注意が必要です。

**MergeUser.sql**

```sql
MERGE INTO Users AS tgt
USING (
    SELECT
        @Id             AS Id,
        @Name           AS Name,
        @Email          AS Email,
        @Age            AS Age,
        @DepartmentId   AS DepartmentId
) AS src
ON tgt.Id = src.Id

WHEN MATCHED THEN
    UPDATE SET
        Name           = src.Name,
        Email          = src.Email,
        Age            = src.Age,
        DepartmentId   = src.DepartmentId,
        UpdatedAt      = GETDATE()

WHEN NOT MATCHED THEN
    INSERT (Id, Name, Email, Age, DepartmentId, CreatedAt, UpdatedAt)
    VALUES (src.Id, src.Name, src.Email, src.Age, src.DepartmentId, GETDATE(), GETDATE())
;  -- ← MERGE文は必ずセミコロンで終端すること！
```

**C# 側**

```csharp
string sql = SqlResourceLoader.Load("MyProject.Queries.MergeUser.sql");

using (var conn = new SqlConnection(connectionString))
using (var cmd = new SqlCommand(sql, conn))
{
    cmd.Parameters.Add(new SqlParameter("@Id",             SqlDbType.Int)           { Value = userId });
    cmd.Parameters.Add(new SqlParameter("@Name",           SqlDbType.NVarChar, 100) { Value = (object)name   ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@Email",          SqlDbType.NVarChar, 256) { Value = (object)email  ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@Age",            SqlDbType.Int)           { Value = (object)age    ?? DBNull.Value });
    cmd.Parameters.Add(new SqlParameter("@DepartmentId",   SqlDbType.Int)           { Value = (object)deptId ?? DBNull.Value });

    conn.Open();
    int affected = cmd.ExecuteNonQuery();
}
```

**VB.NET 側**

```vb
Dim sql As String = SqlResourceLoader.Load("MyProject.Queries.MergeUser.sql")

Using conn As New SqlConnection(connectionString)
    Using cmd As New SqlCommand(sql, conn)
        cmd.Parameters.Add(New SqlParameter("@Id", SqlDbType.Int) With {.Value = userId})
        cmd.Parameters.Add(New SqlParameter("@Name", SqlDbType.NVarChar, 100) With {
            .Value = If(name, DirectCast(DBNull.Value, Object))
        })
        cmd.Parameters.Add(New SqlParameter("@Email", SqlDbType.NVarChar, 256) With {
            .Value = If(email, DirectCast(DBNull.Value, Object))
        })
        cmd.Parameters.Add(New SqlParameter("@Age", SqlDbType.Int) With {
            .Value = If(age.HasValue, DirectCast(age.Value, Object), DBNull.Value)
        })
        cmd.Parameters.Add(New SqlParameter("@DepartmentId", SqlDbType.Int) With {
            .Value = If(deptId.HasValue, DirectCast(deptId.Value, Object), DBNull.Value)
        })

        conn.Open()
        Dim affected As Integer = cmd.ExecuteNonQuery()
    End Using
End Using
```

### MERGE文での注意点

1. **セミコロン必須** — MERGE文は `;` で終わらないとエラーになります
2. **ON句にNULL可能な列を使わない** — `ON tgt.NullableCol = src.NullableCol` は `NULL = NULL` が `UNKNOWN` になるためマッチしません
3. **同時実行性** — MERGE文はデッドロックを起こしやすい傾向があります。高頻度で実行する場合は `WITH (HOLDLOCK)` などのヒントを検討してください
4. **OUTPUT句** — INSERT/UPDATE どちらが実行されたかを `$action` で取得できます

```sql
-- どちらの操作が行われたか確認する例
MERGE INTO Users AS tgt
USING (...) AS src
ON tgt.Id = src.Id
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...
OUTPUT $action, inserted.Id;   -- 'INSERT' or 'UPDATE' が返る
```

---

## 共通ヘルパークラスの実装例

実際のプロジェクトでは、パラメータ生成やNULL変換を毎回書くのは冗長です。ヘルパークラスにまとめましょう。

### C# 版

```csharp
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Reflection;

namespace MyProject.Helpers
{
    /// <summary>
    /// SQL埋め込みリソースの読み込みとパラメータ生成を支援するヘルパー
    /// </summary>
    public static class SqlHelper
    {
        // ================================================================
        // リソース読み込み
        // ================================================================

        /// <summary>
        /// 埋め込みリソースからSQLを読み出す
        /// </summary>
        public static string LoadSql(string resourceName)
        {
            var assembly = Assembly.GetExecutingAssembly();
            using (var stream = assembly.GetManifestResourceStream(resourceName))
            {
                if (stream == null)
                {
                    var names = assembly.GetManifestResourceNames();
                    throw new FileNotFoundException(
                        $"リソース '{resourceName}' が見つかりません。\n" +
                        $"登録済み: {string.Join(", ", names)}");
                }

                using (var reader = new StreamReader(stream))
                {
                    return reader.ReadToEnd();
                }
            }
        }

        // ================================================================
        // パラメータ生成
        // ================================================================

        /// <summary>
        /// SqlParameter を生成する（null は自動的に DBNull.Value に変換）
        /// </summary>
        public static SqlParameter MakeParam(string name, SqlDbType type, object value)
        {
            return new SqlParameter(name, type)
            {
                Value = value ?? DBNull.Value
            };
        }

        /// <summary>
        /// 文字列型の SqlParameter を生成する（Size 指定付き）
        /// </summary>
        public static SqlParameter MakeStringParam(string name, int size, string value)
        {
            return new SqlParameter(name, SqlDbType.NVarChar, size)
            {
                Value = (object)value ?? DBNull.Value
            };
        }

        /// <summary>
        /// SqlParameter を一括登録する
        /// </summary>
        public static void AddParameters(SqlCommand cmd, params SqlParameter[] parameters)
        {
            foreach (var param in parameters)
            {
                cmd.Parameters.Add(param);
            }
        }

        // ================================================================
        // 実行ショートカット
        // ================================================================

        /// <summary>
        /// SELECT文を実行し、DataTable で返す
        /// </summary>
        public static DataTable ExecuteQuery(
            string connectionString,
            string resourceName,
            params SqlParameter[] parameters)
        {
            string sql = LoadSql(resourceName);
            var dt = new DataTable();

            using (var conn = new SqlConnection(connectionString))
            using (var cmd = new SqlCommand(sql, conn))
            {
                AddParameters(cmd, parameters);
                conn.Open();

                using (var adapter = new SqlDataAdapter(cmd))
                {
                    adapter.Fill(dt);
                }
            }

            return dt;
        }

        /// <summary>
        /// INSERT / UPDATE / DELETE / MERGE を実行し、影響行数を返す
        /// </summary>
        public static int ExecuteNonQuery(
            string connectionString,
            string resourceName,
            params SqlParameter[] parameters)
        {
            string sql = LoadSql(resourceName);

            using (var conn = new SqlConnection(connectionString))
            using (var cmd = new SqlCommand(sql, conn))
            {
                AddParameters(cmd, parameters);
                conn.Open();
                return cmd.ExecuteNonQuery();
            }
        }
    }
}
```

### VB.NET 版

```vb
Imports System.Data
Imports System.Data.SqlClient
Imports System.IO
Imports System.Reflection

Namespace Helpers

    ''' <summary>
    ''' SQL埋め込みリソースの読み込みとパラメータ生成を支援するヘルパー
    ''' </summary>
    Public Class SqlHelper

        ' ================================================================
        ' リソース読み込み
        ' ================================================================

        ''' <summary>
        ''' 埋め込みリソースからSQLを読み出す
        ''' </summary>
        Public Shared Function LoadSql(resourceName As String) As String
            Dim asm As Assembly = Assembly.GetExecutingAssembly()

            Using stream As Stream = asm.GetManifestResourceStream(resourceName)
                If stream Is Nothing Then
                    Dim names() As String = asm.GetManifestResourceNames()
                    Throw New FileNotFoundException(
                        $"リソース '{resourceName}' が見つかりません。" & vbCrLf &
                        $"登録済み: {String.Join(", ", names)}")
                End If

                Using reader As New StreamReader(stream)
                    Return reader.ReadToEnd()
                End Using
            End Using
        End Function

        ' ================================================================
        ' パラメータ生成
        ' ================================================================

        ''' <summary>
        ''' SqlParameter を生成する（Nothing は自動的に DBNull.Value に変換）
        ''' </summary>
        Public Shared Function MakeParam(name As String, type As SqlDbType, value As Object) As SqlParameter
            Return New SqlParameter(name, type) With {
                .Value = If(value, DBNull.Value)
            }
        End Function

        ''' <summary>
        ''' 文字列型の SqlParameter を生成する（Size 指定付き）
        ''' </summary>
        Public Shared Function MakeStringParam(name As String, size As Integer, value As String) As SqlParameter
            Return New SqlParameter(name, SqlDbType.NVarChar, size) With {
                .Value = If(DirectCast(value, Object), DBNull.Value)
            }
        End Function

        ''' <summary>
        ''' Nullable(Of T) 型の SqlParameter を生成する
        ''' </summary>
        Public Shared Function MakeNullableParam(Of T As Structure)(
                name As String, type As SqlDbType, value As T?) As SqlParameter
            Return New SqlParameter(name, type) With {
                .Value = If(value.HasValue, DirectCast(value.Value, Object), DBNull.Value)
            }
        End Function

        ''' <summary>
        ''' SqlParameter を一括登録する
        ''' </summary>
        Public Shared Sub AddParameters(cmd As SqlCommand, ParamArray parameters() As SqlParameter)
            For Each param As SqlParameter In parameters
                cmd.Parameters.Add(param)
            Next
        End Sub

        ' ================================================================
        ' 実行ショートカット
        ' ================================================================

        ''' <summary>
        ''' SELECT文を実行し、DataTable で返す
        ''' </summary>
        Public Shared Function ExecuteQuery(
                connectionString As String,
                resourceName As String,
                ParamArray parameters() As SqlParameter) As DataTable

            Dim sql As String = LoadSql(resourceName)
            Dim dt As New DataTable()

            Using conn As New SqlConnection(connectionString)
                Using cmd As New SqlCommand(sql, conn)
                    AddParameters(cmd, parameters)
                    conn.Open()

                    Using adapter As New SqlDataAdapter(cmd)
                        adapter.Fill(dt)
                    End Using
                End Using
            End Using

            Return dt
        End Function

        ''' <summary>
        ''' INSERT / UPDATE / DELETE / MERGE を実行し、影響行数を返す
        ''' </summary>
        Public Shared Function ExecuteNonQuery(
                connectionString As String,
                resourceName As String,
                ParamArray parameters() As SqlParameter) As Integer

            Dim sql As String = LoadSql(resourceName)

            Using conn As New SqlConnection(connectionString)
                Using cmd As New SqlCommand(sql, conn)
                    AddParameters(cmd, parameters)
                    conn.Open()
                    Return cmd.ExecuteNonQuery()
                End Using
            End Using
        End Function

    End Class

End Namespace
```

> **VB.NET 版の追加ポイント：`MakeNullableParam(Of T)` メソッド**
>
> VB.NET では `Integer?`（`Nullable(Of Integer)`）の NULL 変換が C# ほど簡潔に書けないため、
> ジェネリックメソッド `MakeNullableParam` を追加しています。
> これにより値型の Nullable を簡潔にパラメータ変換できます。

### 使用例

**C#**

```csharp
using static MyProject.Helpers.SqlHelper;

// SELECT
DataTable result = ExecuteQuery(connStr, "MyProject.Queries.SelectUsers.sql",
    MakeStringParam("@Name", 100, searchName),    // null なら条件無視
    MakeParam("@Age", SqlDbType.Int, searchAge)
);

// UPDATE
int rows = ExecuteNonQuery(connStr, "MyProject.Queries.UpdateUser.sql",
    MakeParam("@Id",    SqlDbType.Int, userId),
    MakeStringParam("@Name",  100, newName),
    MakeStringParam("@Email", 256, newEmail),     // null なら NULL を代入
    MakeParam("@Age",   SqlDbType.Int, newAge)
);

// MERGE
int rows = ExecuteNonQuery(connStr, "MyProject.Queries.MergeUser.sql",
    MakeParam("@Id",    SqlDbType.Int, userId),
    MakeStringParam("@Name",  100, name),
    MakeStringParam("@Email", 256, email),
    MakeParam("@Age",   SqlDbType.Int, age),
    MakeParam("@DepartmentId", SqlDbType.Int, deptId)
);
```

**VB.NET**

```vb
Imports MyProject.Helpers.SqlHelper

' SELECT
Dim result As DataTable = ExecuteQuery(connStr, "MyProject.Queries.SelectUsers.sql",
    MakeStringParam("@Name", 100, searchName),
    MakeNullableParam("@Age", SqlDbType.Int, searchAge)
)

' UPDATE
Dim rows As Integer = ExecuteNonQuery(connStr, "MyProject.Queries.UpdateUser.sql",
    MakeParam("@Id",    SqlDbType.Int, userId),
    MakeStringParam("@Name",  100, newName),
    MakeStringParam("@Email", 256, newEmail),
    MakeNullableParam("@Age", SqlDbType.Int, newAge)
)

' MERGE
Dim mergeRows As Integer = ExecuteNonQuery(connStr, "MyProject.Queries.MergeUser.sql",
    MakeParam("@Id",    SqlDbType.Int, userId),
    MakeStringParam("@Name",  100, name),
    MakeStringParam("@Email", 256, email),
    MakeNullableParam("@Age", SqlDbType.Int, age),
    MakeNullableParam("@DepartmentId", SqlDbType.Int, deptId)
)
```

---

## よくあるハマりどころと対策

| # | 問題 | 原因 | 対策 |
|---|---|---|---|
| 1 | `Value = null` / `Value = Nothing` でエラー | C#/VB の null/Nothing はパラメータ未設定扱い | 必ず `DBNull.Value` を使う |
| 2 | SqlDbType 未指定でエラー | NULL 時に型推論できない | `SqlDbType` を常に明示する |
| 3 | `NVarChar` のプランキャッシュ肥大 | Size 未指定だと値の長さごとに別プラン | `Size` を明示する（-1 で MAX） |
| 4 | MERGE文の末尾エラー | セミコロンが不足 | MERGE文は必ず `;` で終端する |
| 5 | `WHERE Column = @Param` でNULL行がヒットしない | `NULL = NULL` は UNKNOWN | `IS NULL` と `OR` を組み合わせる |
| 6 | 埋め込みリソースが見つからない | リソース名の不一致 | `GetManifestResourceNames()` で確認 |
| 7 | COALESCE で意図的な NULL 代入ができない | COALESCE は NULL を既存値で上書き | フラグパラメータを別途用意する |
| 8 | パラメータスニッフィングによる性能低下 | 最初のプランが全パターンに使い回される | `OPTION (RECOMPILE)` を検討 |
| 9 | VB.NET で `IIf` を使ってしまう | `IIf` は両辺を評価する | `If` 演算子（短絡評価）を使う |
| 10 | VB.NET のルート名前空間を考慮していない | リソース名が C# と異なる | プロジェクトプロパティで確認 |

---

## 関連知識：知っておくと役立つポイント

### 1. SQLインジェクション対策としてのバインド変数

バインド変数を使用する最大の理由はセキュリティです。文字列連結でSQL文を組み立てると、悪意のある入力により意図しないSQLが実行される可能性があります。

**C#**

```csharp
// 絶対にやってはいけない例
string sql = "SELECT * FROM Users WHERE Name = '" + userInput + "'";
// userInput = "'; DROP TABLE Users; --" → テーブルが削除される！

// 正しい例（バインド変数）
string sql = "SELECT * FROM Users WHERE Name = @Name";
cmd.Parameters.Add(new SqlParameter("@Name", SqlDbType.NVarChar, 100) { Value = userInput });
```

**VB.NET**

```vb
' 絶対にやってはいけない例
Dim sql As String = "SELECT * FROM Users WHERE Name = '" & userInput & "'"
' userInput = "'; DROP TABLE Users; --" → テーブルが削除される！

' 正しい例（バインド変数）
Dim sql As String = "SELECT * FROM Users WHERE Name = @Name"
cmd.Parameters.Add(New SqlParameter("@Name", SqlDbType.NVarChar, 100) With {.Value = userInput})
```

### 2. SqlDbType と C# / VB.NET 型の対応表

| SqlDbType | C# の型 | VB.NET の型 | SQL Server 型 | 備考 |
|---|---|---|---|---|
| `Int` | `int` / `int?` | `Integer` / `Integer?` | `int` | |
| `BigInt` | `long` / `long?` | `Long` / `Long?` | `bigint` | |
| `Bit` | `bool` / `bool?` | `Boolean` / `Boolean?` | `bit` | |
| `NVarChar` | `string` | `String` | `nvarchar(n)` | Size の指定推奨 |
| `VarChar` | `string` | `String` | `varchar(n)` | 非Unicode。日本語には NVarChar を使う |
| `DateTime2` | `DateTime` / `DateTime?` | `Date` / `Date?` | `datetime2` | `DateTime` より精度が高い |
| `Date` | `DateTime` / `DateTime?` | `Date` / `Date?` | `date` | 日付のみ |
| `Decimal` | `decimal` / `decimal?` | `Decimal` / `Decimal?` | `decimal(p,s)` | Precision/Scale の指定推奨 |
| `UniqueIdentifier` | `Guid` / `Guid?` | `Guid` / `Guid?` | `uniqueidentifier` | |

### 3. Nullable 型との組み合わせパターン

**C#**

```csharp
// int? → パラメータ
int? age = null;
cmd.Parameters.Add(new SqlParameter("@Age", SqlDbType.Int)
{
    Value = age.HasValue ? (object)age.Value : DBNull.Value
});

// 短縮形（キャストを利用）
cmd.Parameters.Add(new SqlParameter("@Age", SqlDbType.Int)
{
    Value = (object)age ?? DBNull.Value
});
```

**VB.NET**

```vb
' Integer? → パラメータ
Dim age As Integer? = Nothing
cmd.Parameters.Add(New SqlParameter("@Age", SqlDbType.Int) With {
    .Value = If(age.HasValue, DirectCast(age.Value, Object), DBNull.Value)
})

' ヘルパーメソッドを使う場合（推奨）
cmd.Parameters.Add(SqlHelper.MakeNullableParam("@Age", SqlDbType.Int, age))
```

> **VB.NET での Nullable の注意点**
>
> VB.NET では `(object)age ?? DBNull.Value` のような C# の null合体演算子が直接は使えません。
> `If(age.HasValue, ..., ...)` 形式か、ヘルパーメソッドで対応します。
>
> ```vb
> ' String 型（参照型）の場合は If 2引数版が使える
> Dim name As String = Nothing
> .Value = If(DirectCast(name, Object), DBNull.Value)   ' name が Nothing なら DBNull.Value
>
> ' Integer?（値型の Nullable）の場合は If 3引数版を使う
> Dim age As Integer? = Nothing
> .Value = If(age.HasValue, DirectCast(age.Value, Object), DBNull.Value)
> ```

### 4. DataReader でのNULL読み出し

**C#**

```csharp
using (var reader = cmd.ExecuteReader())
{
    while (reader.Read())
    {
        // NG — DBNull で InvalidCastException
        // string name = (string)reader["Name"];

        // OK — IsDBNull でチェック
        string name = reader.IsDBNull(reader.GetOrdinal("Name"))
            ? null
            : reader.GetString(reader.GetOrdinal("Name"));

        // OK — as 演算子を使う（参照型のみ）
        string email = reader["Email"] as string;

        // OK — 値型は変換ヘルパーを使う
        int? age = reader["Age"] == DBNull.Value
            ? (int?)null
            : (int)reader["Age"];
    }
}
```

**VB.NET**

```vb
Using reader As SqlDataReader = cmd.ExecuteReader()
    Do While reader.Read()
        ' NG — DBNull で InvalidCastException
        ' Dim name As String = DirectCast(reader("Name"), String)

        ' OK — IsDBNull でチェック
        Dim name As String = If(reader.IsDBNull(reader.GetOrdinal("Name")),
                                Nothing,
                                reader.GetString(reader.GetOrdinal("Name")))

        ' OK — TryCast を使う（参照型のみ。VB版の as 演算子）
        Dim email As String = TryCast(reader("Email"), String)

        ' OK — 値型は明示的にチェック
        Dim age As Integer? = If(IsDBNull(reader("Age")),
                                 DirectCast(Nothing, Integer?),
                                 CInt(reader("Age")))
    Loop
End Using
```

### 5. トランザクション管理

**C#**

```csharp
using (var conn = new SqlConnection(connectionString))
{
    conn.Open();

    using (var tran = conn.BeginTransaction())
    {
        try
        {
            using (var cmd1 = new SqlCommand(sql1, conn, tran))
            {
                // パラメータ設定・実行
                cmd1.ExecuteNonQuery();
            }

            using (var cmd2 = new SqlCommand(sql2, conn, tran))
            {
                // パラメータ設定・実行
                cmd2.ExecuteNonQuery();
            }

            tran.Commit();
        }
        catch
        {
            tran.Rollback();
            throw;
        }
    }
}
```

**VB.NET**

```vb
Using conn As New SqlConnection(connectionString)
    conn.Open()

    Using tran As SqlTransaction = conn.BeginTransaction()
        Try
            Using cmd1 As New SqlCommand(sql1, conn, tran)
                ' パラメータ設定・実行
                cmd1.ExecuteNonQuery()
            End Using

            Using cmd2 As New SqlCommand(sql2, conn, tran)
                ' パラメータ設定・実行
                cmd2.ExecuteNonQuery()
            End Using

            tran.Commit()
        Catch
            tran.Rollback()
            Throw
        End Try
    End Using
End Using
```

### 6. 接続文字列のベストプラクティス

```xml
<!-- App.config / Web.config -->
<connectionStrings>
    <add name="MyDb"
         connectionString="Data Source=ServerName;Initial Catalog=DbName;Integrated Security=True;Connection Timeout=30;Application Name=MyApp"
         providerName="System.Data.SqlClient" />
</connectionStrings>
```

接続文字列の読み出し方法：

**C#**

```csharp
using System.Configuration;

string connStr = ConfigurationManager.ConnectionStrings["MyDb"].ConnectionString;
```

**VB.NET**

```vb
Imports System.Configuration

Dim connStr As String = ConfigurationManager.ConnectionStrings("MyDb").ConnectionString
```

- `Application Name` を設定すると、SQL Server のアクティビティモニターで接続元を識別しやすくなります
- `Connection Timeout` はデフォルト15秒ですが、環境に応じて調整してください
- 接続プーリングはデフォルトで有効です。`Using` で確実に接続を閉じることで、プールに返却されます

### 7. 埋め込みリソース vs 外部ファイル vs ストアドプロシージャ

| 方式 | メリット | デメリット |
|---|---|---|
| **埋め込みリソース** | 配布が簡単、改ざんされにくい | SQL変更にはリビルドが必要 |
| **外部ファイル** | SQL変更が容易（リビルド不要） | ファイル配置ミス・改ざんリスク |
| **ストアドプロシージャ** | 実行プラン最適化、権限管理が容易 | DB側のデプロイ管理が必要 |

プロジェクトの規模や運用体制に応じて選択してください。

### 8. SQL Server の NULL に関する重要な仕様

SQL Server における NULL の振る舞いは直感に反する部分があります。

```sql
-- NULL の比較は常に UNKNOWN（偽と同等）
SELECT CASE WHEN NULL = NULL    THEN 'TRUE' ELSE 'FALSE' END  -- → FALSE
SELECT CASE WHEN NULL <> NULL   THEN 'TRUE' ELSE 'FALSE' END  -- → FALSE
SELECT CASE WHEN NULL <> 1      THEN 'TRUE' ELSE 'FALSE' END  -- → FALSE

-- NULL の算術演算は NULL
SELECT 1 + NULL      -- → NULL
SELECT NULL * 100    -- → NULL

-- 集約関数は NULL を無視する
SELECT COUNT(NullableCol) FROM T  -- NULL行はカウントされない
SELECT AVG(NullableCol)   FROM T  -- NULL行は平均の分母に含まれない

-- COALESCE で最初の非NULLを返す
SELECT COALESCE(NULL, NULL, 'default')  -- → 'default'

-- ISNULL は2引数、COALESCE は多引数
SELECT ISNULL(NULL, 'default')          -- → 'default'
```

### 9. .csproj / .vbproj でのワイルドカード埋め込み（SDK形式）

SDK形式のプロジェクトファイルを使用している場合、ワイルドカードで一括指定できます。

```xml
<ItemGroup>
    <EmbeddedResource Include="Queries\**\*.sql" />
</ItemGroup>
```

> **注意：** .NET Framework 4.8 の従来形式（`<Project ToolsVersion="...">`）では
> ワイルドカードが使えないため、個別に追加するか、SDK形式に移行する必要があります。

### 10. VB.NET 固有の注意事項まとめ

| 項目 | C# | VB.NET | 注意点 |
|---|---|---|---|
| null合体演算子 | `??` が使える | `If(値, 代替)` で代用 | 参照型のみ2引数 `If` が使える |
| 値型のNullable変換 | `(object)age ?? DBNull.Value` | `If(age.HasValue, CObj(age.Value), DBNull.Value)` | VB.NET は冗長になりがち。ヘルパー推奨 |
| 型変換演算子 | `as`（参照型） | `TryCast`（参照型） | 値型には使えない |
| null チェック | `== null` | `Is Nothing` | VB.NET では `=` ではなく `Is` を使う |
| ルート名前空間 | なし（ファイル内で定義） | プロジェクト設定にある | リソース名に影響するため必ず確認 |
| Using 文 | `using (var x = ...) { }` | `Using x As New ... End Using` | VB.NET はネストが深くなりがち |
| 文字列結合 | `+` または `$""` | `&` または `$""` | VB14以降は文字列補間 `$""` 対応 |
| コメント | `//`、`/* */` | `'`（シングルクォート） | VB.NET にブロックコメントはない |
| 短絡評価 | `&&`、`||` | `AndAlso`、`OrElse` | `And`/`Or` は短絡評価しないので注意 |

---

## C# と VB.NET の構文対応早見表

本ドキュメントで頻出する構文の対応表です。

### パラメータ生成

```csharp
// C#：オブジェクト初期化子 + null合体演算子
new SqlParameter("@Name", SqlDbType.NVarChar, 100) { Value = (object)name ?? DBNull.Value }
```

```vb
' VB.NET：With 初期化子 + If 演算子
New SqlParameter("@Name", SqlDbType.NVarChar, 100) With {
    .Value = If(DirectCast(name, Object), DBNull.Value)
}
```

### Nullable値型のパラメータ生成

```csharp
// C#：int? のパラメータ
new SqlParameter("@Age", SqlDbType.Int) { Value = (object)age ?? DBNull.Value }
```

```vb
' VB.NET：Integer? のパラメータ
New SqlParameter("@Age", SqlDbType.Int) With {
    .Value = If(age.HasValue, DirectCast(age.Value, Object), DBNull.Value)
}
```

### Using 文のネスト

```csharp
// C#：using のチェーン
using (var conn = new SqlConnection(connStr))
using (var cmd = new SqlCommand(sql, conn))
{
    // ...
}
```

```vb
' VB.NET：Using のネスト
Using conn As New SqlConnection(connStr)
    Using cmd As New SqlCommand(sql, conn)
        ' ...
    End Using
End Using
```

### DBNull チェック（データ読み出し時）

```csharp
// C#
string name = reader["Name"] as string;
int? age = reader["Age"] == DBNull.Value ? (int?)null : (int)reader["Age"];
```

```vb
' VB.NET
Dim name As String = TryCast(reader("Name"), String)
Dim age As Integer? = If(IsDBNull(reader("Age")),
                         DirectCast(Nothing, Integer?),
                         CInt(reader("Age")))
```

---

## まとめ

| やりたいこと | C# 側 | VB.NET 側 | SQL 側 |
|---|---|---|---|
| 列にNULLを代入（UPDATE/MERGE） | `Value = DBNull.Value` | `Value = DBNull.Value` | `SET Col = @Param`（そのまま） |
| NULLなら条件を無視（SELECT） | `(object)val ?? DBNull.Value` | `If(val, DBNull.Value)` | `@Param IS NULL OR Col = @Param` |
| NULLの行を検索（SELECT） | バインド変数では不可 | バインド変数では不可 | `WHERE Col IS NULL`（直接記述） |
| NULLなら既存値維持（UPDATE） | `Value = DBNull.Value` | `Value = DBNull.Value` | `SET Col = COALESCE(@Param, Col)` |

**基本原則：**

- **C#** では `(object)value ?? DBNull.Value` パターンで統一
- **VB.NET** では参照型は `If(DirectCast(value, Object), DBNull.Value)`、値型の Nullable は `If(value.HasValue, CObj(value.Value), DBNull.Value)` パターンで統一（またはヘルパーメソッドを活用）
- **SQL** では用途に応じた `IS NULL` の使い分けを意識する
