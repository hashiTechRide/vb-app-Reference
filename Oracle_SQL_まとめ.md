# Oracle SQL パフォーマンス改善・設計まとめ

## 1. WITH句（CTE）の基本

### WITH句はサブクエリ内でも使用可能

WITH句で定義したCTEは、メインクエリ配下のサブクエリであれば、どの深さでも参照可能（Oracle SQL仕様として正しい動作）。

```sql
WITH cte AS (
    SELECT * FROM test WHERE id = 1
)
SELECT *
FROM (
    SELECT *
    FROM (
        SELECT * FROM farm f INNER JOIN cte ON f.id = cte.id
    ) a
    INNER JOIN big_table b ON a.id = b.id
) c
WHERE c.id = 1
```

> **注意:** エイリアスの不整合（例: `farm f` と定義して `j.id` を参照）があると、Oracleが結合条件を正しく認識できずクロス結合に落ちることがある。

---

## 2. CTEとパフォーマンス

### CTEの注意点

- OracleではCTEが**必ずしもキャッシュされるとは限らない**
- オプティマイザがCTEをインライン展開（サブクエリとして各参照箇所に埋め込む）することがある
- その場合、期待した絞り込み効果が得られない

### クロス結合の原因

- 結合条件のエイリアス不整合により、Oracleが結合条件を認識できない
- 数十万件同士のクロス結合は致命的なパフォーマンス問題になる

### 対策の優先順位

1. **インデックスの作成**（根本原因への対処）
2. **クエリの簡素化**（不必要なサブクエリのネスト排除）
3. **実行計画の再確認**

```sql
-- 結合キーにインデックスを作成
CREATE INDEX idx_farm_id ON farm(id);
CREATE INDEX idx_test_id ON test(id);
CREATE INDEX idx_big_table_id ON big_table(id);

-- クエリの簡素化
WITH cte AS (
    SELECT * FROM test WHERE id = 1
)
SELECT f.*, b.*, cte.*
FROM farm f
INNER JOIN cte ON f.id = cte.id
INNER JOIN big_table b ON f.id = b.id
WHERE f.id = 1;
```

---

## 3. インデックスの判断基準

### 設定すべき場合

- WHERE句やJOIN条件で**頻繁に使われるカラム**
- ORDER BYやGROUP BYで頻繁に指定されるカラム
- **カーディナリティが高いカラム**（ほぼ一意な値）

### 設定しないほうがよい場合

- **カーディナリティが低いカラム**（性別やフラグなど2〜3種類しかない値）
- **INSERT/UPDATE/DELETEが頻繁**なテーブル（インデックスの更新コストが増大）

### 実務での判断手順

1. 実行計画を確認してボトルネックを特定
2. `TABLE ACCESS FULL` が出ていて行数が多い場合 → インデックス候補
3. 全体の**5〜10%以下**しか取得しないクエリならインデックスが効果的

```sql
-- 実行計画の確認
EXPLAIN PLAN FOR
SELECT * FROM farm f INNER JOIN test t ON f.id = t.id;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

---

## 4. 在庫系テーブルのインデックス設計

入出庫履歴・棚卸履歴は数十万〜数百万件に蓄積されやすく、検索時は一部のデータだけを取得するパターンがほとんどのため、インデックスが効果的。

### 候補カラム

- 品目コード
- 在庫位置（倉庫コード・棚番号）
- 日付（入出庫日・棚卸日）

### 複合インデックスの設計

業務クエリではカラムを組み合わせて使うことが多いため、**複合インデックス**が有効。

```sql
-- 「この品目の、この倉庫での入出庫履歴を日付順に」
CREATE INDEX idx_io_hist_item_loc_date
ON io_history(item_code, location_code, io_date);

-- 「この期間の棚卸結果を品目ごとに」
CREATE INDEX idx_inv_hist_date_item
ON inventory_history(inventory_date, item_code);
```

### 発注番号ベースの複合インデックス

発注番号で検索することが多く、受入番号・分割番号が付与される場合：

```sql
CREATE INDEX idx_io_hist_order
ON io_history(order_no, receipt_no, split_no);
```

**このインデックス1つで有効になるパターン:**

| パターン | 有効 |
|----------|------|
| `WHERE order_no = 'PO001' AND receipt_no = 1 AND split_no = 1` | ○ |
| `WHERE order_no = 'PO001' AND receipt_no = 1` | ○ |
| `WHERE order_no = 'PO001'` | ○ |
| `WHERE receipt_no = 1 AND split_no = 1`（先頭カラムを飛ばす） | × |

> **ポイント:** 複合インデックスは先頭カラムだけでも検索に使える。WHERE句で最も頻繁に先頭で指定されるカラムを先に置く。

---

## 5. インデックスの有無による速度差

例: テーブルA 30万件 × テーブルB 20万件

| 状態 | 予想速度 |
|------|----------|
| フルスキャン＋クロス結合 | 数分〜数十分（またはタイムアウト） |
| フルスキャン＋正しい結合 | 数十秒〜数分 |
| インデックス＋正しい結合 | **数秒以内** |

クロス結合では 30万 × 20万 = **600億行**の組み合わせが内部的に生成される。

---

## 6. 理論在庫の計算方法

### 従来の方法（UNION ALL + LAG）

- 棚卸結果あり → 棚卸結果 + 棚卸日以降の入出庫を加減算
- 棚卸結果なし → 入出庫理論在庫の計算のみ
- 両者をUNION ALLでマージし、LAGで棚卸結果側を優先選択

### 改善案（COALESCE + FULL OUTER JOIN で1パス化）

```sql
WITH base AS (
    -- 品目・在庫位置ごとに最新の棚卸結果を取得（MAX KEEP方式）
    SELECT item_code,
           location_code,
           MAX(inventory_qty) KEEP (DENSE_RANK LAST ORDER BY inventory_date) AS inventory_qty,
           MAX(inventory_date) AS inventory_date
    FROM inventory_history
    GROUP BY item_code, location_code
),
io_after AS (
    -- 棚卸日以降の入出庫を集計（棚卸がない品目は全期間）
    SELECT io.item_code,
           io.location_code,
           SUM(CASE WHEN io.io_type = 'IN' THEN io.qty ELSE -io.qty END) AS io_qty
    FROM io_history io
    LEFT JOIN base b
        ON io.item_code = b.item_code
       AND io.location_code = b.location_code
    WHERE io.io_date > COALESCE(b.inventory_date, DATE '1900-01-01')
    GROUP BY io.item_code, io.location_code
)
SELECT COALESCE(b.item_code, io.item_code) AS item_code,
       COALESCE(b.location_code, io.location_code) AS location_code,
       COALESCE(b.inventory_qty, 0) + COALESCE(io.io_qty, 0) AS theoretical_qty
FROM base b
FULL OUTER JOIN io_after io
    ON b.item_code = io.item_code
   AND b.location_code = io.location_code;
```

### 改善のポイント

- COALESCEで基準日を切り替えることで、棚卸有無の分岐を1つのロジックに統合
- UNION ALL・LAGが不要になり、テーブルのスキャン回数が減少
- FULL OUTER JOINで棚卸のみ・入出庫のみの両ケースを漏れなくカバー

### MAX KEEP について

`MAX(col) KEEP (DENSE_RANK LAST ORDER BY ...)` は1回のスキャンで最新日のレコードの値を取得できるため、IN句のサブクエリ方式やNOT EXISTS方式よりも効率的。

---

## 7. Oracle独自構文と標準SQL構文

### (+) 記法 vs ANSI JOIN

```sql
-- Oracle独自構文
SELECT *
FROM table_a a, table_b b
WHERE a.id = b.id(+)

-- 標準構文（ANSI JOIN）
SELECT *
FROM table_a a
LEFT JOIN table_b b ON a.id = b.id
```

- **内部処理は同じ**（オプティマイザが同一の実行計画に変換）
- **処理時間に差はない**

### 標準構文を推奨する理由

- (+) 記法ではFULL OUTER JOINが書けない
- OR条件との組み合わせで意図しない結果になることがある
- カンマ区切りのFROM句は**JOIN条件の書き漏れがクロス結合に直結**する
- 標準構文ならON句を書かないとSQLエラーになるため安全

---

## 8. WITH句が使える無料SQLツール

| ツール | 特徴 |
|--------|------|
| **Oracle SQL Developer** | Oracle純正の無料IDE。実行計画の確認も可能。最もおすすめ |
| **DBeaver（Community Edition）** | オープンソース。Oracle以外のDBにも対応 |
| **A5:SQL Mk-2** | 日本製の無料ツール。軽量で日本語UIが使える |
