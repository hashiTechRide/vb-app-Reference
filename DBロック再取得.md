方向Aで、再ロック失敗時に読み取り専用へ落とす形にまとめます。これまでの構成（`DbLockState` / `RecordLockService` / ViewModel注入）にそのまま乗ります。

## 全体の流れ

```
保存（Commit or Rollback どちらでも排他は切れる）
   → 直後に必ず TryAcquire で再ロック
      成功 → そのまま編集継続
      失敗 → メッセージ表示 → 全タブを読み取り専用へ
```

Commit後もRollback後も「切れている前提で取り直す」のは同じなので、再ロック処理は1箇所にまとめます。

## 1. 読み取り専用状態をどこで持つか

「読み取り専用かどうか」は全タブ共通の横断状態なので、`DbLockState` に持たせるのが自然です。`IsLocked`（他者が握っていて編集できない）と意味が重なるので、統一します。**再ロック失敗＝自分が排他を持っていない＝編集不可**なので、`IsLocked = True` で表現できます。

```vb
Public Class DbLockInfo
    Public Property IsLocked As Boolean   ' True = 自分は編集できない（読み取り専用）
    Public Property LockedBy As String
End Class
```

各タブのグリッドやボタンは既に `DbLockState` を購読しているので、ここが `IsLocked = True` になれば、前に作った仕組みで自動的に編集不可・ボタン無効化に反映されます。**新しく読み取り専用フラグを別に足す必要はなく、既存のロック状態を使い回せます。**

## 2. 再ロック処理を1メソッドにまとめる

保存の成否から呼ばれる共通処理。成功/失敗で `DbLockState` を更新し、失敗時はイベントで通知します。

```vb
' ViewModel（または共有のロック管理を担う層）
Private Function ReacquireLock() As Boolean
    Dim result = _lockService.TryAcquire(_baseSeq)   ' 別接続・別トランザクションで取得
    _lockState.Apply(result)                         ' 全タブへ反映
    If Not result.Acquired Then
        ' 再ロック失敗 → 読み取り専用へ落ちたことを通知
        RaiseEvent LockLost(Me, New LockLostEventArgs(result.LockedBy))
    End If
    Return result.Acquired
End Function
```

`_lockState.Apply` は前に定義した通り、`Acquired=False` なら `IsLocked=True` を立てて通知します。これで購読側（グリッド・ボタン）が読み取り専用に切り替わります。

## 3. 保存処理に組み込む

Commit成功時もRollback（例外）時も、`ReacquireLock` を通します。

```vb
Public Sub OnSave()
    Dim saveSucceeded As Boolean

    Try
        _repository.Save(_table)     ' 内部で FOR UPDATE → UPDATE → Commit
        saveSucceeded = True
    Catch ex As Exception
        saveSucceeded = False
        RaiseEvent SaveFailed(Me, New SaveFailedEventArgs(ex))
    End Try

    ' 成否に関わらず排他は切れているので取り直す
    Dim relocked = ReacquireLock()

    If saveSucceeded AndAlso relocked Then
        AfterAction()               ' 正常：モード遷移や画面終了へ
    End If
    ' 再ロック失敗なら AfterAction せず、読み取り専用のまま画面に留まる
End Sub
```

保存成功していても再ロックに失敗したら、その先の編集はできません。`AfterAction`（次モードへ／画面終了）は「保存成功かつ再ロック成功」のときだけ進めます。保存は成功しているので、データは保存済み・以降は閲覧のみ、という状態になります。

## 4. 再ロック失敗のメッセージ表示（View側）

`LockLost` イベントをUserControl/Formが受けて、メッセージを出します。表示はViewの仕事なので、ViewModelはイベントで依頼するだけ（境界維持）。

```vb
' UserControl or Form
AddHandler _viewModel.LockLost,
    Sub(s, e)
        Dim who = If(String.IsNullOrEmpty(e.LockedBy), "他のユーザー", e.LockedBy)
        MessageBox.Show(
            $"排他ロックを再取得できませんでした（{who} が編集中）。" & vbCrLf &
            "この画面は読み取り専用になります。",
            "読み取り専用", MessageBoxButtons.OK, MessageBoxIcon.Warning)
    End Sub
```

`DbLockState` の変更通知はメッセージとは別に流れるので、メッセージを出す前後で、グリッドやボタンの読み取り専用反映は自動で行われます。メッセージは「ユーザーへの説明」、状態反映は「購読による自動処理」で、役割が分かれます。

## 5. 読み取り専用の反映（既存の仕組みを使う）

`IsLocked = True` になったとき、各所がどう反応するかを確認しておきます。ここは新規実装ではなく、これまで作った購読が効きます。

グリッドの編集不可（`ICellStateProvider` 経由、または一括）:

```vb
' UserControl：ロック状態変更でグリッド全体の編集可否を反映
AddHandler _lockState.PropertyChanged,
    Sub(s, e)
        If e.PropertyName = NameOf(DbLockState.Info) Then
            If InvokeRequired Then BeginInvoke(AddressOf ApplyReadOnly) Else ApplyReadOnly()
        End If
    End Sub

Private Sub ApplyReadOnly()
    Dim locked = _lockState.Info.IsLocked
    grid.AllowEditing = Not locked         ' 読み取り専用ならグリッド編集不可
    RefreshButtons()                       ' 保存等のボタンも無効化
End Sub
```

ボタンの無効化（モードとのAND、前に定義済み）:

```vb
Private Sub RefreshButtons()
    Dim locked = _lockState.Info.IsLocked
    saveButton.Enabled = Not locked
    deleteModeButton.Enabled = _modeState.CanTransit(EditorMode.Delete) AndAlso Not locked
    restoreModeButton.Enabled = _modeState.CanTransit(EditorMode.Restore) AndAlso Not locked
End Sub
```

全タブが同じ `DbLockState` を購読しているので、**1回の再ロック失敗で4タブすべてが読み取り専用になります。** 基準項目Seq単位の排他という設計とも整合します。

## 6. 読み取り専用後の挙動を決めておく

読み取り専用に落ちた後、ユーザーができることを整理しておきます。

- 閲覧はできる（グリッドは見える、編集はできない）。
- 保存・削除モード遷移・復元モード遷移は不可（ボタン無効）。
- キャンセル/閉じるは可能。閉じるときの `Release` は、そもそも自分が持っていないので何もしない（or 自分のロック行が無いことを確認して終わる）。

再ロック失敗後にキャンセルで閉じる場合、`Dispose` の `Release` が「自分が持っていないロックを消そうとする」ことになります。`Release` は自分が所有者のときだけDELETEする実装にしておけば、他者のロックを誤って消しません。

```vb
Public Sub Release(baseSeq As Long)
    ' WHERE baseSeq = :seq AND locked_by = :me  ← 自分の行だけ消す
End Sub
```

これは再ロック失敗時に限らず、安全策として常に入れておくべきです。

## まとめ

- 「読み取り専用」は新規フラグを作らず、**既存の `DbLockState.IsLocked = True` で表現**する。購読済みのグリッド・ボタンが自動で編集不可になる。
- 再ロックは `ReacquireLock` に1本化し、**保存のCommit/Rollbackどちらの後も必ず通す**（行ロックはどちらでも切れるため）。
- 成功時のみ `AfterAction`（モード遷移・画面終了）へ進む。**保存成功でも再ロック失敗なら進めず**、読み取り専用で画面に留まる。
- 再ロック失敗は `LockLost` イベントでView に通知し、**メッセージ表示はView、状態反映は購読で自動**、と役割を分ける。
- 1つの `DbLockState` を全タブが購読しているので、**1回の失敗で4タブすべてが読み取り専用**になる。基準項目Seq単位の排他と整合。
- `Release` は**自分が所有者の行だけ**を消すようにし、読み取り専用後に閉じても他者のロックを壊さない。

方向Aは「保存のたびに切れて取り直す」前提なので、再ロックの成否チェックが常に要ります。今回の読み取り専用化はその失敗系の受け皿として過不足なく、既存のロック状態購読にそのまま乗るので、追加実装は `ReacquireLock` と `LockLost` の通知、メッセージ表示くらいで収まります。

いい問いです。前の回答で私が「ViewModelに `_lockService` を注入してあれば」と書いたのに、Formにしか持たせていない現状と食い違っていました。まず「誰が再取得を実行すべきか」を決めれば、「誰に渡すべきか」は自動で決まります。順番が逆になっていたのが分かりにくさの原因です。

## まず決めるべきこと：再取得は誰の責任か

ロック再取得が必要になるのは**保存の直後**です。だから「保存を実行するのは誰か」に紐づけて考えます。これまでの設計では、保存は次の流れでした。

```
保存ボタン(View) → UserControl(橋渡し) → ViewModel.OnSave → Repository.Save
```

保存を主導しているのは **ViewModel** です。再取得は保存の成否に直結する処理（Commit/Rollbackで切れた排他を取り直す）なので、**保存を主導するViewModelと同じ場所で完結させる**のが自然です。保存はViewModelなのに再取得だけFormに戻す、とすると制御が行ったり来たりして追いにくくなります。

つまり答えは、**ロックサービス（相当の操作窓口）はViewModelに渡す**。UserControlには渡さない（UserControlは橋渡しで、業務判断を持たない方針のため）。

## ただしForm所有のままでよい部分もある

ロックには2つの操作タイミングがあります。

- **開くときの取得・閉じるときの解放** … 画面ライフサイクルの話。**Formの責任**。
- **保存直後の再取得** … 保存の一部。**ViewModelの責任**。

前者はFormが握って正しい。後者だけViewModelに窓口を渡す。**「Formが所有」と「ViewModelにも操作させる」は両立します。**同じサービスインスタンスをFormが生成・保持しつつ、ViewModelにも参照を渡せばよい。所有権と使用権は別です。

```
RecordLockService（1インスタンス）
   ├─ Form が保持     … 開くとき Acquire / 閉じるとき Release
   └─ ViewModel に注入 … 保存直後の再取得（TryAcquire）
```

## 渡し方：サービスそのものか、窓口を絞るか

ここで選択肢が2つあります。

### 案1：RecordLockServiceをそのままViewModelに注入

シンプル。Composition Root（Form生成時）で渡します。

```vb
' Form のコンストラクタ（Composition Root）
_lockService = New RecordLockService(_db, CurrentUser.Name)

Dim largeVm As New LargeEditorViewModel(largeRepo, _lockService, _lockState, _modeState, _baseSeq)
```

```vb
' ViewModel は保存直後に自分で再取得
Public Sub OnSave()
    Dim ok As Boolean
    Try
        _repository.Save(_table)
        ok = True
    Catch ex As Exception
        ok = False
        RaiseEvent SaveFailed(Me, New SaveFailedEventArgs(ex))
    End Try

    ' Commit/Rollbackどちらでも排他は切れているので取り直す
    Dim result = _lockService.TryAcquire(_baseSeq)
    _lockState.Apply(result)
    If Not result.Acquired Then
        RaiseEvent LockLost(Me, New LockLostEventArgs(result.LockedBy))
        Return   ' 読み取り専用へ（前回の通り）
    End If

    If ok Then AfterAction()
End Sub
```

### 案2：再取得だけの薄い窓口を渡す（推奨寄り）

`RecordLockService` には取得・解放・確認が全部入っています。ViewModelに丸ごと渡すと、ViewModelが解放まで呼べてしまい、「解放はFormの責任」という線引きが緩みます。ViewModelに必要なのは**再取得だけ**なので、そこだけ切った窓口を渡すと責任がはっきりします。

```vb
' ViewModelが必要とするのは「今の対象を取り直す」ことだけ
Public Interface ILockRenewer
    Function Renew() As LockResult   ' 対象Seqは内部で保持
End Interface
```

Formが実装（またはラップ）して、baseSeqを内部に閉じ込めた窓口を渡します。

```vb
' Form側で baseSeq を束ねた窓口を作ってViewModelへ
Dim renewer As ILockRenewer = New LockRenewer(_lockService, _baseSeq)
Dim largeVm As New LargeEditorViewModel(largeRepo, renewer, _lockState, _modeState)
```

```vb
Public Class LockRenewer
    Implements ILockRenewer
    Private ReadOnly _service As RecordLockService
    Private ReadOnly _baseSeq As Long
    Public Sub New(service As RecordLockService, baseSeq As Long)
        _service = service
        _baseSeq = baseSeq
    End Sub
    Public Function Renew() As LockResult Implements ILockRenewer.Renew
        Return _service.TryAcquire(_baseSeq)
    End Function
End Class
```

ViewModelは `_renewer.Renew()` を呼ぶだけ。baseSeqすら知らなくてよくなり、解放も呼べないので、責任が「再取得のみ」に絞られます。

## どちらを選ぶか

- **案1（サービス丸渡し）** … 実装が少ない。ViewModelがロック操作全般に触れるが、規約で「ViewModelは再取得しか呼ばない」と決めておけば実用上問題ない。小規模ならこれで十分。
- **案2（窓口を絞る）** … ViewModelができることを再取得だけに限定でき、「解放はFormだけ」の線引きがコードで保証される。baseSeqの受け渡しもViewModelから隠せる。設計をきっちりさせたいならこちら。

これまで「責任を語彙で縛る」話をしてきた流れなら案2が一貫しますが、案1でも動作は同じです。まず案1で組んで、ViewModelがロックを触りすぎて気になったら案2へ絞る、でも構いません。

## UserControlには渡さない

再取得はViewModelで完結するので、UserControlはロックサービスを持ちません。UserControlの役割は変わらず橋渡しです。保存ボタンのクリックをViewModelに渡し、ViewModelが上げる `LockLost` イベントを受けてメッセージ表示する、その2点だけ。

```vb
' UserControl：ロックサービスは持たない。イベントの受け渡しだけ
Private Sub saveButton_Click(sender As Object, e As EventArgs) Handles saveButton.Click
    grid.FinishEditing()
    _viewModel.OnSave()
End Sub

AddHandler _viewModel.LockLost, AddressOf ShowLockLostMessage
```

## 前回の分かりにくさの正体

前回は「ViewModelに注入してあれば」と条件形で書いたのに、実際の注入をどこでやるか（Composition Root＝Form生成時）を明示しなかったので、Formにしか無い現状とつながりませんでした。正しくは、**Formが生成・保持したまま、ViewModelにも参照（案1）か窓口（案2）を渡す**。所有はForm、再取得の実行はViewModel、という分担です。

## まとめ

- 再取得は**保存の直後に必要**で、保存を主導するのは**ViewModel**。だから再取得もViewModelで完結させるのが自然。制御をFormへ戻さない。
- よって**ロック操作の窓口はViewModelに渡す**。UserControlには渡さない（橋渡しに徹する方針のため）。
- ただし**開く時の取得・閉じる時の解放はFormの責任**のまま。「Formが所有」と「ViewModelにも操作させる」は両立する。所有権と使用権は別。
- 渡し方は2案。**案1**：`RecordLockService` を丸ごと注入（simple）。**案2**：再取得だけの `ILockRenewer` に絞って注入（責任が明確・baseSeqも隠せる）。どちらでも動作は同じ。
- Composition Root（Form生成時）で注入する。ここが前回明示できておらず、現状とのつながりが見えにくかった点。

現状Formにしか無いのは出発点として正しいので、そこから「ViewModelに再取得の窓口を追加で渡す」だけで済みます。Formからロックを剥がす必要はありません。足すだけです。
