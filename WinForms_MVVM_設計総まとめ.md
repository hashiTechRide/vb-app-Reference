# WinForms × MVVM 設計総まとめ（VB.NET / C1FlexGrid / Oracle）

基準項目・大・中・小の4タブ構成、編集／削除／復元モード、DB排他ロックを持つ
WinForms 業務画面の設計ノート。これまでの議論を、後半（より洗練された結論）に
比重を置いて再構成し、データ取得層・全体クラス構成・DB操作・検証・画面遷移制御を
新たに加えた。

---

## 0. 全体を貫く一つの原則

> **ViewModel は「データと状態と業務判断」を持つ。View は「描画とUI操作」を持つ。**
> 迷ったら、渡そうとしている／公開しようとしているものの語彙に
> UI部品名（Form / Panel / Grid / Color / DataGridView）が出てくるかを見る。
> 出てきたら境界が崩れている。

判断の分かれ目は常に **「判断（業務）」と「反映・操作（UI機構）」を割る** こと。
これが以下すべてのセクションに通底する。

---

# 第1部 前提（参考程度・既に確定した結論）

詳細な経緯は省き、確定した結論だけを並べる。後半の設計はこれらを前提にしている。

## 1.1 DI は依存の「注入方法」であって「設計」ではない

- DI / DIP を入れても、元コードの結合度が高いままなら、抽出した IF は
  実装を写し取った **漏れのある抽象（Leaky Abstraction）** になり、修正が IF ごと波及する。
- 正しい順序：**責任分離(SRP) → 凝集度の高い境界の発見 → 安定した抽象の抽出 → DIで配線**。
  DI から入ると悪い境界を固定化する。

## 1.2 グリッド更新・選択行の受け渡し

- ViewModel は `BindingList(Of T)` を更新し通知するだけ。`DataGridView` / `C1FlexGrid` を直接触らない。
- 選択行は View が `DataBoundItem` からモデルを取り出し、UI非依存のモデルとして ViewModel に渡す。
  `OnGridSelectionChanged(grid As ...)` のように UI 型を引数に出さない。

## 1.3 色・編集可否は「判定」と「描画」を割る

- 「編集可能か」「どのタブか」の**判定**は ViewModel（`Enum` / `Boolean` で語る）。
- `Enum → Color` の**翻訳辞書**と塗布は View 側。ViewModel に `System.Drawing.Color` を持たせない。

## 1.4 共有横断状態は専用クラスに追い出す

- DBロック状態・モードのような全タブ共通の状態は、各 ViewModel が個別に持つと真実が分裂する。
- **単一の真実（Single Source of Truth）** を共有オブジェクトにし、各 ViewModel と View が購読する。
- ViewModel から「親FormのパネルをUI型のIFで更新しに行く」のは NG（向きが逆／UI語彙が漏れる）。
  ViewModel は状態を通知し、View が購読して表示する。

---

# 第2部 本論（後半の議論・主たる設計）

## 2. インターフェース構成（基準項目とそれ以外の差異吸収）

ViewModel には3つの関心事が混在しがち。分離して扱う。

1. 共通の横断機能（ロック通知・アクション）
2. 編集モードの違い（単一レコード編集 vs リスト編集）
3. タブ固有の個別機能（動的アクションボタン）

```vb
' 全ViewModelが実装する共通の最小契約
Public Interface IEditorViewModel
    Inherits INotifyPropertyChanged
    ReadOnly Property LockInfo As DbLockInfo
    ReadOnly Property Actions As IReadOnlyList(Of EditorAction)
End Interface

' 基準項目：単一レコード編集
Public Interface ISingleRecordViewModel
    Inherits IEditorViewModel
    Property Current As RecordModel
End Interface

' 大・中・小：一つ左の項目に紐づくリストを基準項目単位で編集
Public Interface IListEditorViewModel
    Inherits IEditorViewModel
    ReadOnly Property Items As BindingList(Of RecordModel)
    Property ParentKey As Long   ' 一つ左の項目のキー
End Interface
```

**Form のローカル変数は共通契約で持つ。** これで型名の悩みが消える。

```vb
Private _activeViewModel As IEditorViewModel   ' 素直な名前で済む
```

単一／リスト固有の操作が要る箇所だけ、その場で型分岐・キャストする。
Form が頻繁に分岐するなら、それはタブごとの UserControl が自分の ViewModel 型を
知るべきサイン。

### アクション（動的ボタン）

```vb
Public Class EditorAction
    Public Property Text As String           ' ボタン表示テキスト
    Public Property Name As String           ' ボタンのName
    Public Property Execute As Action         ' クリック時処理（Actionは紛らわしいのでExecute）
    Public Property CanExecute As Func(Of Boolean) = Function() True
End Class
```

動的ボタン生成時の注意：**クロージャのキャプチャ事故を避けるため `Tag` に持たせて共通ハンドラで取り出す**。
再Load時の二重追加を防ぐため生成前に `Clear`。ロック中は活性を落とす。

---

## 3. モードの状態機械（編集／削除／復元）

- 最初は編集モード。削除・復元は **編集モードからのみ** 遷移可。
- 保存／キャンセルボタンの意味がモードで変わる：
  - 編集モード → 画面終了
  - 削除・復元モード → 編集モードへ戻る

モードは全タブ共通の横断状態。**共有 `EditorModeState` に1つの真実として持ち、遷移ルールを閉じ込める。**

```vb
Public Enum EditorMode
    Edit
    Delete
    Restore
End Enum

Public Class EditorModeState
    Implements INotifyPropertyChanged

    Private _mode As EditorMode = EditorMode.Edit   ' 最初は編集モード

    Public Property Mode As EditorMode
        Get
            Return _mode
        End Get
        Private Set(value As EditorMode)
            If _mode <> value Then
                _mode = value
                RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs(NameOf(Mode)))
            End If
        End Set
    End Property

    Public Sub EnterDelete()
        If _mode <> EditorMode.Edit Then _
            Throw New InvalidOperationException("削除モードは編集モードからのみ遷移できます")
        Mode = EditorMode.Delete
    End Sub

    Public Sub EnterRestore()
        If _mode <> EditorMode.Edit Then _
            Throw New InvalidOperationException("復元モードは編集モードからのみ遷移できます")
        Mode = EditorMode.Restore
    End Sub

    Public Sub BackToEdit()
        Mode = EditorMode.Edit
    End Sub

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged
End Class
```

保存・キャンセルの「次に何をするか」をモード起点の1メソッドに集約し、`If` の散在を防ぐ。
画面終了は ViewModel が `RequestClose` イベントで依頼し、Form が閉じる（境界維持）。

```vb
Private Sub AfterAction()
    If _modeState.Mode = EditorMode.Edit Then
        RaiseEvent RequestClose(Me, EventArgs.Empty)   ' Formが受けて Me.Close()
    Else
        _modeState.BackToEdit()
    End If
End Sub

Public Sub OnSave()
    PersistChanges()
    AfterAction()
End Sub

Public Sub OnCancel()
    AfterAction()
End Sub
```

ボタンのラベル・活性はモード変更通知で再計算。**ロック状態とのAND**で1箇所に集約する
（モード的に押せる ∧ ロックされていない）。

---

## 4. 自前タブUI（標準TabControl不使用）と貼り付けロジック

上部にタブ表現のボタン、中央に `Dock=Fill` のパネル。各タブの UserControl は**保持して切替**。

```vb
Public Class MainForm
    Private ReadOnly _controls As New Dictionary(Of TabKind, UserControl)
    Private _activeControl As UserControl

    Private Sub MainForm_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        _controls(TabKind.Standard) = New StandardEditorControl()
        _controls(TabKind.Large)    = New ListEditorControl()
        _controls(TabKind.Medium)   = New ListEditorControl()
        _controls(TabKind.Small)    = New ListEditorControl()

        For Each kv In _controls
            Dim uc = kv.Value
            uc.Dock = DockStyle.Fill
            uc.Visible = False
            contentPanel.Controls.Add(uc)     ' 全部重ねて積んでおく
        Next

        ActivateTab(TabKind.Standard)
    End Sub

    Private Sub ActivateTab(kind As TabKind)
        Dim target = _controls(kind)
        If ReferenceEquals(target, _activeControl) Then Return

        If _activeControl IsNot Nothing Then _activeControl.Visible = False
        target.Visible = True
        target.BringToFront()
        _activeControl = target
        UpdateTabButtonStyles(kind)
    End Sub

    Private Sub TabButton_Click(sender As Object, e As EventArgs) _
            Handles standardTabButton.Click, largeTabButton.Click,
                    mediumTabButton.Click, smallTabButton.Click
        ActivateTab(DirectCast(DirectCast(sender, Button).Tag, TabKind))
    End Sub
End Class
```

**`Visible` 切替方式**を推奨（生成1回・購読1回、状態とハンドルが保たれ再表示が速い）。
`Add/Remove` 方式は保持方針と噛み合わずメリットが薄い。チラつきは `DoubleBuffered` パネルで軽減。

### イベントハンドラの扱い

保持方式なら **生成時に購読・破棄時に解除の2箇所だけ**で済み、切替でハンドラ操作が発生しない。
裏タブの通知は `ReferenceEquals(sender, _activeViewModel)` で無視。
どうしても毎回 `New` するなら、解除→差替→購読を1メソッドに閉じ、**必ず `AddressOf`**
（ラムダ購読は `RemoveHandler` で外せずリークする）。

---

## 5. Form / UserControl / Grid / ViewModel の分担

**Form から grid を直接操作しない。** 配置階層は以下。

```
MainForm
   ├─ 共有資源を生成・保持・配布（OracleDbContext / DbLockState / EditorModeState / RecordLockService）
   ├─ タブ切替（UserControlのVisible制御）
   └─ contentPanel
         └─ UserControl（タブごとに保持）
               ├─ ViewModel を束ねる（橋渡し）
               └─ EditableFlexGrid（カスタムグリッド）
```

| 層 | 責任 | 持たないもの |
|---|---|---|
| Form | タブ切替、共有資源の生成・配布、ロック取得/解放 | gridの操作、業務ロジック |
| UserControl | grid↔ViewModelの**橋渡し**、通知購読→再描画 | 業務ロジック（薄く保つ） |
| カスタムグリッド | セル描画・編集可否反映・セル移動・入力制限 | 業務ルールそのもの |
| ViewModel | 状態・業務判断・検証・保存 | UI型（Form/Grid/Color） |

Form が UserControl 内部の grid に手を伸ばすと、Form がタブの内部構造に依存して境界が崩れる。
Form から見えるのは UserControl の公開IFまで。共有したい状態は Form が配り、各 grid が購読して
自分で塗り直す。

---

## 6. カスタムグリッド（C1FlexGrid継承）に置いてよいもの

**機構（UI操作）はグリッド、判断（業務）はViewModel。**

グリッドに置く：セル移動（Enter/Tab/矢印）、コピペ、編集開始/確定、入力制限、背景色の塗布。
ViewModel に残す：編集可否・色の**判断根拠**、値の検証、保存可否。

状態は ViewModel 型を直接知らせず、薄い窓口 `ICellStateProvider` 経由で受け取る。

```vb
Public Interface ICellStateProvider
    Function GetCellState(rowIndex As Integer, columnName As String) As CellState
End Interface

Public Class CellState
    Public Property Editable As Boolean
    Public Property Background As CellBackground   ' UI非依存の語彙
End Class

Public Enum CellBackground
    Normal
    [ReadOnly]
    Warning
End Enum

Public Class EditableFlexGrid
    Inherits C1FlexGrid

    Private _stateProvider As ICellStateProvider

    Private Shared ReadOnly Backgrounds As New Dictionary(Of CellBackground, Color) From {
        {CellBackground.Normal, Color.White},
        {CellBackground.ReadOnly, Color.FromArgb(240, 240, 240)},
        {CellBackground.Warning, Color.FromArgb(255, 235, 200)}
    }

    Public Sub BindState(provider As ICellStateProvider)
        _stateProvider = provider
        Invalidate()
    End Sub

    ' 描画：状態を色に翻訳して塗る
    Protected Overrides Sub OnOwnerDrawCell(e As OwnerDrawCellEventArgs)
        If _stateProvider IsNot Nothing AndAlso e.Row >= FixedRows Then
            Dim st = _stateProvider.GetCellState(e.Row, Cols(e.Col).Name)
            e.Style.BackColor = Backgrounds(st.Background)
        End If
        MyBase.OnOwnerDrawCell(e)
    End Sub

    ' 読取専用セルは編集開始させない（判断はProvider、操作はグリッド）
    Protected Overrides Sub OnBeforeEdit(e As RowColEventArgs)
        If _stateProvider IsNot Nothing Then
            Dim st = _stateProvider.GetCellState(e.Row, Cols(e.Col).Name)
            If Not st.Editable Then e.Cancel = True
        End If
        MyBase.OnBeforeEdit(e)
    End Sub

    ' 編集確定は外へ通知（値の意味は知らない）
    Public Event CellCommitted As EventHandler(Of CellCommittedEventArgs)
    Protected Overrides Sub OnAfterEdit(e As RowColEventArgs)
        MyBase.OnAfterEdit(e)
        RaiseEvent CellCommitted(Me,
            New CellCommittedEventArgs(e.Row, Cols(e.Col).Name, Me(e.Row, e.Col)))
    End Sub
End Class
```

動的切替は通知→`Invalidate()` で `OnOwnerDrawCell` が走り直す。

### 編集メソッドの置き場所

- セル編集の機構（開始・確定・入力制限・移動・コピペ）→ **カスタムグリッド**
- 値の検証・モデル反映・保存・ロック/モードによる可否 → **ViewModel**
- 両者の配線 → **UserControl（薄く）**

```vb
' UserControl：橋渡しのみ
Private Sub Grid_CellCommitted(sender As Object, e As CellCommittedEventArgs) _
        Handles grid.CellCommitted
    _viewModel.UpdateCell(e.RowIndex, e.ColumnName, e.Value)
End Sub
```

---

## 7. DB排他ロック（基準項目Seq単位で大・中・小を一括ロック）

- ロック単位は **基準項目Seq 1本**。大・中・小はその状態を共有参照するだけ。
- `LockedBy`（誰がロック中か）を表示したいので **ロック管理テーブル方式** を採用
  （`SELECT FOR UPDATE` は保存=コミットでロックが切れて噛み合いにくい）。
- 資源・操作・状態通知を3分離：
  - `OracleDbContext` … 接続（資源）
  - `RecordLockService` … ロックの取得・解放・確認（DB操作）
  - `DbLockState` … ロック状態の通知（UIが購読）

```vb
Public Class DbLockInfo
    Public Property IsLocked As Boolean    ' 自分が編集できない（他者が握っている）
    Public Property LockedBy As String
End Class

Public Class LockResult
    Public Property Acquired As Boolean
    Public Property LockedBy As String
End Class

Public Class RecordLockService
    Private ReadOnly _db As OracleDbContext
    Private ReadOnly _currentUser As String

    Public Sub New(db As OracleDbContext, currentUser As String)
        _db = db
        _currentUser = currentUser
    End Sub

    ' ロック管理テーブルへINSERTを試行（主キー=baseSeq）。
    ' 既存行が自分なら成功扱い（保存ごとの取り直しで自分が弾かれないように）。
    Public Function TryAcquire(baseSeq As Long) As LockResult
        ' 実SQLはテーブル設計に合わせる
    End Function

    Public Sub Release(baseSeq As Long)
        ' 自分のロック行をDELETE
    End Sub
End Class
```

- 開く：baseSeq を1回 `TryAcquire` → `DbLockState.Apply(result)` で全タブに反映。
  取れなければ閲覧専用で開くのが穏当。
- 保存後の取り直し：**ロック者が自分なら成功扱い**にして自分が弾かれないように。
  完全解放→再取得は隙に奪われるので意図（譲る／保持更新）を確認する。
- 閉じる：`Dispose` で確実に `Release`。残留対策に取得時刻で失効させる。

---

# 第3部 追加設計（データ取得層・全体構成・DB操作・検証・遷移制御）

## 8. データ取得層のクラス構成（Repository）

ViewModel に SQL を直書きしない。**データ取得は Repository に分離**し、ViewModel は
Repository を注入されてモデルを受け取るだけにする。これで「DB操作」「業務判断」「UI」が3層に分かれ、
ViewModel が単体テスト可能になる（Repositoryをモックに差し替えられる）。

### 層の構成

```
ViewModel  ──依存──▶  IRepository（抽象）
                         ▲ 実装
                    OracleRepository ──使う──▶ OracleDbContext（接続）
                         └ SQL発行・DataReader→Model 詰め替え
```

### モデル

```vb
Public Class RecordModel
    Public Property Seq As Long
    Public Property ParentSeq As Long      ' 一つ左の階層のSeq
    Public Property Name As String
    Public Property Value As String
    Public Property IsDeleted As Boolean   ' 論理削除フラグ（削除/復元モードで使用）
    ' 変更追跡用
    Public Property RowState As RowEditState
End Class

Public Enum RowEditState
    Unchanged
    Modified
    Added
    Deleted
End Enum
```

### Repositoryの抽象（タブ種別ごとに取得条件が違う）

基準項目は単一レコード、大・中・小は親Seqに紐づくリスト。取得の形が違うのでメソッドを分ける。

```vb
' 基準項目：単一レコード取得
Public Interface IStandardRepository
    Function GetBySeq(baseSeq As Long) As RecordModel
    Sub Update(model As RecordModel)
End Interface

' 大・中・小：親Seqに紐づくリスト取得（共通形）
Public Interface IListRepository
    Function GetByParent(parentSeq As Long) As IList(Of RecordModel)
    Sub BulkSave(models As IEnumerable(Of RecordModel))   ' 追加/更新/削除を一括
End Interface
```

大・中・小は同じ `IListRepository` 形だが、対象テーブルが異なる。実装を分けるか、
テーブル名を注入して1実装を使い回す。

```vb
Public Class OracleListRepository
    Implements IListRepository

    Private ReadOnly _db As OracleDbContext
    Private ReadOnly _tableName As String   ' 大/中/小で differ

    Public Sub New(db As OracleDbContext, tableName As String)
        _db = db
        _tableName = tableName
    End Sub

    Public Function GetByParent(parentSeq As Long) As IList(Of RecordModel) _
            Implements IListRepository.GetByParent
        Dim list As New List(Of RecordModel)
        Using cmd = _db.Connection.CreateCommand()
            cmd.CommandText =
                $"SELECT SEQ, PARENT_SEQ, NAME, VALUE, IS_DELETED " &
                $"FROM {_tableName} WHERE PARENT_SEQ = :p ORDER BY SEQ"
            ' バインド変数で渡す（後述：SQLインジェクション/型安全）
            Dim p = cmd.CreateParameter()
            p.ParameterName = "p"
            p.Value = parentSeq
            cmd.Parameters.Add(p)

            Using reader = cmd.ExecuteReader()
                While reader.Read()
                    list.Add(New RecordModel With {
                        .Seq = reader.GetInt64(0),
                        .ParentSeq = reader.GetInt64(1),
                        .Name = reader.GetString(2),
                        .Value = If(reader.IsDBNull(3), Nothing, reader.GetString(3)),
                        .IsDeleted = (reader.GetInt32(4) = 1),
                        .RowState = RowEditState.Unchanged
                    })
                End While
            End Using
        End Using
        Return list
    End Function

    Public Sub BulkSave(models As IEnumerable(Of RecordModel)) _
            Implements IListRepository.BulkSave
        ' RowStateごとに INSERT/UPDATE/DELETE を振り分け（後述：トランザクション）
    End Sub
End Class
```

### ViewModel は Repository を注入され、取得結果を保持するだけ

```vb
Public Class ListEditorViewModel
    Implements IListEditorViewModel

    Private ReadOnly _repository As IListRepository
    Private ReadOnly _lockState As DbLockState
    Private ReadOnly _modeState As EditorModeState

    Public ReadOnly Property Items As New BindingList(Of RecordModel)()

    Public Sub New(repository As IListRepository,
                   lockState As DbLockState,
                   modeState As EditorModeState)
        _repository = repository
        _lockState = lockState
        _modeState = modeState
    End Sub

    Public Sub Load(parentSeq As Long)
        Items.Clear()
        For Each m In _repository.GetByParent(parentSeq)
            Items.Add(m)
        Next
    End Sub
End Class
```

**ポイント：** Repository が `OracleDbContext` を使い、ViewModel は `IListRepository` しか知らない。
DBの都合（テーブル名・SQL・Oracle固有型）が ViewModel に漏れない。

---

## 9. 全体クラス構成（組み合わせ）

```
┌─────────────────────────── MainForm ───────────────────────────┐
│ 共有資源を生成・保持・配布:                                       │
│   OracleDbContext      （接続・プール）                          │
│   RecordLockService    （ロック取得/解放）                       │
│   DbLockState          （ロック状態通知）                        │
│   EditorModeState      （モード状態通知）                        │
│   各 Repository         （データ取得）                           │
│ タブ切替（UserControl の Visible 制御）                          │
│ RequestClose 受信 → Me.Close()                                  │
└───────────────┬───────────────────────────────────────────────┘
                │ 生成時に注入
   ┌────────────┼───────────────────────────────┐
   ▼            ▼                                ▼
StandardEditorControl     ListEditorControl（大）  ListEditorControl（中/小）
   │  橋渡し                  │  橋渡し
   ▼                         ▼
ISingleRecordViewModel     IListEditorViewModel
   │                         │   ├─ IListRepository（注入）
   │ IStandardRepository     │   ├─ DbLockState（購読）
   │ DbLockState（購読）      │   └─ EditorModeState（購読）
   │ EditorModeState（購読）  │
   ▼                         ▼
EditableFlexGrid          EditableFlexGrid
   （ICellStateProvider 経由で状態取得・描画）

共有状態の流れ:
   DbLockState / EditorModeState
      → 各 ViewModel が購読（業務判断に使う）
      → 各 grid が ICellStateProvider 経由で参照（描画に使う）
      → ロックパネル等の表示も購読

データの流れ:
   Repository → ViewModel(BindingList) → grid(DataSource)
   grid編集確定 → UserControl(橋渡し) → ViewModel.UpdateCell → Model更新(RowState)
   保存 → ViewModel → Repository.BulkSave → DB
```

### 依存方向の原則

```
View（Form/UserControl/Grid） ──▶ ViewModel ──▶ Repository(抽象) ──▶ DbContext
                                       ▲
                       共有状態（DbLockState / EditorModeState）を購読
```

矢印は常に上位→下位（具象→抽象）。下位が上位（UI）を知らない。

---

## 10. Oracle DB操作の具体

### 接続（プール前提）

「Form共通で1インスタンス」は **接続文字列＋プール設定を持つ `OracleDbContext` を共有**する意味にする。
1本の物理接続を握り続けるより、プーリングで都度開閉が定石。

```vb
Public Class OracleDbContext
    Implements IDisposable

    Private ReadOnly _connectionString As String

    Public Sub New(connectionString As String)
        ' 例: "User Id=...;Password=...;Data Source=...;Pooling=true;Min Pool Size=1;Max Pool Size=10;"
        _connectionString = connectionString
    End Sub

    ' トランザクション単位で開く（using で確実に閉じる＝プールに返す）
    Public Function OpenConnection() As OracleConnection
        Dim conn As New OracleConnection(_connectionString)
        conn.Open()
        Return conn
    End Function

    Public Sub Dispose() Implements IDisposable.Dispose
        ' プール自体の破棄が要るなら OracleConnection.ClearPool 等
    End Sub
End Class
```

### バインド変数を必ず使う

文字列連結でSQLを組まない（インジェクション・型不整合・解析負荷）。
`:param` のバインド変数で渡す。Oracleはバインド変数でカーソル共有が効き性能面でも有利。

### 保存はトランザクションで一括

リスト編集は追加・更新・削除が混在する。`RowState` で振り分け、1トランザクションで `BulkSave`。
途中失敗は全ロールバック。

```vb
Public Sub BulkSave(models As IEnumerable(Of RecordModel)) _
        Implements IListRepository.BulkSave
    Using conn = _db.OpenConnection()
        Using tx = conn.BeginTransaction()
            Try
                For Each m In models
                    Select Case m.RowState
                        Case RowEditState.Added
                            ExecInsert(conn, tx, m)
                        Case RowEditState.Modified
                            ExecUpdate(conn, tx, m)
                        Case RowEditState.Deleted
                            ExecDelete(conn, tx, m)
                    End Select
                Next
                tx.Commit()
                ' 成功後、各モデルの RowState を Unchanged に戻す
            Catch
                tx.Rollback()
                Throw
            End Try
        End Using
    End Using
End Sub
```

### 削除・復元モードとの関係

論理削除なら、削除モードの保存は `IS_DELETED=1` への UPDATE、復元モードは `IS_DELETED=0`。
物理削除なら削除モードのみ DELETE。モードに応じて Repository に渡す操作を切り替える。

---

## 11. グリッド・テキストボックスの設定ロジック

### C1FlexGrid 初期設定（列定義・編集可否・書式）

UserControl の初期化で列を構成。列ごとの編集可否・型・書式をここで設定し、
**動的に変わる編集可否は `ICellStateProvider`（=ViewModel状態）** に委ねる。

```vb
Private Sub SetupGrid()
    With grid
        .Cols.Count = 1   ' 固定列ぶんを除いて構成
        .AllowEditing = True
        .SelectionMode = SelectionModeEnum.Cell   ' エクセルライクなセル選択
        .ExtendLastCol = True

        ' 列を追加（名前・キャプション・型・幅）
        Dim cName = .Cols.Add() : .Cols(cName).Name = "Name" : .Cols(cName).Caption = "名称"
        Dim cVal = .Cols.Add()  : .Cols(cVal).Name = "Value" : .Cols(cVal).Caption = "値"
        .Cols("Value").DataType = GetType(Decimal)
        .Cols("Value").Format = "#,##0"
    End With

    ' BindingList をバインド
    grid.DataSource = _viewModel.Items
    grid.BindState(DirectCast(_viewModel, ICellStateProvider))
End Sub
```

### テキストボックス（基準項目の単一レコード編集）

基準項目タブは1レコードなのでテキストボックス群にバインド。
`BindingSource` 経由で `INotifyPropertyChanged` と連動させる。

```vb
Private Sub SetupBindings()
    Dim bs As New BindingSource() With {.DataSource = _viewModel}
    nameTextBox.DataBindings.Add("Text", bs, "Current.Name", True,
                                 DataSourceUpdateMode.OnPropertyChanged)
    valueTextBox.DataBindings.Add("Text", bs, "Current.Value", True,
                                  DataSourceUpdateMode.OnValidation)
End Sub
```

`OnPropertyChanged` は打鍵ごと、`OnValidation` はフォーカス離脱時に反映。
検証を挟みたい項目は `OnValidation` にする。

---

## 12. 検証（保存時・グリッド編集時）

検証は2段階。**入力単位の即時検証（UI寄り）** と **保存前の全体検証（業務寄り）**。

### グリッド編集時の即時検証

セル確定時に値の形式・範囲を確認し、不正なら確定を止めて差し戻す。
形式レベルはグリッド、業務ルールは ViewModel に問い合わせる。

```vb
' カスタムグリッド：形式レベルの検証（数値か等）はここで
Protected Overrides Sub OnValidateEdit(e As ValidateEditEventArgs)
    Dim colName = Cols(e.Col).Name
    If colName = "Value" Then
        Dim text = Editor?.Text
        Dim dummy As Decimal
        If Not Decimal.TryParse(text, dummy) Then
            e.Cancel = True   ' 確定させない＝セルに留まる
        End If
    End If
    MyBase.OnValidateEdit(e)
End Sub
```

```vb
' UserControl：業務ルール検証は ViewModel に委ねる
Private Sub Grid_CellCommitted(sender As Object, e As CellCommittedEventArgs) _
        Handles grid.CellCommitted
    Dim err = _viewModel.ValidateCell(e.RowIndex, e.ColumnName, e.Value)
    If err IsNot Nothing Then
        ' セルに警告色＋メッセージ（ErrorProvider 等）。RowState は Modified にしない
        ShowCellError(e.RowIndex, e.ColumnName, err)
    Else
        _viewModel.UpdateCell(e.RowIndex, e.ColumnName, e.Value)
    End If
End Sub
```

### 保存時の全体検証

保存ボタン押下時、ViewModel が全行・全項目を検証し、エラーがあれば保存を中断して一覧表示。

```vb
Public Function Validate() As IReadOnlyList(Of ValidationError)
    Dim errors As New List(Of ValidationError)
    For Each row In Items
        If String.IsNullOrWhiteSpace(row.Name) Then
            errors.Add(New ValidationError(row.Seq, "Name", "名称は必須です"))
        End If
        ' 業務ルール：重複チェック・相関チェック等
    Next
    Return errors
End Function

Public Sub OnSave()
    Dim errors = Validate()
    If errors.Count > 0 Then
        RaiseEvent ValidationFailed(Me, New ValidationFailedEventArgs(errors))
        Return   ' 保存しない
    End If
    _repository.BulkSave(Items)
    AfterAction()
End Sub
```

**二段防御の原則：** グリッドのUI検証（形式・即時）と、保存前の業務検証（必須・相関・重複）は
別物。UIで弾いているから業務検証は不要、とはしない。

---

## 13. 画面遷移時の編集破棄確認

タブ切替・画面終了時に「編集中なら確認」する。判断材料は ViewModel の**変更有無（IsDirty）**。
確認の発火と分岐は View、変更有無の判定は ViewModel が持つ。

### 変更有無の判定（ViewModel）

```vb
Public ReadOnly Property IsDirty As Boolean
    Get
        Return Items.Any(Function(m) m.RowState <> RowEditState.Unchanged)
    End Get
End Property
```

### タブ切替時のガード（Form / UserControl）

切替を試みる前に、現在のタブが Dirty なら確認ダイアログを出し、結果で分岐。

```vb
Private Function ConfirmLeave() As Boolean
    If _activeViewModel Is Nothing OrElse Not _activeViewModel.IsDirty Then Return True

    Dim res = MessageBox.Show(
        "編集中の内容があります。破棄して移動しますか？" & vbCrLf &
        "「はい」=破棄して移動 / 「いいえ」=このまま留まる",
        "確認", MessageBoxButtons.YesNo, MessageBoxIcon.Warning)

    If res = DialogResult.Yes Then
        _activeViewModel.DiscardChanges()   ' 変更を破棄（再取得 or RowStateリセット）
        Return True
    Else
        Return False   ' 留まる
    End If
End Function

Private Sub TabButton_Click(sender As Object, e As EventArgs) _
        Handles standardTabButton.Click, largeTabButton.Click,
                mediumTabButton.Click, smallTabButton.Click
    If Not ConfirmLeave() Then Return   ' 留まる：タブ切替を中止
    ActivateTab(DirectCast(DirectCast(sender, Button).Tag, TabKind))
End Sub
```

### 画面終了時のガード（FormClosing）

```vb
Private Sub MainForm_FormClosing(sender As Object, e As FormClosingEventArgs) _
        Handles MyBase.FormClosing
    If Not ConfirmLeave() Then
        e.Cancel = True   ' 留まる：閉じない
    End If
    ' 閉じる場合はこの後 Dispose でロック解放
End Sub
```

### 破棄処理（ViewModel）

```vb
Public Sub DiscardChanges()
    ' 単純には Repository から再取得して BindingList を作り直す
    Load(_currentParentSeq)
End Sub
```

**三択にしたい場合**（保存して移動／破棄して移動／留まる）は、`MessageBox` の
`YesNoCancel` を使い、Yes=保存して移動・No=破棄して移動・Cancel=留まる、に割り当てる。
保存して移動は内部で `Validate → BulkSave` を通すため、検証エラー時は移動を中止する。

```vb
Dim res = MessageBox.Show("編集中の内容を保存しますか？",
                          "確認", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning)
Select Case res
    Case DialogResult.Yes
        If _activeViewModel.TrySave() Then Return True Else Return False ' 検証NGなら留まる
    Case DialogResult.No
        _activeViewModel.DiscardChanges() : Return True
    Case Else
        Return False
End Select
```

---

## 14. 早見表（最終）

| やりたいこと | ViewModel | View（UC/Grid） | その他 |
|---|---|---|---|
| データ取得 | Repository に委譲 | バインドして表示 | Repository → DbContext |
| 行/セル編集 | 値検証・モデル反映・RowState | 編集機構・即時形式検証 | — |
| 保存 | 全体検証・BulkSave呼出 | 保存ボタン押下を渡す | Repository でトランザクション |
| 列の色/編集可否 | Enum で判定 | Enum→Color 翻訳・塗布 | ICellStateProvider |
| ロック状態 | 状態保持・購読 | 表示・編集可否反映 | RecordLockService / DbLockState |
| モード | 状態保持・購読・遷移 | ボタン表示/活性反映 | EditorModeState |
| タブ切替 | IsDirty 判定・破棄 | 確認発火・Visible制御 | MainForm |
| 画面終了 | IsDirty 判定・保存/破棄 | FormClosing でガード | Dispose でロック解放 |

**判断基準は常に一つ：判断（業務）はViewModel、反映・操作（UI機構）はView。
語彙にUI部品名が出たら境界が崩れている。**

---

## 15. 依存性注入の組み立て（Composition Root）

第1部の原則どおり、配線は最後。`MainForm` 起動時に一括で組む（Composition Root）。
DIコンテナを使ってもよいが、規模が小さければ手組みで十分。

```vb
Public Sub New()
    InitializeComponent()

    ' 資源
    _db = New OracleDbContext(GetConnectionString())
    _lockService = New RecordLockService(_db, CurrentUser.Name)

    ' 共有状態
    _lockState = New DbLockState()
    _modeState = New EditorModeState()

    ' Repository（大/中/小はテーブル名違いで使い回し）
    Dim stdRepo As New OracleStandardRepository(_db)
    Dim largeRepo As New OracleListRepository(_db, "T_LARGE")
    Dim mediumRepo As New OracleListRepository(_db, "T_MEDIUM")
    Dim smallRepo As New OracleListRepository(_db, "T_SMALL")

    ' ViewModel
    Dim stdVm As New StandardEditorViewModel(stdRepo, _lockState, _modeState)
    Dim largeVm As New ListEditorViewModel(largeRepo, _lockState, _modeState)
    ' …中・小も同様

    ' UserControl に ViewModel を渡す（前述の保持＆Visible切替へ）
End Sub
```

抽象（IF）に依存させ、具象（Oracle実装）を Composition Root だけで知る。
テスト時は Repository をモックに差し替えれば、ViewModel を WinForms 抜きで検証できる。
