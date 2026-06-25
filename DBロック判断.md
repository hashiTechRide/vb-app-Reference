ここは設計判断が要る場面なので、まず仕組みを整理してから実装に落とします。「基準項目のSeqを1つ排他すれば、それに紐づく大・中・小すべてのロックを表現する」という考え方は妥当です。子を個別にロックするのではなく、**親（基準項目Seq）の1ロックを全タブで共有して参照する**形にします。

## ロックの考え方

ロックの単位は基準項目のレコードSeq、1つだけです。大・中・小は物理的に別レコードでも、編集権の単位としては「どの基準項目に属するか」で決まります。だから取るロックは1本でよく、4タブはその1本の状態を見て編集可否を表現します。これは前回までの「共有 `DbLockState` を全ViewModelが参照する」構図とそのまま一致します。

```
基準項目Seq = 123 を1回ロック
   └─ 大・中・小タブはすべて「123がロック取得済みか」を見るだけ
```

## Oracleでどう排他するか

Oracleで「フォームを開いている間ずっと握る悲観ロック」を実現する代表的な方法は2つあります。

**`SELECT ... FOR UPDATE NOWAIT`**（行ロック）。基準項目の行をトランザクション内でロックし、コミット／ロールバックまで保持。他者が同じ行を取りに来ると `NOWAIT` で即座に失敗するので、「誰かが編集中」を即判定できます。ただしトランザクションを開きっぱなしにする設計になり、保存のたびにコミットすると同時にロックが外れてしまう点に注意が要ります（後述の「保存後に取り直す」がまさにこれ）。

**アプリケーションロック方式**（ロック管理テーブル or `DBMS_LOCK`）。専用のロックテーブルに「Seq・ロック者・取得時刻」を1行入れて排他を表現する方法。トランザクションと独立して保持でき、「誰がロックしているか」を画面に出しやすい。前半で `DbLockInfo.LockedBy`（誰がロックしているか）を持たせたい話があったので、こちらのほうが相性がいいです。

`LockedBy` を表示したい要件があるなら、ロック管理テーブル方式を勧めます。以下はその前提で書きます。

## ロック取得・解放を担うクラス

接続は前回の `OracleDbContext`、状態通知は `DbLockState`。その間に「ロックを取りに行く・外しに行く」操作を持つクラスを置きます。`DbLockState` は状態を持つだけ、実際のDB操作はサービスに分けると責任が綺麗です。

```vb
' ロックのDB操作を担う（取得・解放・確認）
Public Class RecordLockService
    Private ReadOnly _db As OracleDbContext
    Private ReadOnly _currentUser As String

    Public Sub New(db As OracleDbContext, currentUser As String)
        _db = db
        _currentUser = currentUser
    End Sub

    ' 取得を試みる。成否と、失敗時はロック者を返す
    Public Function TryAcquire(baseSeq As Long) As LockResult
        ' ロック管理テーブルに INSERT を試みる（主キー = baseSeq）
        ' 既に行があれば取得失敗。その行のロック者を読んで返す
        ' INSERT成功 = 取得成功
        ' ※実際のSQLはテーブル設計に合わせる
    End Function

    Public Sub Release(baseSeq As Long)
        ' 自分が持っている行を DELETE
    End Sub
End Class

Public Class LockResult
    Public Property Acquired As Boolean
    Public Property LockedBy As String   ' 失敗時、誰が持っているか
End Class
```

`DbLockState` は結果を受けて状態を通知するだけにします。

```vb
Public Class DbLockState
    Implements INotifyPropertyChanged

    Private _info As DbLockInfo
    Public Property Info As DbLockInfo
        Get
            Return _info
        End Get
        Private Set(value As DbLockInfo)
            _info = value
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs(NameOf(Info)))
        End Set
    End Property

    ' サービスの結果を反映
    Public Sub Apply(result As LockResult)
        Info = New DbLockInfo With {
            .IsLocked = Not result.Acquired,   ' 自分が取れなかった=他者ロック中
            .LockedBy = result.LockedBy
        }
    End Sub

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged
End Class
```

`IsLocked` の意味を「自分が編集できない（他者が握っている）」と定義すると、UIは `IsLocked = True` のとき編集不可・`LockedBy` を表示、で一貫します。

## フォームを開いたときに取る

基準項目のSeqが決まった時点で1回取得します。取得可否で全タブの編集可否が決まります。

```vb
Public Class MainForm
    Private ReadOnly _db As OracleDbContext
    Private ReadOnly _lockService As RecordLockService
    Private ReadOnly _lockState As New DbLockState()
    Private _baseSeq As Long

    Private Sub MainForm_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        _baseSeq = GetTargetBaseSeq()      ' 開く対象の基準項目Seq
        AcquireLock()
        ' UserControl生成・タブ初期化など（前回までの流れ）
    End Sub

    Private Sub AcquireLock()
        Dim result = _lockService.TryAcquire(_baseSeq)
        _lockState.Apply(result)           ' 全タブがこの通知を受けて編集可否を反映
        If Not result.Acquired Then
            MessageBox.Show($"このレコードは {result.LockedBy} が編集中のため、閲覧のみ可能です。")
        End If
    End Sub
```

取れなければ閲覧専用として開く、という運用が穏当です（開けない＝即閉じる、にするかは要件次第）。

## 保存後に取り直す

「内容保存したら再度ロックを取りに行く」という要件は、おそらく**保存＝コミットでトランザクション境界が切れる／ロックを一度手放す運用**になっているからだと思います。保存でロックを解放→再取得することで、保存の合間に他者へ譲る余地を作る、あるいはロックの保持時刻を更新する狙いです。

保存処理の最後に再取得を挟みます。重要なのは、**保存と再ロックの間に他者が割り込む可能性がある**点です。再取得に失敗したら、以降は編集不可へ落とす必要があります。

```vb
    ' 各ViewModelの保存完了後に呼ばれる想定（イベント経由でForm/共有層へ）
    Private Sub OnSaved()
        ' 保存処理側で commit 済み。ロックを取り直す
        _lockService.Release(_baseSeq)       ' いったん解放（運用次第では省略）
        Dim result = _lockService.TryAcquire(_baseSeq)
        _lockState.Apply(result)
        If Not result.Acquired Then
            MessageBox.Show($"保存しましたが、ロックを再取得できませんでした（{result.LockedBy} が取得）。以降は閲覧のみになります。")
        End If
    End Sub
```

ここで一つ判断が要ります。**解放してから再取得する**と、その一瞬の隙に他者が奪える。**解放せず保持時刻だけ更新する**なら隙はないが、それは「保存のたびに取り直す」という当初の表現とは少しズレます。要件の意図がどちらかで実装が変わります。

```
意図A：保存ごとに他者へ譲る機会を作りたい → Release してから TryAcquire（隙あり、要再判定）
意図B：握り続けたいが保持を更新したい     → Release せず保持時刻を UPDATE（隙なし）
```

「再度ロックを取りに行く」と言っているので意図Aに見えますが、編集中に毎回手放すと頻繁に奪われて編集が続けられなくなるリスクがあります。実運用では意図B（保持の更新）か、A でも「自分が継続保持なら必ず取り直せる」設計（ロック者が自分なら成功扱い）にするのが安全です。

```vb
' TryAcquire 内：既存行のロック者が自分自身なら成功扱いにする
' → 保存ごとの取り直しで自分が弾かれない
```

## どのタイミングで解放するか

フォームを閉じるときに必ず解放します。前回の `Dispose` に乗せます。例外で落ちてもロックが残らないように、確実に通る場所に置きます。

```vb
    Protected Overrides Sub Dispose(disposing As Boolean)
        If disposing Then
            Try
                _lockService.Release(_baseSeq)
            Catch
                ' ログ。解放失敗してもアプリは閉じる
            End Try
            _db?.Dispose()
            components?.Dispose()
        End If
        MyBase.Dispose(disposing)
    End Sub
End Class
```

アプリが異常終了するとロック行が残る問題は、ロック管理テーブル方式の弱点です。`取得時刻` を持たせて**一定時間で失効**させる、起動時に自分の古いロックを掃除する、といった対策をセットで入れておくと運用が安定します。

## 全体の構図

```
OracleDbContext     … 接続（資源）
RecordLockService   … ロックの取得・解放・確認（DB操作）
DbLockState         … ロック状態の通知（UIが購読）
   ↑ 各タブのViewModel/UserControlが購読し、IsLocked で編集可否を表現

開く        → baseSeq を1回 TryAcquire → 全タブに反映
保存完了    → 取り直し（自分なら成功扱い推奨）→ 全タブに反映
閉じる      → Release（Disposeで確実に）
```

## まとめ

- ロック単位は**基準項目Seq 1本**。大・中・小はその状態を共有参照するだけ。個別ロックは不要
- `LockedBy`（誰がロック中か）を出したいので、**ロック管理テーブル方式**を勧める。`SELECT FOR UPDATE` は保存＝コミットでロックが切れて噛み合いにくい
- ロックのDB操作は `RecordLockService` に分離。`DbLockState` は結果を受けて通知するだけ（資源・操作・状態通知の3分離を維持）
- 開いたとき取得、取れなければ閲覧専用が穏当
- **保存後の取り直しは、ロック者が自分なら成功扱いにして自分が弾かれないように**。完全に解放して取り直すと隙に奪われるので意図を確認
- 閉じるときは `Dispose` で確実に解放。残留対策に失効時刻を持たせる

「保存のたびに取り直す」が、毎回完全に手放す意図なのか保持を更新する意図なのかだけ、要件を確認してください。ここが排他の体験を大きく left right します。前者は他者に譲りやすい反面、自分の編集が中断されるリスクがあります。
