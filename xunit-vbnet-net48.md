# VB.NET (.NET Framework 4.8) + xUnit 2 テスト環境構築ガイド

## 1. 前提

| 項目 | 内容 |
|---|---|
| 言語 | VB.NET |
| 対象フレームワーク | .NET Framework 4.8 |
| テストフレームワーク | xUnit 2.x |
| IDE | Visual Studio 2019 / 2022 |
| OS | Windows(.NET Framework のため) |

### 推奨構成

```
MySolution.sln
├─ MyApp/                 ← 既存の本体プロジェクト (WinForms / クラスライブラリ等)
│   └─ MyApp.vbproj
└─ MyApp.Tests/           ← 新規作成するテストプロジェクト
    └─ MyApp.Tests.vbproj
```

ポイント:
- **テストプロジェクトは SDK 形式 (`Microsoft.NET.Sdk`) の vbproj で作る**のが一番ラクです。`TargetFramework` を `net48` にすれば .NET Framework 4.8 向けにビルドされ、`packages.config` も不要です。
- 本体が旧形式 (非SDK形式) の vbproj でも、`ProjectReference` で参照できます。

---

## 2. 環境構築手順

### 手順1: テストプロジェクトのフォルダと vbproj を作る

Visual Studio の「新しいプロジェクト」に VB 用の xUnit テンプレートは .NET Core 系しか出ないことが多いので、**手動で vbproj を作る方法**を推奨します。

1. ソリューションフォルダに `MyApp.Tests` フォルダを作成
2. 中に `MyApp.Tests.vbproj` を作成し、下記を貼り付ける

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <RootNamespace>MyApp.Tests</RootNamespace>
    <AssemblyName>MyApp.Tests</AssemblyName>
    <IsPackable>false</IsPackable>
    <OptionStrict>On</OptionStrict>
    <OptionInfer>On</OptionInfer>
    <OptionExplicit>On</OptionExplicit>
    <!-- テストプロジェクトに My 名前空間 (WinForms 用) は不要 -->
    <MyType>Empty</MyType>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>

  <ItemGroup>
    <!-- テスト対象プロジェクトを参照 -->
    <ProjectReference Include="..\MyApp\MyApp.vbproj" />
  </ItemGroup>

</Project>
```

> バージョンは例です。NuGet で最新の安定版を選んでください。
> `xunit.runner.visualstudio` と `Microsoft.NET.Test.Sdk` は**必須**です(Test Explorer / `dotnet test` がテストを検出するために必要)。

### 手順2: ソリューションに追加

Visual Studio:
1. ソリューションを右クリック → **追加 → 既存のプロジェクト**
2. `MyApp.Tests.vbproj` を選択

またはコマンドラインで:

```powershell
dotnet sln MySolution.sln add MyApp.Tests\MyApp.Tests.vbproj
```

### 手順3: NuGet パッケージの復元

Visual Studio でソリューションを開けば自動復元されます。手動なら:

```powershell
dotnet restore
```

### 手順4: テストを書く(次章のサンプル参照)

### 手順5: テストを実行

**Visual Studio**
- メニュー **テスト → テスト エクスプローラー** → 「すべて実行」

**コマンドライン**

```powershell
# ソリューション全体
dotnet test

# テストプロジェクトのみ
dotnet test MyApp.Tests\MyApp.Tests.vbproj

# 名前でフィルタ
dotnet test --filter "FullyQualifiedName~CalculatorTests"

# 結果を詳細表示
dotnet test --logger "console;verbosity=detailed"
```

---

## 3. テスト対象のサンプル (MyApp 側)

`MyApp/Calculator.vb`

```vb
Public Class Calculator

    Public Function Add(a As Integer, b As Integer) As Integer
        Return a + b
    End Function

    Public Function Divide(a As Integer, b As Integer) As Double
        If b = 0 Then
            Throw New DivideByZeroException("0では割れません。")
        End If
        Return CDbl(a) / b
    End Function

    Public Function IsEven(n As Integer) As Boolean
        Return n Mod 2 = 0
    End Function

End Class
```

---

## 4. テストのサンプル (MyApp.Tests 側)

### 4-1. 基本: `Fact` と `Theory`

`MyApp.Tests/CalculatorTests.vb`

```vb
Imports Xunit
Imports MyApp

Public Class CalculatorTests

    ' --- Fact: 引数なしの単純なテスト ---
    <Fact>
    Public Sub Add_2と3を渡すと5を返す()
        ' Arrange
        Dim sut As New Calculator()

        ' Act
        Dim actual As Integer = sut.Add(2, 3)

        ' Assert
        Assert.Equal(5, actual)
    End Sub

    ' --- Theory + InlineData: 同じテストを複数の入力で実行 ---
    <Theory>
    <InlineData(1, 1, 2)>
    <InlineData(0, 0, 0)>
    <InlineData(-1, 1, 0)>
    <InlineData(100, 200, 300)>
    Public Sub Add_複数パターン(a As Integer, b As Integer, expected As Integer)
        Dim sut As New Calculator()

        Assert.Equal(expected, sut.Add(a, b))
    End Sub

    <Theory>
    <InlineData(2, True)>
    <InlineData(3, False)>
    <InlineData(0, True)>
    <InlineData(-4, True)>
    Public Sub IsEven_偶数判定(n As Integer, expected As Boolean)
        Dim sut As New Calculator()

        Assert.Equal(expected, sut.IsEven(n))
    End Sub

    ' --- 例外のテスト ---
    ' VB.NET ではラムダを Sub(...) で書く
    <Fact>
    Public Sub Divide_0で割ると例外()
        Dim sut As New Calculator()

        Dim ex = Assert.Throws(Of DivideByZeroException)(Sub() sut.Divide(10, 0))

        Assert.Equal("0では割れません。", ex.Message)
    End Sub

    ' --- 浮動小数点は precision を指定して比較 ---
    <Fact>
    Public Sub Divide_小数の比較()
        Dim sut As New Calculator()

        Assert.Equal(3.333, sut.Divide(10, 3), 3)   ' 小数第3位まで一致
    End Sub

    ' --- 一時的にスキップ ---
    <Fact(Skip:="仕様確認待ち")>
    Public Sub 保留中のテスト()
        Assert.True(False)
    End Sub

End Class
```

### 4-2. `MemberData` でテストデータをクラス/メソッドから供給

```vb
Imports Xunit
Imports MyApp

Public Class CalculatorMemberDataTests

    ' MemberData のデータソースは Shared (static) で定義する
    Public Shared ReadOnly Property AddCases As IEnumerable(Of Object())
        Get
            Return New List(Of Object()) From {
                New Object() {1, 2, 3},
                New Object() {10, 20, 30},
                New Object() {-5, 5, 0}
            }
        End Get
    End Property

    <Theory>
    <MemberData(NameOf(AddCases))>
    Public Sub Add_MemberData(a As Integer, b As Integer, expected As Integer)
        Dim sut As New Calculator()

        Assert.Equal(expected, sut.Add(a, b))
    End Sub

End Class
```

### 4-3. コレクション / 文字列のアサーション例

```vb
Imports Xunit

Public Class AssertionSamples

    <Fact>
    Public Sub コレクションのアサート()
        Dim list As New List(Of Integer) From {1, 2, 3}

        Assert.NotEmpty(list)
        Assert.Equal(3, list.Count)
        Assert.Contains(2, list)
        Assert.DoesNotContain(99, list)
        Assert.All(list, Sub(x) Assert.True(x > 0))
        Assert.Equal(New Integer() {1, 2, 3}, list)   ' 要素順に比較
    End Sub

    <Fact>
    Public Sub 文字列のアサート()
        Dim s As String = "Hello, xUnit"

        Assert.StartsWith("Hello", s)
        Assert.EndsWith("xUnit", s)
        Assert.Contains("xUnit", s)
        Assert.Equal("hello, xunit", s, ignoreCase:=True)
        Assert.NotNull(s)
        Assert.False(String.IsNullOrEmpty(s))
    End Sub

    <Fact>
    Public Sub 型のアサート()
        Dim obj As Object = "text"

        Assert.IsType(Of String)(obj)
        Assert.IsAssignableFrom(Of IComparable)(obj)
    End Sub

End Class
```

### 4-4. セットアップ / 後始末 (コンストラクタと `IDisposable`)

xUnit には `[SetUp]` / `[TearDown]` がありません。**テストごとにクラスのインスタンスが新規生成される**ので、コンストラクタ = SetUp、`Dispose` = TearDown です。

```vb
Imports Xunit
Imports MyApp

Public Class CalculatorLifecycleTests
    Implements IDisposable

    Private ReadOnly _sut As Calculator

    ' 各テストの前に毎回呼ばれる (= SetUp)
    Public Sub New()
        _sut = New Calculator()
    End Sub

    <Fact>
    Public Sub テスト1()
        Assert.Equal(3, _sut.Add(1, 2))
    End Sub

    <Fact>
    Public Sub テスト2()
        Assert.True(_sut.IsEven(2))
    End Sub

    ' 各テストの後に毎回呼ばれる (= TearDown)
    Public Sub Dispose() Implements IDisposable.Dispose
        ' 一時ファイル削除、DB接続クローズ等
    End Sub

End Class
```

### 4-5. `IClassFixture` でクラス内のテスト間で重い初期化を共有

```vb
Imports Xunit

' 共有したいリソース (DB接続や一時フォルダ等)
Public Class TempFolderFixture
    Implements IDisposable

    Public ReadOnly Property Path As String

    Public Sub New()
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), Guid.NewGuid().ToString())
        System.IO.Directory.CreateDirectory(Path)
    End Sub

    Public Sub Dispose() Implements IDisposable.Dispose
        If System.IO.Directory.Exists(Path) Then
            System.IO.Directory.Delete(Path, True)
        End If
    End Sub

End Class

Public Class FileTests
    Implements IClassFixture(Of TempFolderFixture)

    Private ReadOnly _fixture As TempFolderFixture

    ' Fixture はコンストラクタ引数で受け取る
    Public Sub New(fixture As TempFolderFixture)
        _fixture = fixture
    End Sub

    <Fact>
    Public Sub ファイルを書いて読める()
        Dim file = System.IO.Path.Combine(_fixture.Path, "a.txt")

        System.IO.File.WriteAllText(file, "abc")

        Assert.Equal("abc", System.IO.File.ReadAllText(file))
    End Sub

End Class
```

### 4-6. 非同期テスト

VB.NET では `Async Function ... As Task` にします(`Async Sub` は不可)。

```vb
Imports System.Threading.Tasks
Imports Xunit

Public Class AsyncSamples

    <Fact>
    Public Async Function 非同期メソッドのテスト() As Task
        Dim result As Integer = Await GetValueAsync()

        Assert.Equal(42, result)
    End Function

    <Fact>
    Public Async Function 非同期例外のテスト() As Task
        Await Assert.ThrowsAsync(Of InvalidOperationException)(
            Function() ThrowAsync())
    End Function

    Private Async Function GetValueAsync() As Task(Of Integer)
        Await Task.Delay(10)
        Return 42
    End Function

    Private Async Function ThrowAsync() As Task
        Await Task.Delay(10)
        Throw New InvalidOperationException()
    End Function

End Class
```

### 4-7. テストごとの出力 (`ITestOutputHelper`)

`Console.WriteLine` はテスト結果に出ません。代わりに `ITestOutputHelper` を使います。

```vb
Imports Xunit
Imports Xunit.Abstractions

Public Class OutputSamples

    Private ReadOnly _output As ITestOutputHelper

    Public Sub New(output As ITestOutputHelper)
        _output = output
    End Sub

    <Fact>
    Public Sub ログを出力する()
        _output.WriteLine("デバッグ情報: {0}", DateTime.Now)
        Assert.True(True)
    End Sub

End Class
```

---

## 5. 本体側の `Friend` メンバーをテストしたい場合

`Friend` (C# の internal) は別アセンブリから見えません。本体プロジェクトの `My Project\AssemblyInfo.vb` に追記します。

```vb
Imports System.Runtime.CompilerServices

<Assembly: InternalsVisibleTo("MyApp.Tests")>
```

---

## 6. WinForms アプリをテストするときの考え方

- `Form` クラスそのものの単体テストは難しい(UIスレッド・ハンドル生成が必要)。
- **ロジックをフォームから切り出して**、別クラス(Service / Presenter 等)にしてからテストするのが定石です。
  - 例: 計算処理、CSV/Excel読み込み、入力チェック、Undo/Redo のスタック管理 など
- DB・ファイル・日時など外部依存は **インターフェース化** して、テストではスタブに差し替えます。

```vb
' 日時の依存をインターフェース化する例
Public Interface IClock
    Function Now() As DateTime
End Interface

Public Class SystemClock
    Implements IClock
    Public Function Now() As DateTime Implements IClock.Now
        Return DateTime.Now
    End Function
End Class

' テスト用スタブ
Public Class FakeClock
    Implements IClock
    Private ReadOnly _fixed As DateTime
    Public Sub New(fixed As DateTime)
        _fixed = fixed
    End Sub
    Public Function Now() As DateTime Implements IClock.Now
        Return _fixed
    End Function
End Class
```

モックライブラリを使いたい場合は NuGet から **Moq** または **NSubstitute** を追加します(どちらも .NET Framework 4.8 対応)。

```xml
<PackageReference Include="NSubstitute" Version="5.1.0" />
```

---

## 7. トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| Test Explorer にテストが出てこない | `Microsoft.NET.Test.Sdk` と `xunit.runner.visualstudio` が入っているか確認。ビルド後に「テスト → テスト エクスプローラー」を再読み込み |
| `dotnet test` で "No test is available" | 上記パッケージ不足、または `TargetFramework` が `net48` になっているか確認 |
| 本体のクラスが見えない | `ProjectReference` の追加漏れ、`Friend` のままでアクセスしている(→ 5章) |
| `Assert.Throws` でコンパイルエラー | VB では `Sub() ...`(戻り値なし)または `Function() ...`(戻り値あり)のラムダを渡す。式の戻り値を捨てたいときは `Sub()` |
| `MemberData` で "Could not find public static member" | データソースは `Public Shared` で定義する |
| 旧形式 vbproj + `packages.config` でテストが動かない | SDK 形式のテストプロジェクトに分ける方式(本書)を推奨 |
| 32bit/64bit の違いでDLLが読めない | テストプロジェクトの `PlatformTarget` を本体に合わせる |

---

## 8. 参考

- xUnit.net 公式: https://xunit.net/
- xUnit Assert 一覧: https://xunit.net/docs/comparisons
- テストの命名・構成は **AAA (Arrange / Act / Assert)** パターンに揃えると読みやすくなります。
