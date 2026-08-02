# 仕様書NO Excel出力アプリ 設計方針

## 1. 対象システム概要

仕様書NO / 部品 / 部品オプション / オプション別発注先 の4テーブル（左から親子関係）をJOINし、年度単位のExcelファイルとして出力する。

| 項目 | 内容 |
|---|---|
| 出力単位 | 年度ごとに別ファイル（例: `2026年度.xlsx`） |
| 出力方式 | 年度単位で全データを再出力（差分行の追記ではない） |
| 保存方式 | 上書き保存 |
| 実行契機 | 常駐アプリによる毎日23時の自動出力 / デスクトップアプリによる手動出力 |
| 対象データ | 仕様書NOが `^[A-Z][0-9]{2}[A-Za-z0-9]*$` に一致するもののみ |
| 年度の導出 | 仕様書NOの2〜3文字目（例: `A26xxx` → 2026年度） |
| 想定件数 | 数万件 / 年度 |

---

## 2. 出力対象の決定方式

### 2.1 採用方式

**変更履歴からの差分検知は行わない。** 以下の単純なルールで対象年度を決定する。

| 対象 | 頻度 |
|---|---|
| 直近3年度 | 毎晩無条件に出力 |
| それ以前の年度 | 前回出力成功から7日経過していれば出力 |
| 未出力（新年度含む） | 無条件に出力 |

### 2.2 この方式を採用した理由

- 更新検知ロジックが不要になり、拾い漏れを疑い続ける必要がなくなる
- 物理削除、仕様書NOの年度移動、親子同時削除といった検知困難なケースを考慮しなくてよい
- 更新側テーブルへのトリガー追加が不要で、書き込み性能に一切影響しない
- 過検知（余計に出力する）のコストは処理時間のみ。未検知（出力漏れ）のコストはデータ欠損。非対称なので過検知側に倒す

### 2.3 「曜日固定」ではなく「経過日数」で判定する理由

週次判定を曜日固定（日曜のみ等）にすると、その日にファイルが開かれていて失敗した年度は翌週まで放置される。

経過日数判定なら、失敗時に `LAST_SUCCESS_DT` を更新しないことで**翌日も自動的に対象に残る**。リトライという概念を実装せずにリトライが成立する。

また各年度の `LAST_SUCCESS_DT` が自然にばらけるため、負荷分散も自動的に効く。

---

## 3. 管理テーブル設計

### 3.1 方針

- **年度をPKとした1テーブルのみ**とする。ヘッダ/明細に分割しない
- **出力レコードテーブル（出力した仕様書NOの一覧）は持たない**。年度単位の全件再出力なので制御に一切使われず、実データとのズレという保守不要なバグを生むだけ
- **要出力フラグ / リトライフラグは持たない**。出力対象は年度と `LAST_SUCCESS_DT` から導出できる
- **ファイルパスはDBに持たない**。設定ファイルまたはシステム設定マスタ側（環境ごとに値を変える必要があるため）

### 3.2 DDL

```sql
CREATE TABLE EXCEL_OUTPUT_STATUS (
    NENDO             NUMBER(4)      NOT NULL,   -- 年度（西暦4桁）PK
    ------------------------------------------------------------------
    -- 出力対象判定用
    ------------------------------------------------------------------
    LAST_SUCCESS_DT   DATE,                      -- 最終出力成功日時。NULL=未出力
    ------------------------------------------------------------------
    -- 排他制御用
    ------------------------------------------------------------------
    STATUS            VARCHAR2(10)   DEFAULT 'IDLE' NOT NULL, -- IDLE / RUNNING
    LOCK_OWNER        VARCHAR2(128),             -- 実行中プロセスの識別子
    LOCK_ACQUIRED_DT  DATE,                      -- 実行開始日時
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
    LAST_ERROR_CODE   VARCHAR2(50),              -- FILE_LOCKED / UNEXPECTED 等
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
    CONSTRAINT CK_EOS_LOCK    CHECK (
        (STATUS = 'IDLE')
     OR (STATUS = 'RUNNING' AND LOCK_OWNER IS NOT NULL
                            AND LOCK_ACQUIRED_DT IS NOT NULL)
    )
);
```

インデックスはPKのみで十分（行数は年度数＝多くて数十行）。

### 3.3 各カラムの用途

| カラム | 用途 |
|---|---|
| `LAST_SUCCESS_DT` | 出力対象判定の唯一の基準。**成功時に「処理開始時刻」を記録**する（完了時刻ではない） |
| `FAIL_COUNT` | 制御には使わない。通知・監視専用（何回失敗しても翌日リトライし続ける仕様のため） |
| `LAST_ROW_CNT` | 異常検知用。前日1万件が急に0件になったらJOIN条件の破壊やマスタ削除を疑える |
| `LAST_ERROR_CODE` | `FILE_LOCKED`（誰かが開いている＝想定内）と `UNEXPECTED`（要調査）を区別。全部同じ扱いにすると通知が狼少年になる |

### 3.4 型の注意

`DATE` / `TIMESTAMP` は既存の履歴テーブル等と比較する可能性を考慮し、システム内で統一する。混在すると暗黙変換でインデックスが効かなくなる。

---

## 4. 年度の扱い

### 4.1 年度境界

年度は仕様書NOから導出するため、日本の会計年度（4月始まり）とは無関係。**1月1日に切り替わる**。

```sql
-- 現在年度
TO_NUMBER(TO_CHAR(SYSDATE, 'YYYY'))
```

「直近3年度」の判定にのみ使う値であり、データの年度そのものは常に仕様書NO由来。ここを会計年度と混同しないよう注意する。

### 4.2 仕様書NOからの年度導出

```sql
CASE WHEN REGEXP_LIKE(SPEC_NO, '^[A-Z][0-9]{2}[A-Za-z0-9]*$')
     THEN 2000 + TO_NUMBER(SUBSTR(SPEC_NO, 2, 2))
END
```

**注意点:**

- 正規表現には**必ずアンカー（`^` `$`）を付ける**。Oracleの `REGEXP_LIKE` はデフォルトで部分一致のため、アンカーなしだと不正なNOを拾う
- `2000 +` は決め打ち。`99` 等の値が過去データに紛れていると2099年度になる。事前に `GROUP BY SUBSTR(SPEC_NO,2,2)` で実データを確認すること
- この変換式は**DB側とアプリ側で二重実装になりやすい**。ビュー化するか定数として1箇所にまとめる

---

## 5. 出力対象抽出SQL

### 5.1 新年度行の自動追加（対象抽出の前に実行）

```sql
MERGE INTO EXCEL_OUTPUT_STATUS t
USING (
    SELECT DISTINCT
           2000 + TO_NUMBER(SUBSTR(SPEC_NO, 2, 2)) AS NENDO
      FROM SPEC
     WHERE REGEXP_LIKE(SPEC_NO, '^[A-Z][0-9]{2}[A-Za-z0-9]*$')
) s
   ON (t.NENDO = s.NENDO)
 WHEN NOT MATCHED THEN
      INSERT (NENDO, STATUS, INS_DT, UPD_DT, UPD_USER)
      VALUES (s.NENDO, 'IDLE', SYSDATE, SYSDATE, :user)
```

新規行は `LAST_SUCCESS_DT` が NULL なので、次項の抽出SQLで「未出力」として即座に対象になる。

### 5.2 出力対象年度の抽出

```sql
WITH cur AS (
    SELECT TO_NUMBER(TO_CHAR(SYSDATE, 'YYYY')) AS NENDO
      FROM DUAL
)
SELECT s.NENDO,
       CASE
           WHEN s.NENDO >= c.NENDO - 2          THEN '直近3年度'
           WHEN s.LAST_SUCCESS_DT IS NULL       THEN '未出力'
           WHEN s.LAST_SUCCESS_DT < SYSDATE - 7 THEN '週次'
       END AS REASON,
       s.LAST_SUCCESS_DT,
       s.FAIL_COUNT
  FROM EXCEL_OUTPUT_STATUS s
 CROSS JOIN cur c
 WHERE s.NENDO >= c.NENDO - 2                -- 直近3年度は無条件
    OR s.LAST_SUCCESS_DT IS NULL             -- 一度も成功していない
    OR s.LAST_SUCCESS_DT < SYSDATE - 7       -- 前回成功から7日経過
 ORDER BY s.NENDO DESC                       -- 新しい年度から処理
```

### 5.3 調整ポイント

**「7日」のマージン**
`SYSDATE - 7` ちょうどだと実行時刻の揺れで8日目にずれ込むことがある。`SYSDATE - 6.5` にすると確実に7日目に入る。

**3年度の境界日**
1月1日に対象年度が切り替わり、3年前の年度が毎晩→週次に落ちる。年始は前年度の残作業が続いている可能性があるため、`c.NENDO - 3`（4年度分）にする余地はある。実際の更新頻度を見て判断する。

**処理順序**
年度の降順（新しい順）で処理する。処理が途中で落ちた際に、重要度の高い年度が出力済みになっている確率が高い。

**データが消えた年度**
`SPEC` から全件削除された年度は `EXCEL_OUTPUT_STATUS` に残り、0件のファイルが出力され続ける。除外することも可能だが、既存ファイルは残ったままになるため「中身が古いファイルが残る」状態になる。0件でも上書きし続けるほうが事故が少ない可能性がある（運用判断）。

---

## 6. 排他制御（自動出力と手動出力の競合）

### 6.1 方針

| | 相手が実行中のとき |
|---|---|
| **手動出力** | 即座に「他の処理が実行中です」で中止。待たない |
| **自動出力** | その年度をスキップして次の年度へ。待たない |

自動側で待たないことが重要。全年度ループの途中で1年度に張り付くと後続が全部遅れる。またスキップしても翌日また対象になるため実害がない。

**ロックは年度単位で、処理直前に取得して直後に解放する。** 全年度分をまとめて取ると、バッチ実行中ずっと手動出力ができなくなる。

### 6.2 手動出力は年度指定にする

全年度出力に手動でも付き合わせると数分待たされる。手動側は年度を選択させるUIとし、競合するのは「その1年度が今まさに出力中」のときだけにする。

週次の年度は最大7日反映が遅れるため、手動出力がその救済手段になる。**利用者への周知が必須**（周知しないと「更新したのに反映されない」という問い合わせになる）。

### 6.3 ロック取得

`SELECT` で確認してから `UPDATE` すると隙間ができるため、**必ず1文で判定**する。

```sql
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
        -- 残留ロックの回収（プロセス強制終了・電源断など）
        OR LOCK_HEARTBEAT_DT < SYSDATE - INTERVAL '10' MINUTE)
```

更新件数が0なら他プロセスが実行中。

**実行後は即コミットする。** ロックを保持したままトランザクションを開けておくと、Oracleの行ロックで相手の `TryAcquireLock` が待たされ、「即座に諦める」が成立しなくなる。ロックの実体は行ロックではなく `STATUS` 列の値であり、DBトランザクションは短く閉じる。

### 6.4 ロック解放

```sql
UPDATE EXCEL_OUTPUT_STATUS
   SET STATUS            = 'IDLE',
       LOCK_OWNER        = NULL,
       LOCK_ACQUIRED_DT  = NULL,
       LOCK_HEARTBEAT_DT = NULL,
       UPD_DT            = SYSDATE
 WHERE NENDO = :nendo
   AND LOCK_OWNER = :owner        -- 自分が取ったロックだけ解放
```

`LOCK_OWNER` の条件は必須。ハートビート切れで別プロセスにロックを奪われた後に自分が解放すると、他人の実行中ロックを解除してしまう。

### 6.5 `LOCK_OWNER` の一意性

`MachineName\UserName` だけだと、同一PCで常駐アプリとデスクトップアプリが同じユーザーで動いた際に同じ値になり、所有者チェックが機能しない。

```
{MachineName}\{UserName}:{アプリ種別}:{ProcessId}
```

### 6.6 ハートビート

出力処理中は1分間隔で `LOCK_HEARTBEAT_DT` を更新する。これがないと、プロセス強制終了時に `RUNNING` のまま固まり、その年度が永久に出力されなくなる。

- 心拍間隔（1分）と残留判定（10分）は十分な差を空ける
- 1年度の出力に10分以上かかる可能性があるなら判定側を伸ばす
- 心拍の初回遅延は短め（10〜20秒）にする
- 心拍の失敗で本処理を止めない

---

## 7. アプリ実装（VB.NET / .NET Framework 4.8）

### 7.1 全体構造

```vb
Public Enum OutputResult
    Success
    Skipped      ' 他プロセスが実行中
    Failed       ' Excel保存失敗など
End Enum

Public Sub RunTargetYears(owner As String)
    _statusRepo.MergeNewYears()                ' 5.1
    Dim years = _statusRepo.GetTargetYears()   ' 5.2（降順）

    Dim skipped As New List(Of Integer)
    Dim failed  As New List(Of Integer)

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
    ' ロック取得。失敗したら即スキップ（待たない）
    If Not _statusRepo.TryAcquireLock(nendo, owner) Then
        _logger.Info($"{nendo}年度: 他プロセス実行中のためスキップ")
        Return OutputResult.Skipped
    End If

    Dim startedAt = _statusRepo.GetServerTime()   ' DBサーバー基準の時刻

    Try
        Using hb As New HeartbeatTimer(_statusRepo, nendo, owner)
            Dim tmpPath As String
            Dim rowCount As Integer

            Using reader = _dataRepo.OpenReaderByYear(nendo)   ' DataTableに載せない
                tmpPath = _excelWriter.WriteToTemp(nendo, reader, rowCount)
            End Using

            Try
                FileUtil.ReplaceAtomic(tmpPath, GetFilePath(nendo))
            Catch ex As IOException When FileUtil.IsSharingViolation(ex)
                ' 誰かが開いている。想定内の失敗
                _statusRepo.MarkFailed(nendo, "FILE_LOCKED", ex.Message)
                Return OutputResult.Failed
            End Try

            _statusRepo.MarkSuccess(nendo, startedAt, rowCount)
            Return OutputResult.Success
        End Using

    Catch ex As Exception
        _logger.Error(ex, $"{nendo}年度の出力に失敗")
        _statusRepo.MarkFailed(nendo, "UNEXPECTED", ex.Message)
        Return OutputResult.Failed

    Finally
        ' 成否に関わらず必ず解放。漏れると年度が固まる
        _statusRepo.ReleaseLock(nendo, owner)
    End Try
End Function
```

`Finally` での `ReleaseLock` が要。ハートビートによる残留回収は最後の保険であり、正常系で頼るものではない。

### 7.2 ファイル保存（一時ファイル + 差し替え）

いきなり本ファイルに書くと、書き込み途中で失敗した際にファイルが壊れる。

1. 一時ファイルに生成
2. `File.Replace` または `Move` で差し替え

開かれている場合は差し替え時に `IOException` になる。**例外を握りつぶさず、`HResult` の下位16bitが 32 / 33（共有違反）かまで判定**して `FILE_LOCKED` として記録する。

### 7.3 時刻はDBサーバー基準で取得

`startedAt` にクライアントの `DateTime.Now` を使うと、PCの時計ずれがそのまま出力対象判定と監視に効く。`SELECT SYSDATE FROM DUAL` で取得する。

### 7.4 手動出力側のUI

```vb
Select Case result
    Case OutputResult.Skipped
        MessageBox.Show($"{nendo}年度は現在、他の処理が実行中です。" & vbCrLf &
                        "しばらく待ってから再度実行してください。",
                        "出力できません", MessageBoxButtons.OK, MessageBoxIcon.Information)
    Case OutputResult.Failed
        MessageBox.Show("出力に失敗しました。ファイルが開かれていないか確認してください。", ...)
    Case OutputResult.Success
        MessageBox.Show($"{nendo}年度を出力しました。", ...)
End Select
```

`LOCK_OWNER` と `LOCK_ACQUIRED_DT` を返して「〇〇さんが実行中（経過〜分）」と表示すると問い合わせが減る（自動バッチなら「自動出力処理」と表示）。

---

## 8. 数万件/年度への対応

### 8.1 Excelライブラリ：NPOI（SXSSFWorkbook）

**採用: NPOI の `SXSSFWorkbook`**

`XSSFWorkbook` / ClosedXML / EPPlus は全セルをオブジェクトとしてメモリ上に構築するため、5万行×20列＝100万セルで数百MB〜1GBに達する。GC負荷も大きく、常駐プロセスのワーキングセットが膨らんだままになる。

`SXSSFWorkbook` は**直近N行だけをメモリに保持し、それより古い行を一時ファイルへフラッシュする**ストリーミング方式。メモリ使用量が行数にほぼ依存しない。APIは `XSSFWorkbook` とほぼ同じで書きやすい。

#### 制約（設計に影響する）

| 制約 | 影響 |
|---|---|
| フラッシュ済みの行にアクセスできない | 後から遡って値やスタイルを書き換えられない。**1パスで書き切る設計にする** |
| `AutoSizeColumn` が使えない（全行がメモリにないため） | 列幅は固定値で指定する。もともと8.6の理由で自動調整はしない方針なので問題なし |
| 一時ファイルがディスクに作られる | 出力中は一時領域を消費する。ディスク空き容量の確認が必要 |
| `Dispose` を忘れると一時ファイルが残り続ける | 常駐アプリなので**確実に破棄すること**（後述） |

#### 実装

```vb
Imports NPOI.XSSF.Streaming
Imports NPOI.SS.UserModel

Public Function WriteToTemp(nendo As Integer,
                            reader As IDataReader,
                            ByRef rowCount As Integer) As String

    Dim tmpPath = Path.Combine(Path.GetTempPath(),
                               $"{nendo}年度_{Guid.NewGuid():N}.xlsx")

    ' rowAccessWindowSize: メモリに保持する行数。既定100。
    ' compressTempFiles:=True で一時ファイルを圧縮（ディスク節約 / CPUと引き換え）
    Dim wb As New SXSSFWorkbook(rowAccessWindowSize:=200, compressTempFiles:=True)
    Try
        Dim styles = New ExportStyles(wb)          ' スタイルは最初に一括生成（8.2）
        Dim sheet = wb.CreateSheet($"{nendo}年度")

        ' 列幅は固定値で指定（AutoSizeColumn は使用不可）
        For i = 0 To ColumnDefs.Count - 1
            sheet.SetColumnWidth(i, ColumnDefs(i).WidthChars * 256)
        Next

        Dim r As Integer = 0
        WriteHeaderRow(sheet.CreateRow(r), styles)
        r += 1

        While reader.Read()
            Dim row = sheet.CreateRow(r)
            For i = 0 To ColumnDefs.Count - 1
                WriteCell(row.CreateCell(i), reader, i, styles)   ' 8.2
            Next
            r += 1
        End While
        rowCount = r - 1

        Using fs As New FileStream(tmpPath, FileMode.Create, FileAccess.Write)
            wb.Write(fs)
        End Using

        Return tmpPath

    Finally
        ' 一時ファイルの後始末。常駐アプリでは特に必須
        Try
            wb.ClearAllTemporaryFiles()
        Catch
        End Try
        wb.Close()
    End Try
End Function
```

`rowAccessWindowSize` は既定の100でも動くが、小さすぎるとフラッシュ回数が増える。200〜1000程度で実測して決める。大きくしてもメモリは行数ではなくウィンドウサイズに比例するだけなので、数千までは許容範囲。

`compressTempFiles:=True` は一時ファイルをGZip圧縮する。ディスクI/Oが減る代わりにCPUを使うので、**両方試して速いほうを採る**。

#### バージョンと環境の確認

- NPOI のパッケージによって**対応ターゲットフレームワークが異なる**。.NET Framework 4.8 で使えるバージョンかを事前に確認する
- `SXSSFWorkbook` は `NPOI.XSSF.Streaming` 名前空間（`NPOI.XSSF.UserModel` ではない）
- NPOI は内部で `SixLabors.ImageSharp` 等に依存するバージョンがある。依存パッケージが増えるので、配布形態（ClickOnce / xcopy）への影響を確認する

### 8.2 セルの型とスタイル

#### 型を正しく設定する

文字列で書くと Excel 上で「数値が文字列として保存されています」の警告が出て、集計もソートもできない。ファイルサイズも無駄に大きくなる。

```vb
Private Sub WriteCell(cell As ICell, reader As IDataReader,
                      idx As Integer, styles As ExportStyles)
    If reader.IsDBNull(idx) Then Return          ' NULL は空セルのまま

    Select Case ColumnDefs(idx).Kind
        Case ColumnKind.Number
            cell.SetCellValue(Convert.ToDouble(reader.GetValue(idx)))
            cell.CellStyle = styles.Number

        Case ColumnKind.Date
            cell.SetCellValue(reader.GetDateTime(idx))    ' DateTime オーバーロード
            cell.CellStyle = styles.DateStyle             ' 書式必須（無いと数値表示）

        Case Else
            cell.SetCellValue(reader.GetValue(idx).ToString())
    End Select
End Sub
```

日付は `SetCellValue(DateTime)` を使ったうえで**必ず日付書式のスタイルを当てる**。スタイルを当てないとシリアル値（45000 のような数値）として表示される。

#### スタイルは最初に一括生成して使い回す

`ICellStyle` を行ごと・セルごとに `CreateCellStyle()` で作ると、`styles.xml` が膨れ上がってファイルが開けなくなる。**XSSF にはブック内のセルスタイル数に上限（約64,000）**があり、5万行で1行1スタイル作ると即座に到達する。

```vb
Friend NotInheritable Class ExportStyles
    Public ReadOnly Header    As ICellStyle
    Public ReadOnly Number    As ICellStyle
    Public ReadOnly DateStyle As ICellStyle
    Public ReadOnly Text      As ICellStyle

    Public Sub New(wb As IWorkbook)
        Dim fmt = wb.CreateDataFormat()

        Header = wb.CreateCellStyle()
        Dim f = wb.CreateFont()
        f.IsBold = True
        Header.SetFont(f)

        Number = wb.CreateCellStyle()
        Number.DataFormat = fmt.GetFormat("#,##0")

        DateStyle = wb.CreateCellStyle()
        DateStyle.DataFormat = fmt.GetFormat("yyyy/mm/dd")

        Text = wb.CreateCellStyle()
    End Sub
End Class
```

**`ICellStyle` はワークブック単位**なので、年度ごとに `SXSSFWorkbook` を作り直すなら `ExportStyles` も都度生成する。使い回そうとして別ブックのスタイルを当てると壊れる。

### 8.3 DB取得

```vb
' NG: 数万行をメモリに展開
Dim dt As New DataTable()
adapter.Fill(dt)

' OK: 1行ずつ流す
Using reader = cmd.ExecuteReader()
    While reader.Read()
        ' そのまま SXSSFWorkbook へ
    End While
End Using
```

`OracleCommand.FetchSize` はデフォルトが小さい。1〜2MB程度に設定するとラウンドトリップが減り体感で変わる。

### 8.4 プロセスのビット数

.NET Framework 4.8 の WinForms は「AnyCPU + Prefer 32-bit」になっていることが多い。この場合アドレス空間が約2GBに制限される。`Oracle.ManagedDataAccess`（マネージド版）を使えばx64ビルドへの切り替えが容易。

### 8.5 JOINクエリのインデックス

年度絞り込みが `REGEXP_LIKE` + `SUBSTR` だとインデックスが効かない。ファンクションインデックスを作成する。

```sql
CREATE INDEX IX_SPEC_NENDO ON SPEC (
    CASE WHEN REGEXP_LIKE(SPEC_NO,'^[A-Z][0-9]{2}[A-Za-z0-9]*$')
         THEN 2000 + TO_NUMBER(SUBSTR(SPEC_NO,2,2)) END
);
```

**クエリ側も全く同じ式で書かないと使われない。** 式をビューに固定するのが現実的。

### 8.6 出力ファイル自体の重さ（利用者側の問題）

5万行×20列のxlsxは圧縮後3〜10MB、Excelで開くのに数十秒かかる。

- **オートフィルタを付けない**（開くのがさらに遅くなる）
- **条件付き書式を使わない**（行数分のルールになると致命的）
- **列幅の自動調整をしない**。`SXSSFWorkbook` では `AutoSizeColumn` がそもそも使えないため、`SetColumnWidth` で固定値を指定する

なお `SXSSFWorkbook` でオートフィルタ（`SetAutoFilter`）を設定する場合、範囲指定に全行数が必要になるため、書き出し完了後に行数が確定してから設定する必要がある。付けない方針ならこの考慮も不要になる。

ファイルが重いほど利用者が開いている時間が長くなり、保存失敗の発生確率が上がる。運用開始後にウォッチが必要。

---

## 9. 性能見積もりと計測

### 9.1 事前に実測すべきこと

1. **年度ごとの件数分布**（`GROUP BY 年度` で件数を数える）
2. **最も件数の多い年度**でのDB fetch時間とファイル書き出し時間を**別々に**計測
3. その結果から、直近3年度＋週次分が23時からの許容時間内に収まるか判断

NPOI 採用は決定済みだが、`rowAccessWindowSize` と `compressTempFiles` の最適値は実測でしか決まらない。また件数分布によっては 8.6 の「利用者が開けないほど重いファイル」が先に問題になる。

### 9.2 目安（5万行/年度の場合）

| 工程 | 目安 |
|---|---|
| DB fetch（4テーブルJOIN） | 年度あたり 2〜10秒 |
| Excel書き出し（ストリーミング） | 年度あたり 1〜5秒 |
| ファイル差し替え | 1秒未満 |

初回実行時は全年度が対象になるため時間がかかる。**その日の所要時間を計測しておくと、平常時との差が分かり以降の判断材料になる。**

### 9.3 方式を見直すべきライン

- 平常時（直近3年度＋週次分）の所要時間が30分を超える
- 年度数が増え続け、線形に悪化する見込みがある
- 深夜帯に他バッチと競合してDB負荷が問題になる

---

## 10. 運用監視

### 10.1 未出力年度の検知

直近3年度と週次年度で閾値を分ける。分けないと週次年度が常時警告に引っかかる。

```sql
SELECT NENDO, LAST_SUCCESS_DT, FAIL_COUNT, LAST_ERROR_CODE
  FROM EXCEL_OUTPUT_STATUS s
 CROSS JOIN (SELECT TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')) AS NENDO FROM DUAL) c
 WHERE (s.NENDO >= c.NENDO - 2 AND s.LAST_SUCCESS_DT < SYSDATE - 3)
    OR (s.NENDO <  c.NENDO - 2 AND s.LAST_SUCCESS_DT < SYSDATE - 10)
```

これがないと「誰かがExcelを開きっぱなしで1ヶ月更新されていない」に気づけない。

### 10.2 スキップの可視化

スキップ自体は正常な結果だが、毎晩同じ年度がスキップされ続けているなら異常。スキップはエラーではないため、10.1 の `LAST_SUCCESS_DT` ベースの監視で拾う。

### 10.3 出力件数の異常検知

`LAST_ROW_CNT` の前日比が極端に減っていたら警告。「出力は成功したが中身が壊れている」を検知する数少ない手段。

---

## 11. 実装着手順序

1. 年度ごとの件数分布を確認する
2. NPOI（SXSSFWorkbook）で最大件数年度を1年度分出力し、時間・メモリ・一時ファイルサイズを実測する（`rowAccessWindowSize` と `compressTempFiles` の調整もここで）
3. `EXCEL_OUTPUT_STATUS` を作成し、全年度を手動出力して `LAST_SUCCESS_DT` を埋める
4. 出力対象抽出SQL（5.1 / 5.2）を単体で確認する
5. ロック取得・解放を実装し、2プロセス同時起動で競合とスキップを確認する
6. ハートビート切れ（プロセス強制終了）からの回収を確認する
7. ファイルを開いた状態での保存失敗と、翌日の自動リトライを確認する
8. 常駐アプリのスケジューラに組み込む

---

## 付録: 検討したが採用しなかった案

| 案 | 不採用の理由 |
|---|---|
| 出力レコードテーブル（出力した仕様書NOの一覧を保持） | 年度単位の全件再出力のため制御に使われない。実データとのズレというバグを生むだけ |
| 要出力フラグ + トリガーでのフラグON | 単一行への集中UPDATEでロック競合。子テーブルのトリガーからの年度解決に1行あたり2〜3回のSELECTが必要で一括更新時に致命的 |
| 変更履歴テーブルからの差分検知 | 削除時に最上位階層のキーがNULLになり年度が特定できない。SQLが複雑化し、拾い漏れを疑い続けるコードになる |
| 毎晩、全年度を無条件出力 | 年度数の増加に対して線形に悪化する。直近3年度＋週次で実質同等の鮮度を保てる |
| `XSSFWorkbook` / ClosedXML / EPPlus | 全セルをメモリに構築するため数万件で数百MB〜1GB。常駐プロセスには不向き |
| `OpenXmlWriter`（OpenXML SDK） | メモリ効率は最良だがAPIが低レベルで実装コストが高い。NPOI の SXSSF で必要十分と判断 |
| 週次判定を曜日固定にする | その日に失敗した年度が翌週まで放置される |
