# WinForms × MVVM 責任分離まとめ（VB.NET）

DI・インターフェース分離・ViewModel と View の境界について整理した設計ノート。
WinForms（VB.NET）を前提に、これまで議論した内容と追加論点をまとめる。

---

## 0. 全体を貫く一つの原則

> **ViewModel は「データと状態」を持つ。View は「描画と UI 操作」を持つ。**
> ViewModel が UI 部品（Form / Panel / DataGridView / Color…）の型や存在を知った時点で境界は崩れている。

判断に迷ったら、ViewModel に渡そうとしているもの・公開しようとしているものの
**語彙に UI 部品名が出てくるか** を見る。出てきたら NG。

---

## 1. DI は「依存の注入方法」であって「依存の設計」ではない

### よくある誤解

書籍では「DI を導入すると依存関係が逆転する（DIP）」と説明される。
しかし **DI を導入しただけでは本質的な問題は解決しない。**

| DI が解決すること | DI が解決しないこと |
|---|---|
| オブジェクト生成・解決の外部化 | クラスの責任配分（何をどこが持つか） |
| 具象依存をコンストラクタ注入に変える | インターフェースの粒度・凝集度 |
| テスト時のモック差し替え | ロジック同士の本質的な絡み合い |

### なぜ「IF を分離しても修正が波及する」のか

元のコードの結合度が高いまま機械的にインターフェースを抽出すると、
その IF は **実装の都合をそのまま写し取った漏れのある抽象（Leaky Abstraction）** になる。
概念ではなく実装に縛られた IF なので、1 つのロジック修正が IF ごと波及する。

### DIP の本質

DIP は「矢印の向きを変えること」自体が目的ではなく、
**安定した抽象（＝ドメインの概念）に依存させること** が目的。
抽象が不安定なら逆転させても脆さは変わらない。

### 正しい順序

```
1. 責任分離（SRP）          ← まずここ
2. 凝集度の高い境界の発見
3. 安定した抽象の抽出
4. DI で配線               ← 最後
```

DI から入ると、悪い境界を固定化してしまい逆効果。
属人化した保守ノウハウも、境界が概念として整理されていなければ DI では解けない。

---

## 2. グリッドの更新は ViewModel でやってよいか

**「更新」が何を指すかで変わる。**

### NG：ViewModel が UI コントロールを直接触る

```vb
' ❌ ViewModel が DataGridView を知っている
Public Class OrderViewModel
    Private ReadOnly _grid As DataGridView   ' UI型への依存 = 境界崩壊

    Public Sub Refresh()
        _grid.Rows.Clear()
        For Each o In _orders
            _grid.Rows.Add(o.Id, o.Name)     ' テスト不能・UI差し替え不能
        Next
    End Sub
End Class
```

### OK：ViewModel はデータを更新し、通知を出すだけ

WinForms では `BindingList(Of T)` + `BindingSource` が現実解。

```vb
' ✅ ViewModel は BindingList を更新するだけ。DataGridView を知らない
Public Class OrderViewModel
    Public ReadOnly Property Orders As New BindingList(Of OrderRowModel)()

    Public Sub Load(source As IEnumerable(Of OrderRowModel))
        Orders.Clear()
        For Each o In source
            Orders.Add(o)
        Next
    End Sub
End Class
```

```vb
' View（コードビハインド）側でバインドするだけ
Private Sub OrderControl_Load(sender As Object, e As EventArgs) Handles MyBase.Load
    bindingSource.DataSource = _viewModel.Orders
    grid.DataSource = bindingSource
End Sub
```

列幅・セル色などコントロール固有の描画制御は View（コードビハインド）の責任として残す。

---

## 3. 選択行の情報を UI から ViewModel へどう渡すか

**向き：View が UI イベントを拾い、抽出したデータを ViewModel に渡す。**
ViewModel に `DataGridViewRow` を渡してはいけない。

```vb
' ✅ View が DataBoundItem からモデルを取り出して渡す
Private Sub grid_SelectionChanged(sender As Object, e As EventArgs) Handles grid.SelectionChanged
    Dim row = grid.CurrentRow
    If row IsNot Nothing AndAlso TypeOf row.DataBoundItem Is OrderRowModel Then
        _viewModel.SelectedItem = DirectCast(row.DataBoundItem, OrderRowModel)
    End If
End Sub
```

```vb
' ✅ ViewModel は UI 非依存のモデルを受け取るだけ
Public Class OrderViewModel
    Public Property SelectedItem As OrderRowModel
    ' 複数選択なら SelectedItems As IList(Of OrderRowModel)
    ' ID だけで足りるなら SelectedId As Integer
End Class
```

### 避けたい形

```vb
' ❌ UI 型が引数に出てきた時点で境界崩壊
Public Sub OnGridSelectionChanged(grid As DataGridView)
```

ポイント：**ViewModel が UI へ問い合わせに行く（pull）のではなく、View が変化を通知する（push）。**
選択行の「行番号や見た目」が業務ロジックに必要になったら設計を疑うサイン。
たいていモデルに持つべき状態が漏れている。

---

## 4. 変更不可列の背景色をタブ毎に切り替える：誰が持つか

責任を二つに分ける：**「どういう状態か（判定）」と「どう見せるか（描画）」。**

| 関心事 | 担当 | 持つもの |
|---|---|---|
| この列は編集可能か / 今どのタブか | ViewModel | `Boolean` / `Enum`（UI 非依存の語彙） |
| 変更不可ならこの色で塗る | View | `Color`（UI 依存の語彙） |

### ViewModel：意味論的な状態まで

```vb
Public Enum ColumnState
    Editable
    [ReadOnly]
End Enum

Public Class GridViewModel
    Public Property CurrentTab As TabKind

    ' どのタブでどの列が不可か、という判定ロジックは ViewModel の中
    Public Function GetColumnState(columnName As String) As ColumnState
        Select Case CurrentTab
            Case TabKind.Summary
                Return If(columnName = "Price", ColumnState.ReadOnly, ColumnState.Editable)
            Case Else
                Return ColumnState.Editable
        End Select
    End Function
End Class
```

### View：状態を色に翻訳する辞書を持つ

```vb
Private Shared ReadOnly ReadOnlyBack As Color = Color.FromArgb(240, 240, 240)

Private Sub grid_CellFormatting(sender As Object, e As DataGridViewCellFormattingEventArgs) _
        Handles grid.CellFormatting
    Dim colName = grid.Columns(e.ColumnIndex).Name
    If _viewModel.GetColumnState(colName) = ColumnState.ReadOnly Then
        e.CellStyle.BackColor = ReadOnlyBack
    End If
End Sub

' タブが変わったら ViewModel の状態を更新し、再描画させるだけ
Private Sub tabControl_SelectedIndexChanged(sender As Object, e As EventArgs) _
        Handles tabControl.SelectedIndexChanged
    _viewModel.CurrentTab = GetTabKind(tabControl.SelectedTab)
    grid.Invalidate()   ' CellFormatting が走り直し、最新タブで塗り直される
End Sub
```

### なぜこの線引きか

`Color`（`System.Drawing.Color`）を ViewModel に置くと、ViewModel が UI に依存し始める。
ViewModel は `Enum` / `Boolean` で状態を語り、**色への翻訳辞書は View が持つ。**

判断基準：色を変えたい理由が **業務ルール**（このタブのこの列は編集禁止）なら判定は ViewModel、
**単なる見やすさ** なら View に寄せてよい。

---

## 5. DB 排他ロック状態パネルを ViewModel から更新したい

### 状況

ロック状態パネルを Form が持ち、ViewModel は Form に動的に貼り付けられる
UserControl のコンストラクタで渡されている。
「ロックパネルの値を変更する IF」を ViewModel のコンストラクタに渡してよいか？

### 結論：NG

```vb
' ❌ UI 部品名（Panel）が IF の語彙に出てくる = Leaky Abstraction
Public Interface ILockPanelView
    Sub SetLocked(isLocked As Boolean)
End Interface

Public Class EditViewModel
    Private ReadOnly _lockPanel As ILockPanelView   ' Viewの構造を知ってしまう
    Public Sub New(lockPanel As ILockPanelView)
        _lockPanel = lockPanel
    End Sub
End Class
```

抽象化したつもりでも「ロックパネルという UI 部品が存在する」前提を写し取っているだけ。
Form 側の UI 都合（パネルの有無・表示方法）が変わると IF ごと直すはめになる。
**向きも逆**（ViewModel が View を更新しに行っている）。

### あるべき形：ViewModel は状態を持って通知、View が購読

```vb
' ✅ ViewModel は UI を一切知らない。状態を持って通知するだけ
Public Class EditViewModel
    Implements INotifyPropertyChanged

    Private _isDbLocked As Boolean
    Public Property IsDbLocked As Boolean
        Get
            Return _isDbLocked
        End Get
        Private Set(value As Boolean)
            If _isDbLocked <> value Then
                _isDbLocked = value
                RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs(NameOf(IsDbLocked)))
            End If
        End Set
    End Property

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged
End Class
```

```vb
' ✅ パネルを持つ Form / UserControl が購読して表示を更新する
AddHandler _viewModel.PropertyChanged,
    Sub(s, e)
        If e.PropertyName = NameOf(_viewModel.IsDbLocked) Then
            ParentForm.UpdateLockPanel(_viewModel.IsDbLocked)
        End If
    End Sub
```

### さらに：ロック状態はアプリ共通の状態かもしれない

動的に貼り付く UserControl の ViewModel が各自で親 Form のパネルを書きに行く設計は、
複数コントロールがある場合に **誰が真実（Single Source of Truth）を持つのか** が曖昧になる。

ロック状態が DB 接続単位＝アプリ共通なら、共有の状態オブジェクトを一つ用意し、
ViewModel もパネルもそれを購読する：

```
DbLockState（共有 / 通知を出す）
   ├─ ViewModel が購読（業務判断に使う）
   └─ Form のパネルが購読（表示する）
```

```vb
' 共有のロック状態（シングルトン or DI で単一インスタンス共有）
Public Class DbLockState
    Implements INotifyPropertyChanged

    Private _isLocked As Boolean
    Public Property IsLocked As Boolean
        Get
            Return _isLocked
        End Get
        Set(value As Boolean)
            If _isLocked <> value Then
                _isLocked = value
                RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs(NameOf(IsLocked)))
            End If
        End Set
    End Property

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged
End Class
```

誰も他人の UI を直接触らずに済む。

---

## 6.（追加）コマンドの扱い — ボタン押下をどう渡すか

WinForms には WPF の `ICommand` バインディングが標準で無いので、
View がイベントを拾って ViewModel のメソッドを呼ぶ。
**ただし「実行可能かどうか」の判定は ViewModel が持つ。**

```vb
Public Class EditViewModel
    Public ReadOnly Property CanSave As Boolean
        Get
            Return Not IsDbLocked AndAlso HasChanges
        End Get
    End Property

    Public Sub Save()
        If Not CanSave Then Return
        ' 保存ロジック（ドメイン / アプリケーション層へ委譲）
    End Sub
End Class
```

```vb
' View：押下を渡すだけ。活性制御は CanSave を反映するだけ
Private Sub saveButton_Click(sender As Object, e As EventArgs) Handles saveButton.Click
    _viewModel.Save()
End Sub

Private Sub RefreshCommandStates()
    saveButton.Enabled = _viewModel.CanSave
End Sub
```

簡易な `RelayCommand` 相当を自作して `Button.Enabled` と束ねる方法もあるが、
小規模なら上記で十分。重要なのは **活性判定ロジックが View に散らばらないこと。**

---

## 7.（追加）UI スレッドへのマーシャリング

ViewModel の状態変更が別スレッド（DB アクセス、非同期処理）から来る場合、
`PropertyChanged` を購読した **View 側で** UI スレッドに戻す。
ViewModel に `Control.Invoke` を書かせない（また UI 依存になる）。

```vb
' View 側で UI スレッドへ戻す
AddHandler _viewModel.PropertyChanged,
    Sub(s, e)
        If Me.InvokeRequired Then
            Me.BeginInvoke(Sub() OnViewModelChanged(e.PropertyName))
        Else
            OnViewModelChanged(e.PropertyName)
        End If
    End Sub
```

ViewModel は「いつスレッドが切り替わるか」を知らないままでいられる。

---

## 8.（追加）イベント購読の解除（メモリリーク対策）

動的に貼り付け／破棄される UserControl が共有オブジェクト（`DbLockState` など）を
購読する場合、**購読しっぱなしだと共有オブジェクトが UserControl を参照し続け、GC されない。**
破棄時に必ず解除する。

```vb
Protected Overrides Sub Dispose(disposing As Boolean)
    If disposing Then
        RemoveHandler _dbLockState.PropertyChanged, AddressOf OnLockChanged
        components?.Dispose()
    End If
    MyBase.Dispose(disposing)
End Sub
```

短命な View が長命なオブジェクトを購読するときは、必ず解除責任をセットで考える。

---

## 9.（追加）テスト可能性チェックリスト

ここまでの境界が守れていれば、ViewModel は WinForms 参照なしで単体テストできる。

- [ ] ViewModel のプロジェクトが `System.Windows.Forms` / `System.Drawing` を参照していない
- [ ] ViewModel のメソッド・プロパティの引数/戻り値に UI 型が出てこない
- [ ] 選択状態・ロック状態などをコードから直接セットして検証できる
- [ ] 「実行可能か」「列が編集可能か」の判定を UI 無しで呼び出せる

```vb
' UI 無しで判定ロジックをテストできる
<TestMethod>
Public Sub Price列はSummaryタブで編集不可()
    Dim vm As New GridViewModel With {.CurrentTab = TabKind.Summary}
    Assert.AreEqual(ColumnState.ReadOnly, vm.GetColumnState("Price"))
End Sub
```

このチェックリストを通らない箇所が、**属人化・保守困難の温床** になっている可能性が高い。

---

## まとめ：一枚の早見表

| やりたいこと | ViewModel | View |
|---|---|---|
| データ更新 | `BindingList(Of T)` を更新 | バインドして自動再描画 |
| 選択行を渡す | UI 非依存モデルを受け取る | `DataBoundItem` から抽出して渡す |
| 列の色をタブ毎に変える | 編集可否を `Enum` で判定 | `Enum` → `Color` 翻訳・塗布 |
| ロック状態表示 | 状態を持ち通知 / 共有状態を購読 | 通知を購読してパネル更新 |
| ボタン押下 | 実行＋活性判定（`CanXxx`） | 押下を渡す・`Enabled` 反映 |
| 別スレッド更新 | スレッドを意識しない | `Invoke` で UI スレッドへ |

**判断基準は常に一つ：その語彙に UI 部品名（Form / Panel / DataGridView / Color）が出てくるか。**
出てきたら境界が崩れている。
