# Oracle 実行計画 チューニングガイド

## 目次

1. [WITH句（CTE）の使用判断基準](#1-with句cteの使用判断基準)
2. [COSTと実行時間の乖離](#2-costと実行時間の乖離)
3. [ヒストグラムとSQLプロファイル](#3-ヒストグラムとsqlプロファイル)
4. [サブクエリの集計結果とインデックス](#4-サブクエリの集計結果とインデックス)
5. [大規模テーブルのインデックス設計](#5-大規模テーブルのインデックス設計)
6. [Cost/Bytesが爆増した場合の対応](#6-costbytesが爆増した場合の対応)
7. [DISPLAY_CURSORで正しいSQLを参照する方法](#7-display_cursorで正しいsqlを参照する方法)
8. [INLINEヒントの正しい使い方](#8-inlineヒントの正しい使い方)

---

## 1. WITH句（CTE）の使用判断基準

### 使うべきケース

- **同じサブクエリを複数回参照する場合** — 最も明確な判断基準。パフォーマンスと可読性の両方が向上する
- **クエリのネストが深くなる場合** — サブクエリが3段以上の入れ子になると可読性が低下する。WITH句で段階的に名前を付けて分解すると処理の流れが明確になる
- **複雑な集計を段階的に行う場合** — 「部門別売上を集計 → ランキング → 上位抽出」のように処理をステップに分けたいとき
- **再帰クエリが必要な場合** — 階層構造（組織図、カテゴリツリーなど）の探索

### 避けてよいケース

- **単純なクエリ** — JOINやWHEREだけで済むものにCTEを使うと冗長になる
- **1回しか使わない軽量なサブクエリ** — インラインビュー（FROM句内のサブクエリ）で十分
- **パフォーマンスに悪影響がある場合** — OracleのCTEは意図せずマテリアライズされることがある

### Oracle固有の注意点

- `/*+ MATERIALIZE */` と `/*+ INLINE */` のヒントでCTEの実行方式を制御可能
- 実行計画で `TEMP TABLE TRANSFORMATION` が出ていたらマテリアライズされている

---

## 2. COSTと実行時間の乖離

### 前提

COSTはオプティマイザが統計情報をもとに算出した**相対的な推定コスト**であり、実際のI/OやCPU時間を正確に反映するものではない。COSTが低い＝速いとは限らない。

### 主な原因

#### 2.1 統計情報が実態と乖離している（最も多い原因）

テーブルやインデックスの統計情報が古い・不正確だと、オプティマイザは行数やデータ分布を見誤る。

```sql
-- 統計情報の最終収集日を確認
SELECT table_name, num_rows, last_analyzed
FROM user_tables
WHERE table_name = 'YOUR_TABLE';

-- 実際の行数と比較
SELECT COUNT(*) FROM your_table;
```

#### 2.2 カーディナリティの見積もり誤り（E-Rows vs A-Rows）

COSTの計算根拠であるRows（推定行数）が実際と大きくずれている場合、COSTは低くても実行時間は長くなる。

```sql
-- 実行計画のE-Rows（推定）とA-Rows（実績）を比較
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    sql_id => 'your_sql_id',
    format  => 'ALLSTATS LAST'
));
```

E-RowsとA-Rowsが桁違いに異なっていたら、それが根本原因。

#### 2.3 WITH句のマテリアライズによるオーバーヘッド

マテリアライズされると一時表への書き込み・読み込みが発生するが、COSTにはこのオーバーヘッドが適切に反映されないことがある。

```sql
-- インライン展開を強制して比較
WITH cte AS (...)
SELECT /*+ INLINE */ * FROM ...;
```

#### 2.4 マルチブロックリードとキャッシュの影響

COSTはディスクI/Oを前提に計算するが、実際にはバッファキャッシュのヒット率によって速度が大きく変わる。

#### 2.5 並列処理の有無

COSTが低いプランが直列実行、COSTが高いプランが並列実行の場合、後者のほうが実時間は短くなることがある。

---

## 3. ヒストグラムとSQLプロファイル

### 3.1 ヒストグラム

通常の統計情報は行数やNDV（ユニーク値の数）など大まかな情報しか持たない。ヒストグラムは特定カラムの**データ分布（偏り）**を記録する追加の統計情報。

例：`status`カラムに「完了」が95%、「処理中」が5%の場合、ヒストグラムがないとオプティマイザは均等分布と仮定し行数を過大評価する。

```sql
-- 特定カラムにヒストグラムを収集
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => 'SCHEMA_NAME',
    tabname    => 'YOUR_TABLE',
    method_opt => 'FOR COLUMNS SIZE 254 status'
  );
END;
/

-- 確認
SELECT column_name, histogram, num_buckets
FROM user_tab_col_statistics
WHERE table_name = 'YOUR_TABLE';
```

- `histogram`が`NONE`なら未収集
- `FREQUENCY`、`HEIGHT BALANCED`、`HYBRID`なら収集済み
- データの偏りが大きいカラム（ステータス、フラグ、区分コードなど）で効果的

### 3.2 SQLプロファイル

特定のSQL文に対して**補正情報を紐づける**仕組み。SQL文単位のピンポイントな対策。

```sql
-- 1. チューニングタスクを作成
DECLARE
  l_task VARCHAR2(30);
BEGIN
  l_task := DBMS_SQLTUNE.CREATE_TUNING_TASK(
    sql_id => 'your_sql_id'
  );
  DBMS_SQLTUNE.EXECUTE_TUNING_TASK(task_name => l_task);
END;
/

-- 2. レポートを確認
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('task_name') FROM dual;

-- 3. 推奨されたSQLプロファイルを適用
BEGIN
  DBMS_SQLTUNE.ACCEPT_SQL_PROFILE(
    task_name => 'task_name',
    name      => 'my_profile'
  );
END;
/

-- 確認・削除
SELECT name, sql_text, status FROM dba_sql_profiles;

BEGIN
  DBMS_SQLTUNE.DROP_SQL_PROFILE(name => 'my_profile');
END;
/
```

### 使い分けの目安

| 手法 | 対象 | 性質 |
|---|---|---|
| ヒストグラム | テーブル・カラム単位 | 根本対策。複数SQLに広く効く |
| SQLプロファイル | 特定のSQL文単位 | 対症療法。即効性がある |

まずヒストグラムを試し、改善しなければSQLプロファイルを検討するのがセオリー。

---

## 4. サブクエリの集計結果とインデックス

### 結論

サブクエリやWITH句の結果セットに**インデックスは存在しない**。メモリ上またはTEMP表領域に一時的に生成されるデータであり、実テーブルではないため。

### 影響

- ネステッドループ結合が使えず、ハッシュ結合やソートマージ結合が選択される
- WITH句がマテリアライズされた場合の一時表にもインデックスは作られない

### 対処法

#### 方法1：グローバル一時表を使う

```sql
CREATE GLOBAL TEMPORARY TABLE tmp_sales_summary (
    dept_id  NUMBER,
    total    NUMBER
) ON COMMIT DELETE ROWS;

CREATE INDEX idx_tmp_dept ON tmp_sales_summary(dept_id);

INSERT INTO tmp_sales_summary
SELECT dept_id, SUM(amount) FROM sales GROUP BY dept_id;

SELECT *
FROM large_table a JOIN tmp_sales_summary b
ON a.dept_id = b.dept_id;
```

#### 方法2：結合の方向を意識する

サブクエリ（小）→ 実テーブル（大）の方向でNested Loopを使えば、実テーブル側のインデックスを活用できる。

```sql
SELECT /*+ LEADING(b) USE_NL(a) */ *
FROM large_table a
JOIN (
    SELECT dept_id, SUM(amount) AS total
    FROM sales GROUP BY dept_id
) b ON a.dept_id = b.dept_id;
```

**重要：** サブクエリにインデックスがないこと自体は必ずしも問題ではなく、結合の駆動表と被駆動表のどちら側にインデックスがあるかを意識することが重要。

---

## 5. 大規模テーブルのインデックス設計

### インデックスサイズの目安

B-Treeインデックスは1行あたり約10〜20バイト。

| 件数 | インデックス1本の目安サイズ |
|---|---|
| 1,000万件 | 約100〜200MB |
| 5,000万件 | 約500MB〜1GB |

```sql
-- 既存インデックスのサイズ確認
SELECT segment_name, bytes/1024/1024 AS size_mb
FROM user_segments
WHERE segment_type = 'INDEX';
```

### 検索速度の変化

1,000万件テーブルで特定条件の履歴取得を行う場合の目安：

| 条件 | 実行時間 |
|---|---|
| インデックスなし（フルスキャン） | 数十秒〜数分 |
| 適切なインデックスあり | 数十ミリ秒〜数秒 |

数百倍〜数千倍の差が出ることも珍しくない。

### 入出庫履歴テーブルの推奨インデックス例

```sql
-- 品目 × 日付（最も頻出する検索パターン）
CREATE INDEX idx_hist_item_date
ON inventory_history(item_code, transaction_date);

-- 倉庫 × 日付（倉庫別の履歴照会用）
CREATE INDEX idx_hist_wh_date
ON inventory_history(warehouse_code, transaction_date);

-- 入出庫区分 × 日付（入庫のみ・出庫のみの抽出用）
CREATE INDEX idx_hist_type_date
ON inventory_history(transaction_type, transaction_date);
```

### トレードオフ

- INSERT時にインデックス1本あたり数%〜10%のオーバーヘッドが発生
- 入出庫履歴は「読み込み > 書き込み」の性質を持つため、2〜3本が妥当

---

## 6. Cost/Bytesが爆増した場合の対応

### 状況

WITH句による最適化で実行時間が50%改善したが、実行計画のBytesが34M→356G、Costが565K→81Mに爆増した。

### 確認手順

```sql
ALTER SESSION SET STATISTICS_LEVEL = ALL;

-- 対象SQLを実行後
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    NULL, NULL, 'ALLSTATS LAST'
));
```

以下の3点を確認する：

1. **E-Rows vs A-Rows** — 推定行数と実績行数の乖離。推定が膨れているだけで実処理量は少ないケースが非常に多い
2. **Buffers（実際のI/O量）** — 改善前より減っていれば実際のリソース消費は減っている
3. **Starts × A-Rows** — 各ステップが実際に何回、何行処理したか

### 爆増の原因

WITH句をマテリアライズした結果、結合順序やアクセスパスが変わり推定の計算方法が変わったことが原因。WITH句の結果セットには統計情報がないため、オプティマイザはカーディナリティを大きく見積もりがち。

### 対応方針

| 実績値の状況 | 対応 |
|---|---|
| Buffersも改善、A-Rowsも妥当 | 何もしなくてよい。推定値の乖離として報告 |
| 実績値に懸念あり | 統計情報の再収集、CARDINALITYヒント、INLINE/MATERIALIZE切替で調整 |

```sql
-- 統計情報の再収集
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => 'SCHEMA_NAME',
    tabname    => 'YOUR_TABLE',
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    cascade    => TRUE
  );
END;
/

-- カーディナリティの補正
WITH /*+ CARDINALITY(cte_name, 1000) */ cte_name AS (...)
```

### 報告時の記載例

```
■ 改善結果
  実行時間    : 改善前 ○秒 → 改善後 ○秒（50%改善）
  Buffers     : 改善前 ○○ → 改善後 ○○

■ 実行計画の推定値について
  Cost/Bytesの増加はオプティマイザの推定誤差によるもの。
  ALLSTATS LASTで確認した実績値（A-Rows, Buffers）は
  改善前より良好であり、実際のリソース消費は削減されている。
```

---

## 7. DISPLAY_CURSORで正しいSQLを参照する方法

### 問題

`DISPLAY_CURSOR(NULL, NULL, ...)`は最後に実行されたSQLのカーソルを表示するが、意図したSQLが取れないことがある。

### 解決策1：SQL_IDを指定する

```sql
-- 1. 対象SQLを実行
SELECT ...;

-- 2. 直前のSQL_IDを取得
SELECT prev_sql_id, prev_child_number
FROM v$session
WHERE sid = SYS_CONTEXT('USERENV', 'SID');

-- 3. SQL_IDを指定して実行計画を取得
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    'ここにprev_sql_id',
    prev_child_number,
    'ALLSTATS LAST'
));
```

### 解決策2：V$SQLから検索

```sql
SELECT sql_id, child_number, sql_text, executions
FROM v$sql
WHERE sql_text LIKE '%特徴的なテーブル名%'
  AND sql_text NOT LIKE '%v$sql%'
ORDER BY last_active_time DESC;
```

### 実務Tips：SQLに一意のコメントを付与

```sql
-- 改善前
SELECT /* BEFORE_001 */ * FROM inventory_history WHERE ...;

-- 改善後
SELECT /* AFTER_001 */ * FROM inventory_history WHERE ...;

-- コメントで検索
SELECT sql_id, child_number
FROM v$sql
WHERE sql_text LIKE '%BEFORE_001%'
  AND sql_text NOT LIKE '%v$sql%';
```

---

## 8. INLINEヒントの正しい使い方

### 正しい記述位置

ヒントはWITH句の中ではなく、**メインクエリのSELECT直後**に記述する。

```sql
-- OK：メインクエリのSELECT直後
WITH cte AS (
    SELECT dept_id, SUM(amount) AS total
    FROM sales
    GROUP BY dept_id
)
SELECT /*+ INLINE */ *
FROM large_table a
JOIN cte b ON a.dept_id = b.dept_id;
```

```sql
-- NG：WITH句の中に書いても効かない
WITH /*+ INLINE */ cte AS (...)
SELECT * FROM ...;
```

### ヒントの構文

ヒントとして有効なのは `/*+ ... */` 形式のみ。`--`（ハイフン2個）はただのコメントであり、ヒントとして認識されない。

```sql
-- OK
SELECT /*+ INLINE */ * FROM ...;

-- NG（ただのコメント）
SELECT --+ INLINE
* FROM ...;
```

### INLINEの適用範囲

メインクエリの `SELECT /*+ INLINE */` は**すべてのWITH句に一括適用**される。入れ子のCTEでも同様。

```sql
WITH cte1 AS (...),
     cte2 AS (SELECT ... FROM cte1 ...),
     cte3 AS (SELECT ... FROM cte2 ...)
SELECT /*+ INLINE */ *
FROM cte3 JOIN large_table ...;
-- → cte1, cte2, cte3すべてがインライン展開される
```

### 個別のCTEを制御したい場合

Oracle標準のヒントでは個別のCTEを指定してINLINE/MATERIALIZEを切り分けることはできない。対処法は以下の通り：

- マテリアライズしたいものはグローバル一時表に切り出す
- インライン展開したいものはFROM句のサブクエリに書き換え、マテリアライズしたいものだけWITH句に残す

### 効いているかの確認

実行計画に `TEMP TABLE TRANSFORMATION` が出ていなければインライン展開されている。

```sql
EXPLAIN PLAN FOR
WITH cte AS (...)
SELECT /*+ INLINE */ * FROM ...;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```
