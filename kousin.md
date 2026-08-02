## DDL

```sql
CREATE TABLE EXCEL_OUTPUT_STATUS (
    NENDO             NUMBER(4)      NOT NULL,   -- 年度（西暦4桁）PK
    ------------------------------------------------------------------
    -- 差分検知用
    ------------------------------------------------------------------
    LAST_SUCCESS_DT   DATE,                      -- 最終出力成功日時。NULL=未出力
    ------------------------------------------------------------------
    -- 排他制御用
    ------------------------------------------------------------------
    STATUS            VARCHAR2(10)   DEFAULT 'IDLE' NOT NULL, -- IDLE / RUNNING
    LOCK_OWNER        VARCHAR2(128),             -- 実行中のホスト名\ユーザー名
    LOCK_ACQUIRED_DT  DATE,                      -- 実行開始日時（残留ロック判定用）
    LOCK_HEARTBEAT_DT DATE,                      -- 生存確認用。定期更新
    ------------------------------------------------------------------
    -- 実行結果・運用監視用
    ------------------------------------------------------------------
    LAST_ATTEMPT_DT   DATE,                      -- 最終試行日時（成否問わず）
    LAST_RESULT       VARCHAR2(10),              -- SUCCESS / FAILED
    LAST_FILE_NAME    VARCHAR2(255),             -- 実際に出力したファイル名
    LAST_ROW_CNT      NUMBER(10),                -- 出力件数（異常検知用）
    LAST_DURATION_MS  NUMBER(10),                -- 処理時間（性能劣化の把握用）
    FAIL_COUNT        NUMBER(5)      DEFAULT 0 NOT NULL, -- 連続失敗回数
    LAST_ERROR_CODE   VARCHAR2(50),              -- 例: FILE_LOCKED / DB_ERROR
    LAST_ERROR_MSG    VARCHAR2(2000),            -- 例外メッセージ（切り詰め）
    ------------------------------------------------------------------
    -- 監査
    ------------------------------------------------------------------
    INS_DT            DATE           DEFAULT SYSDATE NOT NULL,
    UPD_DT            DATE           DEFAULT SYSDATE NOT NULL,
    UPD_USER          VARCHAR2(128),
    ------------------------------------------------------------------
    CONSTRAINT PK_EXCEL_OUTPUT_STATUS PRIMARY KEY (NENDO),
    CONSTRAINT CK_EOS_STATUS  CHECK (STATUS IN ('IDLE','RUNNING')),
    CONSTRAINT CK_EOS_RESULT  CHECK (LAST_RESULT IN ('SUCCESS','FAILED')),
    CONSTRAINT CK_EOS_NENDO   CHECK (NENDO BETWEEN 1990 AND 2199),
    -- RUNNING 中は必ず所有者と開始日時が入っている
    CONSTRAINT CK_EOS_LOCK    CHECK (
        (STATUS = 'IDLE')
     OR (STATUS = 'RUNNING' AND LOCK_OWNER IS NOT NULL
                            AND LOCK_ACQUIRED_DT IS NOT NULL)
    )
);
```

インデックスはPKのみで十分です。行数は年度数（多くて数十行）なので、`FULL SCAN` でも問題になりません。

---

## 意図的に持たせていないもの

**要出力フラグ / リトライフラグ**
履歴テーブルからの導出方式にしたので不要です。`LAST_SUCCESS_DT` が「どこまで反映済みか」を表し、失敗時は更新しないので翌日も自然に対象に残ります。フラグを持つと、導出結果とフラグのどちらが正なのかという二重管理になります。

**ファイルパス**
年度によって変わらないはずなので、設定ファイル（またはシステム設定マスタ）側です。DBに入れると環境ごと（本番/検証）に値を変える必要が出てきて面倒です。`LAST_FILE_NAME` だけは「実際に何を出力したか」の実績として持っています。

**出力レコードテーブルへのFK**
テーブルごと廃止した前提です。

---

## 状態遷移

```
出力開始:
  IDLE → RUNNING   （LOCK_OWNER, LOCK_ACQUIRED_DT を設定）

成功:
  RUNNING → IDLE   LAST_SUCCESS_DT = 開始時刻, FAIL_COUNT = 0,
                   LAST_RESULT = 'SUCCESS', ロック列を NULL クリア

失敗:
  RUNNING → IDLE   LAST_SUCCESS_DT は据え置き, FAIL_COUNT = FAIL_COUNT + 1,
                   LAST_RESULT = 'FAILED', エラー内容を記録
```

`LAST_SUCCESS_DT` に入れるのは**完了時刻ではなく処理開始時刻**にしてください。処理中に発生した変更を次回拾えるようにするためです。前回話した25時間マージンと合わせて、過検知側に倒しておく方針です。

---

## ロック取得（アトミックに）

常駐アプリの23時バッチと手動出力が競合するので、`SELECT` してから `UPDATE` する2ステップにすると隙間ができます。1文で取ります。

```sql
UPDATE EXCEL_OUTPUT_STATUS
   SET STATUS            = 'RUNNING',
       LOCK_OWNER        = :owner,
       LOCK_ACQUIRED_DT  = SYSDATE,
       LOCK_HEARTBEAT_DT = SYSDATE,
       LAST_ATTEMPT_DT   = SYSDATE,
       UPD_DT            = SYSDATE,
       UPD_USER          = :user
 WHERE NENDO = :nendo
   AND (STATUS = 'IDLE'
        -- 残留ロックの回収（プロセス強制終了・PCの電源断など）
        OR LOCK_HEARTBEAT_DT < SYSDATE - INTERVAL '10' MINUTE)
```

更新件数が0なら他プロセスが実行中なので、手動側は「他の処理が実行中です」で中止、バッチ側はスキップします。

`LOCK_HEARTBEAT_DT` は、デスクトップアプリが出力中にプロセスキルされた場合の保険です。これがないと `RUNNING` のまま永久に固まって、以降その年度が一切出力されなくなります。出力処理中に1分おきくらいで更新してください。既存のロック管理テーブルの仕組みがあるなら、そちらのハートビート方式に合わせるのが自然だと思います。

---

## 新年度行のINSERT

年度は勝手に増えるので、出力対象の年度が管理テーブルに存在しない場合はMERGEで作ります。

```sql
MERGE INTO EXCEL_OUTPUT_STATUS t
USING (SELECT :nendo AS NENDO FROM DUAL) s
   ON (t.NENDO = s.NENDO)
 WHEN NOT MATCHED THEN
      INSERT (NENDO, STATUS, INS_DT, UPD_DT, UPD_USER)
      VALUES (s.NENDO, 'IDLE', SYSDATE, SYSDATE, :user)
```

`LAST_SUCCESS_DT` は NULL のままなので、前回のSQLの `b.FROM_DT IS NULL` 条件で無条件に出力対象になります。

---

## 運用面で効いてくる点

**`FAIL_COUNT` は通知のため**に持っています。制御には使いません（何回失敗しても翌日リトライし続ける仕様なので）。3以上で管理者にメール、といった監視をかけないと「誰かがExcelを開きっぱなしで1ヶ月更新されていない」に気づけません。

**`LAST_ROW_CNT` は異常検知用**です。前日1万件だったものが急に0件になっていたら、JOIN条件の破壊やマスタ削除を疑えます。前回値との比較まで実装するかは別として、記録だけはしておく価値があります。

**`LAST_ERROR_CODE` を分けている**のは、`FILE_LOCKED`（誰かが開いている＝正常な範囲の失敗）と `DB_ERROR`（要調査）を区別したいからです。前回触れた `IOException` の HResult 32/33 判定の結果をここに落とす想定です。全部同じ扱いにすると、通知が狼少年になります。

**`DATE` か `TIMESTAMP` か** — 前回の差分検知SQLで履歴テーブルの `UPD_DT` と比較するので、**履歴テーブル側の型に揃えてください**。履歴が `TIMESTAMP` なら暗黙変換が入って、インデックスが効かなくなる可能性があります。

前提を置かないと書けないので、以下を仮定します。実際のスキーマに合わせて読み替えてください。

**仮定するスキーマ**

| 種別 | テーブル | 主なカラム |
|---|---|---|
| 現行 | `SPEC` | `SPEC_SEQ`(PK), `SPEC_NO` |
| 現行 | `PART` | `PART_SEQ`(PK), `SPEC_SEQ` |
| 現行 | `OPT` | `OPT_SEQ`(PK), `PART_SEQ` |
| 現行 | `SUP` | `SUP_SEQ`(PK), `OPT_SEQ` |
| 履歴 | `*_HIST` | 上記の全カラム + `OPE_KBN`(I/U/D), `UPD_DT` |
| 管理 | `EXCEL_OUTPUT_STATUS` | `NENDO`(PK), `LAST_SUCCESS_DT` |

履歴は**変更後の値（削除時は削除直前の値）のスナップショット**が入る前提です。

---

## SQL

```sql
WITH
base_dt AS (
    SELECT NENDO, LAST_SUCCESS_DT - INTERVAL '25' HOUR AS FROM_DT
      FROM EXCEL_OUTPUT_STATUS
),
min_dt AS (
    SELECT CASE WHEN COUNT(*) > COUNT(LAST_SUCCESS_DT) THEN NULL
                ELSE MIN(LAST_SUCCESS_DT) - INTERVAL '25' HOUR END AS FROM_DT
      FROM EXCEL_OUTPUT_STATUS
),
chg AS (
    SELECT c.UPD_DT, c.TBL_NM, c.PK_VAL, c.COL_NM,
           c.OLD_VAL, c.NEW_VAL, c.ROOT_PK_VAL
      FROM CHANGE_LOG c
     CROSS JOIN min_dt m
     WHERE c.TBL_NM IN ('SPEC','PART','OPT','SUP')
       AND c.SCHEMA_NM = :schema
       AND (m.FROM_DT IS NULL OR c.UPD_DT >= m.FROM_DT)
),
------------------------------------------------------------------
-- 親子対応表：現行テーブル + ログの旧値/新値
-- 削除済み・付け替え済みの行もここで拾える
------------------------------------------------------------------
part_spec AS (
    SELECT TO_CHAR(PART_SEQ) AS C, TO_CHAR(SPEC_SEQ) AS P FROM PART
    UNION
    SELECT PK_VAL, OLD_VAL FROM CHANGE_LOG
     WHERE TBL_NM='PART' AND COL_NM='SPEC_SEQ' AND OLD_VAL IS NOT NULL
    UNION
    SELECT PK_VAL, NEW_VAL FROM CHANGE_LOG
     WHERE TBL_NM='PART' AND COL_NM='SPEC_SEQ' AND NEW_VAL IS NOT NULL
),
opt_part AS (
    SELECT TO_CHAR(OPT_SEQ), TO_CHAR(PART_SEQ) FROM OPT
    UNION
    SELECT PK_VAL, OLD_VAL FROM CHANGE_LOG
     WHERE TBL_NM='OPT' AND COL_NM='PART_SEQ' AND OLD_VAL IS NOT NULL
    UNION
    SELECT PK_VAL, NEW_VAL FROM CHANGE_LOG
     WHERE TBL_NM='OPT' AND COL_NM='PART_SEQ' AND NEW_VAL IS NOT NULL
),
sup_opt AS (
    SELECT TO_CHAR(SUP_SEQ), TO_CHAR(OPT_SEQ) FROM SUP
    UNION
    SELECT PK_VAL, OLD_VAL FROM CHANGE_LOG
     WHERE TBL_NM='SUP' AND COL_NM='OPT_SEQ' AND OLD_VAL IS NOT NULL
    UNION
    SELECT PK_VAL, NEW_VAL FROM CHANGE_LOG
     WHERE TBL_NM='SUP' AND COL_NM='OPT_SEQ' AND NEW_VAL IS NOT NULL
),
------------------------------------------------------------------
-- 影響を受ける SPEC_SEQ の特定
--   ROOT_PK_VAL があればそれを使い、NULL なら自力で辿る
------------------------------------------------------------------
affected AS (
    -- SPEC 自身
    SELECT UPD_DT, TBL_NM, PK_VAL, PK_VAL AS SPEC_SEQ_S
      FROM chg WHERE TBL_NM='SPEC'
    UNION ALL
    -- PART：ROOT または SPEC_SEQ の旧値・新値
    SELECT c.UPD_DT, c.TBL_NM, c.PK_VAL,
           COALESCE(c.ROOT_PK_VAL, ps.P)
      FROM chg c
      LEFT JOIN part_spec ps ON ps.C = c.PK_VAL
     WHERE c.TBL_NM='PART'
    UNION ALL
    -- OPT：ROOT または PART 経由
    SELECT c.UPD_DT, c.TBL_NM, c.PK_VAL,
           COALESCE(c.ROOT_PK_VAL, ps.P)
      FROM chg c
      LEFT JOIN opt_part  op ON op.C = c.PK_VAL
      LEFT JOIN part_spec ps ON ps.C = op.P
     WHERE c.TBL_NM='OPT'
    UNION ALL
    -- SUP：ROOT または OPT→PART 経由
    SELECT c.UPD_DT, c.TBL_NM, c.PK_VAL,
           COALESCE(c.ROOT_PK_VAL, ps.P)
      FROM chg c
      LEFT JOIN sup_opt   so ON so.C = c.PK_VAL
      LEFT JOIN opt_part  op ON op.C = so.P
      LEFT JOIN part_spec ps ON ps.C = op.P
     WHERE c.TBL_NM='SUP'
),
spec_no_all AS (
    SELECT TO_CHAR(SPEC_SEQ) AS SPEC_SEQ_S, SPEC_NO FROM SPEC
    UNION
    SELECT PK_VAL, OLD_VAL FROM CHANGE_LOG
     WHERE TBL_NM='SPEC' AND COL_NM='SPEC_NO' AND OLD_VAL IS NOT NULL
    UNION
    SELECT PK_VAL, NEW_VAL FROM CHANGE_LOG
     WHERE TBL_NM='SPEC' AND COL_NM='SPEC_NO' AND NEW_VAL IS NOT NULL
),
spec_year AS (
    SELECT DISTINCT SPEC_SEQ_S,
           2000 + TO_NUMBER(SUBSTR(SPEC_NO,2,2)) AS NENDO
      FROM spec_no_all
     WHERE REGEXP_LIKE(SPEC_NO, '^[A-Z][0-9]{2}[A-Za-z0-9]*$')
),
------------------------------------------------------------------
-- 安全網：年度を特定できなかった変更が存在するか
------------------------------------------------------------------
unresolved AS (
    SELECT COUNT(*) AS CNT FROM affected WHERE SPEC_SEQ_S IS NULL
)
SELECT sy.NENDO,
       COUNT(DISTINCT a.TBL_NM||'/'||a.PK_VAL) AS CHANGED_ROW_CNT,
       MAX(a.UPD_DT)                           AS LAST_CHANGE_DT,
       COUNT(DISTINCT CASE WHEN a.TBL_NM='SPEC' THEN a.PK_VAL END) AS SPEC_CNT,
       COUNT(DISTINCT CASE WHEN a.TBL_NM='PART' THEN a.PK_VAL END) AS PART_CNT,
       COUNT(DISTINCT CASE WHEN a.TBL_NM='OPT'  THEN a.PK_VAL END) AS OPT_CNT,
       COUNT(DISTINCT CASE WHEN a.TBL_NM='SUP'  THEN a.PK_VAL END) AS SUP_CNT,
       CASE WHEN b.NENDO IS NULL THEN '新規年度' ELSE '更新' END   AS REASON
  FROM affected a
  JOIN spec_year sy ON sy.SPEC_SEQ_S = a.SPEC_SEQ_S
  LEFT JOIN base_dt b ON b.NENDO = sy.NENDO
 WHERE b.NENDO IS NULL OR b.FROM_DT IS NULL OR a.UPD_DT >= b.FROM_DT
 GROUP BY sy.NENDO, b.NENDO
 ORDER BY sy.NENDO
```

`SPEC_CNT`〜`SUP_CNT` は運用時の切り分け用です。「なぜこの年度が対象になったのか」が分からないと調査が地獄になるので、集計しておくことをおすすめします。

---

## 意図している挙動

**年度移動** — 仕様書NO `A25xxx` → `A26xxx` に変更されると、`spec_year` に 2025 と 2026 の両方の行が残るため、旧年度・新年度の両方が対象になります。旧年度のファイルから行を消せます。

**削除** — 履歴に削除直前のスナップショットがあれば、現行テーブルに行がなくても `spec_year` / `part_spec` が履歴側から拾います。

**親子同時削除** — `part_spec` などが現行と履歴のUNIONなので、親が消えていても履歴経由で辿れます。前回話した「履歴同士のJOIN」がここに相当します。

**フォーマット違反** — `NENDO` が NULL になり `spec_year` の時点で除外。違反NOを正しい形式に修正した場合は、修正後の値が履歴に入るので新規追加と同じ扱いで拾えます。

---

## 注意点

**`INTERVAL '25' HOUR` のマージン**は前回話した取りこぼし対策です。バッチが毎日走る前提なら、これは「前回失敗して2日空いた」ようなケースでは足りません。ただし失敗時は `LAST_SUCCESS_DT` を更新しないので、基準日時が古いまま残り、結果的にカバーされます。

**世紀の判定** `2000 + SUBSTR(...)` は決め打ちです。`99` のような値が過去データに紛れていると 2099年度になります。実データを一度 `GROUP BY SUBSTR(SPEC_NO,2,2)` で確認しておいたほうがいいです。ここは前回触れた「変換ルールを1箇所にまとめる」対象そのもので、SQL側とアプリ側で二重実装になりがちな箇所です。

**性能** 履歴テーブルの `UPD_DT` にインデックスがあっても、このSQLは `spec_year` などのCTEで**現行・履歴の全件スキャン**が入ります。履歴が数百万件規模だと重くなるはずです。その場合は、

1. まず `*_HIST` を `UPD_DT >= (全年度の最小FROM_DT)` で絞ってから親子解決する
2. `spec_year` をマテリアライズドビューにする

のどちらかです。ただ、**この重さこそが「毎晩全年度を無条件出力」を検討する理由**でもあります。差分検知のSQLがこの規模になるなら、全年度出力の実測時間と比較してみる価値は十分あると思います。

**動作確認の順序** としては、`changes` CTE を単体で `SELECT * FROM changes WHERE NENDO = 2026` のように叩いて、意図した件数が出るかを先に見るのが早いです。特に年度移動と削除のケースは、テストデータを作って明示的に確認しておくことをおすすめします。

その他、実装時に効いてくる点

排他制御

常駐アプリの23時バッチと、デスクトップアプリの手動出力が同時に走る可能性があります。同一年度を2プロセスが同時に書くと壊れるので、状態カラム（出力中）か、既存のロック管理テーブルの仕組みに乗せるのが安全です。手動出力側は「他が出力中です」で弾く。

手動出力の挙動

手動はフラグ関係なく強制出力にすべきです。「更新してないのに出したい」（前回の出力が消えた、内容を確認したい）が手動の主用途なので。

保存失敗の判定と一時ファイル

いきなり本ファイルに書くと、書き込み途中で失敗したときにファイルが壊れます。一時ファイルに生成 → File.Replace または Move で差し替え、が定石です。開かれている場合は差し替え時に IOException になるので、そこで失敗判定。例外を握りつぶさず、HResult（32/33 = 共有違反）まで見てログに残すと運用が楽になります。

フォーマット判定

^[A-Z][0-9]{2}[a-zA-Z0-9]*$ を必ずアンカー付きで。Oracleの REGEXP_LIKE はデフォルトで部分一致なので、アンカーなしだと不正なNOを拾います。

年度の2桁 → 4桁変換ルール（26 → 2026）も、どこかに定数として1箇所にまとめておかないと、DB側のビューとアプリ側で二重実装になりがちです。

変更管理テーブルのインデックス定義
```sql
CREATE INDEX IX_CHANGE_LOG_01 ON CHANGE_LOG (UPD_DT, TBL_NM);
CREATE INDEX IX_CHANGE_LOG_02 ON CHANGE_LOG (TBL_NM, COL_NM);  -- spec_no_all用
```

## 考え方

「スキップ」の実体は、**ロック取得UPDATEの更新件数が0だったら次の年度へ進む**、それだけです。`SELECT` で状態を確認してから `UPDATE` すると隙間ができるので、必ず1文で判定します。

前回のロック取得SQLがそのまま使えます。

---

## VB.NET 実装

```vb
Public Enum OutputResult
    Success
    Skipped      ' 他プロセスが実行中
    Failed       ' Excel保存失敗など
End Enum

''' <summary>全年度を出力する。競合した年度はスキップして継続。</summary>
Public Sub RunAllYears(owner As String)
    Dim years = _statusRepo.GetTargetYears()   ' 降順で取得

    Dim skipped As New List(Of Integer)
    Dim failed As New List(Of Integer)

    For Each nendo In years
        Select Case ExportOneYear(nendo, owner)
            Case OutputResult.Skipped : skipped.Add(nendo)
            Case OutputResult.Failed  : failed.Add(nendo)
        End Select
    Next

    _logger.Info($"出力完了 対象:{years.Count} スキップ:{skipped.Count} 失敗:{failed.Count}")
    If skipped.Any() Then _logger.Warn($"スキップ年度: {String.Join(",", skipped)}")
End Sub

Private Function ExportOneYear(nendo As Integer, owner As String) As OutputResult
    ' ── ロック取得。失敗したら即スキップ（待たない）──
    If Not _statusRepo.TryAcquireLock(nendo, owner) Then
        _logger.Info($"{nendo}年度: 他プロセス実行中のためスキップ")
        Return OutputResult.Skipped
    End If

    Dim startedAt = _statusRepo.GetServerTime()   ' 差分検知用に開始時刻を保持

    Try
        Using hb As New HeartbeatTimer(_statusRepo, nendo, owner)
            Dim rows = _dataRepo.FetchByYear(nendo)
            Dim tmpPath = _excelWriter.WriteToTemp(nendo, rows)

            Try
                FileUtil.ReplaceAtomic(tmpPath, GetFilePath(nendo))
            Catch ex As IOException When FileUtil.IsSharingViolation(ex)
                ' 誰かが開いている。想定内の失敗
                _statusRepo.MarkFailed(nendo, "FILE_LOCKED", ex.Message)
                Return OutputResult.Failed
            End Try

            _statusRepo.MarkSuccess(nendo, startedAt, rows.Count)
            Return OutputResult.Success
        End Using

    Catch ex As Exception
        _logger.Error(ex, $"{nendo}年度の出力に失敗")
        _statusRepo.MarkFailed(nendo, "UNEXPECTED", ex.Message)
        Return OutputResult.Failed

    Finally
        ' 成否に関わらず必ず解放。ここが漏れると年度が永久に固まる
        _statusRepo.ReleaseLock(nendo, owner)
    End Try
End Function
```

`Finally` での `ReleaseLock` が要です。ハートビートによる残留回収は最後の保険であって、正常系で頼るものではありません。

---

## ロック取得（更新件数で判定）

```vb
Public Function TryAcquireLock(nendo As Integer, owner As String) As Boolean
    Const sql = "
        UPDATE EXCEL_OUTPUT_STATUS
           SET STATUS            = 'RUNNING',
               LOCK_OWNER        = :owner,
               LOCK_ACQUIRED_DT  = SYSDATE,
               LOCK_HEARTBEAT_DT = SYSDATE,
               LAST_ATTEMPT_DT   = SYSDATE,
               UPD_DT            = SYSDATE,
               UPD_USER          = :owner
         WHERE NENDO = :nendo
           AND (STATUS = 'IDLE'
                OR LOCK_HEARTBEAT_DT < SYSDATE - INTERVAL '10' MINUTE)"

    Using cmd = CreateCommand(sql)
        cmd.Parameters.Add(":owner", owner)
        cmd.Parameters.Add(":nendo", nendo)
        Dim affected = cmd.ExecuteNonQuery()
        _connection.Commit()          ' ← 即コミット。トランザクションを引っ張らない
        Return affected > 0
    End Using
End Function
```

**即コミットが重要**です。ロックを保持したままトランザクションを開けておくと、Oracleの行ロックで手動出力側の `TryAcquireLock` が**待たされてしまい**、「即座に諦める」が成立しません。

ロックの実体は行ロックではなく `STATUS` 列の値です。DBトランザクションは短く閉じます。

---

## 解放

```vb
Public Sub ReleaseLock(nendo As Integer, owner As String)
    Const sql = "
        UPDATE EXCEL_OUTPUT_STATUS
           SET STATUS            = 'IDLE',
               LOCK_OWNER        = NULL,
               LOCK_ACQUIRED_DT  = NULL,
               LOCK_HEARTBEAT_DT = NULL,
               UPD_DT            = SYSDATE
         WHERE NENDO = :nendo
           AND LOCK_OWNER = :owner"    -- 自分が取ったロックだけ解放
    ' ...
End Sub
```

`LOCK_OWNER = :owner` の条件を必ず付けてください。ハートビート切れで別プロセスに奪われた後に自分が解放すると、**他人の実行中ロックを解除**してしまいます。

---

## 手動出力側

自動と同じ `ExportOneYear` を呼び、`Skipped` のときだけUIに出します。

```vb
Private Async Sub btnExport_Click(sender As Object, e As EventArgs)
    Dim nendo = CInt(cmbNendo.SelectedValue)
    btnExport.Enabled = False
    Try
        Dim result = Await Task.Run(Function() ExportOneYear(nendo, GetOwnerId()))

        Select Case result
            Case OutputResult.Skipped
                MessageBox.Show($"{nendo}年度は現在、他の処理が実行中です。" &
                                vbCrLf & "しばらく待ってから再度実行してください。",
                                "出力できません", MessageBoxButtons.OK,
                                MessageBoxIcon.Information)
            Case OutputResult.Failed
                MessageBox.Show("出力に失敗しました。ファイルが開かれていないか確認してください。", ...)
            Case OutputResult.Success
                MessageBox.Show($"{nendo}年度を出力しました。", ...)
        End Select
    Finally
        btnExport.Enabled = True
    End Try
End Sub
```

「実行中です」に加えて**誰が実行中か**を出すと、問い合わせが減ります。`LOCK_OWNER` を返して「〇〇さんが実行中です」と表示するのは、社内システムなら有効です（自動バッチなら「自動出力処理」と表示）。

---

## ハートビート

```vb
Friend NotInheritable Class HeartbeatTimer : Implements IDisposable
    Private ReadOnly _timer As System.Threading.Timer

    Public Sub New(repo As IStatusRepository, nendo As Integer, owner As String)
        _timer = New System.Threading.Timer(
            Sub() 
                Try
                    repo.Heartbeat(nendo, owner)
                Catch
                    ' 心拍の失敗で本処理を止めない
                End Try
            End Sub,
            Nothing, TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1))
    End Sub

    Public Sub Dispose() Implements IDisposable.Dispose
        _timer?.Dispose()
    End Sub
End Class
```

心拍の間隔（1分）と残留判定（10分）は十分な差を空けてください。1年度の出力に10分以上かかる可能性があるなら、判定側を伸ばす必要があります。

---

## 注意点

**`LOCK_OWNER` の一意性** — `Environment.MachineName & "\" & Environment.UserName` だと、同じPCで常駐アプリとデスクトップアプリが同じユーザーで動くと**同じ値**になります。プロセスIDかアプリ種別を含めてください。

```vb
$"{Environment.MachineName}\{Environment.UserName}:{appKind}:{Process.GetCurrentProcessId()}"
```

これを分けないと、`ReleaseLock` の所有者チェックが機能しません。

**スキップの可視化** — スキップは「正常な結果」ですが、毎晩同じ年度がスキップされ続けているなら異常です。`EXCEL_OUTPUT_STATUS` の `LAST_SUCCESS_DT` を見て、3日以上成功していない年度を検知する監視は別途入れておくべきです。スキップ自体はエラーではないので、そこだけ見ていると気づけません。

**時刻はDBサーバー基準で** — `startedAt` にクライアントの `DateTime.Now` を使うと、PCの時計ずれがそのまま差分検知（将来復活させる可能性を含め）や監視に効きます。`SELECT SYSDATE FROM DUAL` で取ってください。
