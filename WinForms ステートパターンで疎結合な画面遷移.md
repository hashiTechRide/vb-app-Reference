# はじめに

VB.NET .NET Framework 4.8でWinFormsアプリケーションを開発する際、画面遷移をステートパターンで実装するケースがあります。しかし、よくある実装では以下の問題が発生します。
- フォームに遷移ロジックが混在
- State が他の State を直接 new して密結合
- UserControl が画面遷移を知りすぎている

本記事では、**疎結合で保守性の高いステートパターン**の実装方法を解説します。

## 前提条件

- VB.NET (.NET Framework 4.8)
- WinForms アプリケーション
- 共通レイアウトは固定、コンテンツ部分のみ UserControl で切り替え
- 特定画面のみタイトルバーにボタン追加などの拡張が必要

## アンチパターン：よくある密結合な実装

### ❌ パターン1：フォームに遷移ロジックが混在

```vb
Public Class MainForm
    Private Sub ShowHomeScreen()
        HomePanel.Visible = True
        SettingsPanel.Visible = False
        
        ' フォームが遷移ロジックを持っている
        If TypeOf currentState Is IHasCustomButton Then
            AddTitleButton(...)
        End If
    End Sub
End Class
```

### ❌ パターン2：State が別の State を直接 new

```vb
Public Class HomeScreenState
    Private Sub OnNextClick()
        ' 密結合：HomeScreenState が SettingsScreenState を知っている
        context.ChangeState(New SettingsScreenState())
    End Sub
End Class
```

### ❌ パターン3：UserControl が遷移を直接実行

```vb
Public Class HomeScreenUserControl
    Private context As ScreenContext
    
    Private Sub NextButton_Click(sender As Object, e As EventArgs)
        ' UserControl が画面遷移を知りすぎている
        context.ChangeState(New SettingsScreenState())
    End Sub
End Class
```

## ✅ 解決策：疎結合なステートパターン

### 基本方針

1. **Context クラス**が遷移マッピングを一元管理
2. **State** は遷移先を「名前」で指定（具象クラスを知らない）
3. **UserControl** はイベントで「意図」のみ通知

### アーキテクチャ図

```
┌─────────────┐
│  MainForm   │ ← UI要素の配置のみ
└──────┬──────┘
       │
┌──────▼──────────┐
│ ScreenContext   │ ← 遷移マッピング管理
│ + NavigateTo()  │
└──────┬──────────┘
       │
┌──────▼──────────┐
│  IScreenState   │ ← 各画面の振る舞い
│  + Enter()      │
│  + Exit()       │
└─────────────────┘
```

## 実装：列挙型による疎結合化

### 1. 遷移先を列挙型で定義

```vb
Public Enum Screen
    Login
    Home
    Settings
    Profile
    AdminDashboard
    UserDashboard
End Enum
```

### 2. ScreenContext クラス（遷移管理の中核）

```vb
Public Class ScreenContext
    Private mainForm As MainForm
    Private currentState As IScreenState
    Private contentPanel As Panel
    Private titlePanel As Panel
    Private customTitleButton As Button
    
    ' 遷移マッピング
    Private stateFactory As Dictionary(Of Screen, Func(Of IScreenState))
    
    Public Sub New(form As MainForm, content As Panel, title As Panel)
        mainForm = form
        contentPanel = content
        titlePanel = title
        InitializeStateFactory()
    End Sub
    
    Private Sub InitializeStateFactory()
        stateFactory = New Dictionary(Of Screen, Func(Of IScreenState))()
        
        ' ここで全ての遷移マッピングを定義（一元管理）
        stateFactory.Add(Screen.Login, Function() New LoginScreenState())
        stateFactory.Add(Screen.Home, Function() New HomeScreenState())
        stateFactory.Add(Screen.Settings, Function() New SettingsScreenState())
        stateFactory.Add(Screen.Profile, Function() New ProfileScreenState())
        stateFactory.Add(Screen.AdminDashboard, Function() New AdminDashboardState())
        stateFactory.Add(Screen.UserDashboard, Function() New UserDashboardState())
    End Sub
    
    ' 疎結合な遷移メソッド
    Public Sub NavigateTo(destination As Screen)
        If stateFactory.ContainsKey(destination) Then
            Dim newState = stateFactory(destination)()
            ChangeState(newState)
        Else
            Throw New ArgumentException($"Unknown screen: {destination}")
        End If
    End Sub
    
    Private Sub ChangeState(newState As IScreenState)
        If currentState IsNot Nothing Then
            currentState.Exit(Me)
        End If
        
        currentState = newState
        currentState.Enter(Me)
    End Sub
    
    ' State が使用する公開メソッド
    Public Sub ShowUserControl(control As UserControl)
        contentPanel.Controls.Clear()
        contentPanel.Controls.Add(control)
        control.Dock = DockStyle.Fill
        control.Visible = True
    End Sub
    
    Public Sub AddTitleButton(button As Button)
        RemoveTitleButton()
        customTitleButton = button
        titlePanel.Controls.Add(button)
        button.Location = New Point(titlePanel.Width - button.Width - 10, 5)
    End Sub
    
    Public Sub RemoveTitleButton()
        If customTitleButton IsNot Nothing Then
            titlePanel.Controls.Remove(customTitleButton)
            customTitleButton.Dispose()
            customTitleButton = Nothing
        End If
    End Sub
    
    Public ReadOnly Property Form As MainForm
        Get
            Return mainForm
        End Get
    End Property
End Class
```

### 3. State インターフェース

```vb
Public Interface IScreenState
    Sub Enter(context As ScreenContext)
    Sub [Exit](context As ScreenContext)
End Interface
```

### 4. 具体的な State 実装

#### 通常の画面（ボタンなし）

```vb
Public Class HomeScreenState
    Implements IScreenState
    
    Private userControl As HomeScreenUserControl
    Private context As ScreenContext
    
    Public Sub Enter(context As ScreenContext) Implements IScreenState.Enter
        Me.context = context
        
        If userControl Is Nothing Then
            userControl = New HomeScreenUserControl()
            ' イベント購読
            AddHandler userControl.NavigationRequested, AddressOf OnNavigationRequested
        End If
        
        context.ShowUserControl(userControl)
    End Sub
    
    Public Sub [Exit](context As ScreenContext) Implements IScreenState.Exit
        ' イベント解除
        RemoveHandler userControl.NavigationRequested, AddressOf OnNavigationRequested
        Me.context = Nothing
    End Sub
    
    ' ✅ 疎結合：列挙型で遷移先を指定
    Private Sub OnNavigationRequested(destination As Screen)
        context.NavigateTo(destination)
    End Sub
End Class
```

#### 設定ボタンが必要な画面

```vb
Public Class SettingsScreenState
    Implements IScreenState
    
    Private userControl As SettingsScreenUserControl
    Private settingsButton As Button
    Private context As ScreenContext
    
    Public Sub Enter(context As ScreenContext) Implements IScreenState.Enter
        Me.context = context
        
        ' UserControl の表示
        If userControl Is Nothing Then
            userControl = New SettingsScreenUserControl()
            AddHandler userControl.SaveRequested, AddressOf OnSaveRequested
        End If
        context.ShowUserControl(userControl)
        
        ' タイトルボタンの追加
        If settingsButton Is Nothing Then
            settingsButton = New Button()
            settingsButton.Text = "詳細設定"
            settingsButton.Size = New Size(80, 30)
            AddHandler settingsButton.Click, AddressOf OnDetailSettingsClick
        End If
        context.AddTitleButton(settingsButton)
    End Sub
    
    Public Sub [Exit](context As ScreenContext) Implements IScreenState.Exit
        context.RemoveTitleButton()
        RemoveHandler userControl.SaveRequested, AddressOf OnSaveRequested
        Me.context = Nothing
    End Sub
    
    Private Sub OnDetailSettingsClick(sender As Object, e As EventArgs)
        MessageBox.Show("詳細設定を開きます")
    End Sub
    
    Private Sub OnSaveRequested()
        ' 保存処理後、ホームへ遷移
        context.NavigateTo(Screen.Home)
    End Sub
End Class
```

#### ビジネスロジック駆動の遷移例

```vb
Public Class LoginScreenState
    Implements IScreenState
    
    Private userControl As LoginUserControl
    Private context As ScreenContext
    
    Public Sub Enter(context As ScreenContext) Implements IScreenState.Enter
        Me.context = context
        
        If userControl Is Nothing Then
            userControl = New LoginUserControl()
            AddHandler userControl.LoginAttempted, AddressOf OnLoginAttempted
        End If
        
        context.ShowUserControl(userControl)
    End Sub
    
    Public Sub [Exit](context As ScreenContext) Implements IScreenState.Exit
        RemoveHandler userControl.LoginAttempted, AddressOf OnLoginAttempted
        Me.context = Nothing
    End Sub
    
    Private Sub OnLoginAttempted(username As String, password As String)
        Dim result = AuthService.Login(username, password)
        
        If result.Success Then
            ' ✅ ビジネスロジックに基づいて遷移先を決定
            If result.User.IsAdmin Then
                context.NavigateTo(Screen.AdminDashboard)
            Else
                context.NavigateTo(Screen.UserDashboard)
            End If
        Else
            userControl.ShowError(result.ErrorMessage)
        End If
    End Sub
End Class
```

### 5. UserControl（疎結合な実装）

```vb
Public Class HomeScreenUserControl
    ' ✅ 遷移先を列挙型で通知（具象クラスを知らない）
    Public Event NavigationRequested(destination As Screen)
    
    Private Sub SettingsButton_Click(sender As Object, e As EventArgs) Handles SettingsButton.Click
        RaiseEvent NavigationRequested(Screen.Settings)
    End Sub
    
    Private Sub ProfileButton_Click(sender As Object, e As EventArgs) Handles ProfileButton.Click
        RaiseEvent NavigationRequested(Screen.Profile)
    End Sub
End Class

Public Class LoginUserControl
    ' ✅ ビジネスイベントのみ通知
    Public Event LoginAttempted(username As String, password As String)
    
    Private Sub LoginButton_Click(sender As Object, e As EventArgs) Handles LoginButton.Click
        RaiseEvent LoginAttempted(UsernameTextBox.Text, PasswordTextBox.Text)
    End Sub
    
    Public Sub ShowError(message As String)
        ErrorLabel.Text = message
        ErrorLabel.Visible = True
    End Sub
End Class
```

### 6. MainForm（最小限の責任）

```vb
Public Class MainForm
    Private screenContext As ScreenContext
    
    Private Sub MainForm_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        ' Context の初期化
        screenContext = New ScreenContext(Me, ContentPanel, TitlePanel)
        
        ' 初期画面の表示
        screenContext.NavigateTo(Screen.Login)
    End Sub
    
    ' グローバルナビゲーション（メニューバーなど）のみ担当
    Private Sub MenuHome_Click(sender As Object, e As EventArgs) Handles MenuHome.Click
        screenContext.NavigateTo(Screen.Home)
    End Sub
    
    Private Sub MenuSettings_Click(sender As Object, e As EventArgs) Handles MenuSettings.Click
        screenContext.NavigateTo(Screen.Settings)
    End Sub
    
    Private Sub MenuLogout_Click(sender As Object, e As EventArgs) Handles MenuLogout.Click
        screenContext.NavigateTo(Screen.Login)
    End Sub
End Class
```

## さらなる改善：NavigationService の導入

より洗練された実装として、NavigationService を導入することもできます。

```vb
Public Interface INavigationService
    Sub NavigateTo(destination As Screen)
    Sub NavigateBack()
    ReadOnly Property CanGoBack As Boolean
End Interface

Public Class NavigationService
    Implements INavigationService
    
    Private context As ScreenContext
    Private history As New Stack(Of Screen)()
    
    Public Sub New(context As ScreenContext)
        Me.context = context
    End Sub
    
    Public Sub NavigateTo(destination As Screen) Implements INavigationService.NavigateTo
        If context.CurrentScreen <> destination Then
            history.Push(context.CurrentScreen)
        End If
        context.NavigateTo(destination)
    End Sub
    
    Public Sub NavigateBack() Implements INavigationService.NavigateBack
        If history.Count > 0 Then
            Dim previous = history.Pop()
            context.NavigateTo(previous)
        End If
    End Sub
    
    Public ReadOnly Property CanGoBack As Boolean Implements INavigationService.CanGoBack
        Get
            Return history.Count > 0
        End Get
    End Property
End Class

' Context に組み込み
Public Class ScreenContext
    Private navigationService As INavigationService
    
    Public ReadOnly Property Navigation As INavigationService
        Get
            Return navigationService
        End Get
    End Property
    
    Public Sub New(form As MainForm, content As Panel, title As Panel)
        ' ... 初期化 ...
        navigationService = New NavigationService(Me)
    End Sub
End Class

' State 側での使用
Private Sub OnBackButtonClick()
    If context.Navigation.CanGoBack Then
        context.Navigation.NavigateBack()
    End If
End Sub
```

## 責任分担の明確化

| コンポーネント | 責任 | やってはいけないこと |
|---------------|------|---------------------|
| **MainForm** | UI要素の配置、グローバルナビゲーション | 遷移ロジック、State の管理 |
| **ScreenContext** | 遷移マッピング管理、State のライフサイクル | ビジネスロジック |
| **State** | 画面固有の振る舞い、遷移条件の判断 | 他の State を直接 new |
| **UserControl** | データ表示・入力、イベント通知 | 遷移先の決定 |

## テストしやすい設計

この設計により、各コンポーネントの単体テストが容易になります。

```vb
<TestClass>
Public Class LoginScreenStateTests
    <TestMethod>
    Public Sub LoginSuccess_Admin_NavigatesToAdminDashboard()
        ' Arrange
        Dim mockContext As New Mock(Of ScreenContext)()
        Dim state As New LoginScreenState()
        state.Enter(mockContext.Object)
        
        ' Act
        ' ログイン成功（管理者）をシミュレート
        RaiseEvent state.UserControl.LoginAttempted("admin", "password")
        
        ' Assert
        mockContext.Verify(Sub(c) c.NavigateTo(Screen.AdminDashboard), Times.Once)
    End Sub
End Class
```

## まとめ

### ✅ この設計の利点

1. **疎結合**
   - State は具象クラスを知らず、列挙型で遷移先を指定
   - UserControl は遷移ロジックから完全に分離

2. **単一責任の原則**
   - 各コンポーネントが明確な責任を持つ
   - 遷移マッピングは ScreenContext に一元化

3. **拡張性**
   - 新しい画面追加時は State と列挙型を追加するだけ
   - 既存コードの変更が最小限

4. **テスタビリティ**
   - 各コンポーネントが独立してテスト可能
   - モックを使った単体テストが容易

### 🎯 設計の鉄則

**「State は『どこに行きたいか』を伝えるだけ、『どうやって行くか』は Context が決める」**

この原則により、真に保守性の高いステートパターンが実現できます。

## 参考リンク

- [State パターン - Wikipedia](https://ja.wikipedia.org/wiki/State_%E3%83%91%E3%82%BF%E3%83%BC%E3%83%B3)
- [デザインパターン（GoF）](https://ja.wikipedia.org/wiki/%E3%83%87%E3%82%B6%E3%82%A4%E3%83%B3%E3%83%91%E3%82%BF%E3%83%BC%E3%83%B3_(%E3%82%BD%E3%83%95%E3%83%88%E3%82%A6%E3%82%A7%E3%82%A2))

---

この記事が VB.NET での画面遷移実装の参考になれば幸いです。
ご質問やフィードバックがあれば、コメント欄でお気軽にお寄せください！
