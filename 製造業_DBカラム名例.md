# 部品表変更管理システムのデータベース設計とカラム命名規則

## 📋 はじめに
製造業における部品表（BOM）の変更管理と、その実施状況をトラッキングするシステムのデータベース設計について、実務で使われているカラム命名パターンをまとめました。

## 🏗️ テーブル構成

### 1. 変更管理ヘッダーテーブル (change_headers / engineering_change_notices)

変更指示の基本情報を管理するマスタテーブル

```sql
-- 基本情報
change_id                 -- 変更ID（主キー）
ecn_number               -- ECN番号（Engineering Change Notice）
eco_number               -- ECO番号（Engineering Change Order）
change_request_number    -- 変更要求番号
revision_number          -- リビジョン番号
change_type              -- 変更区分（NEW/MODIFY/OBSOLETE/TEMPORARY）
change_category          -- 変更カテゴリ（DESIGN/PROCESS/SUPPLIER/QUALITY）
priority_level           -- 優先度（CRITICAL/HIGH/MEDIUM/LOW）
severity_level           -- 重要度（1-5）

-- 日付関連
request_date             -- 要求日
planned_date            -- 計画実施日
effective_date          -- 有効開始日
implementation_date     -- 実施日
completion_date         -- 完了日
cutoff_date            -- 切替日
phase_in_date          -- 段階導入開始日
phase_out_date         -- 段階廃止完了日

-- ステータス
status_code            -- ステータスコード
approval_status        -- 承認ステータス（DRAFT/PENDING/APPROVED/REJECTED）
implementation_status  -- 実施ステータス
workflow_status        -- ワークフローステータス

-- 理由・説明
change_reason_code     -- 変更理由コード
reason_category        -- 理由カテゴリ
description           -- 説明
impact_description    -- 影響説明
implementation_notes  -- 実施注記
```

### 2. 変更明細テーブル (change_details / change_items)

変更対象の部品情報を管理

```sql
-- キー情報
detail_id              -- 明細ID（主キー）
change_id             -- 変更ID（外部キー）
line_number           -- 行番号
sequence_number       -- シーケンス番号

-- 部品情報
part_number           -- 部品番号
item_code            -- 品目コード
sku                  -- SKU
component_id         -- コンポーネントID
material_code        -- 材料コード

-- 変更前後の情報
before_revision      -- 変更前リビジョン
after_revision       -- 変更後リビジョン
old_part_number     -- 旧部品番号
new_part_number     -- 新部品番号
old_quantity        -- 旧数量
new_quantity        -- 新数量
old_unit_price      -- 旧単価
new_unit_price      -- 新単価

-- 在庫切替情報
disposition_code     -- 処置コード（USE_UP/SCRAP/REWORK/RETURN）
inventory_action     -- 在庫処置
use_up_quantity     -- 使い切り数量
scrap_quantity      -- 廃棄数量
rework_quantity     -- 再加工数量
```

### 3. サプライヤー連絡管理テーブル (supplier_notifications)

発注先への連絡状況を管理

```sql
-- キー情報
notification_id        -- 通知ID（主キー）
change_id             -- 変更ID（外部キー）
detail_id             -- 明細ID（外部キー）
supplier_id           -- サプライヤーID
vendor_code           -- ベンダーコード

-- 連絡情報
notification_type      -- 通知タイプ
notification_method    -- 通知方法（EMAIL/FAX/EDI/PORTAL）
contact_person_id      -- 担当者ID
notification_date      -- 通知日
sent_datetime         -- 送信日時
acknowledged_date     -- 確認日
response_due_date     -- 回答期限

-- ステータス
notification_status    -- 通知ステータス（DRAFT/SENT/ACKNOWLEDGED/CONFIRMED）
supplier_response      -- サプライヤー回答（ACCEPT/REJECT/CONDITIONAL）
confirmation_status    -- 確認ステータス

-- 文書管理
document_number       -- 文書番号
attachment_id         -- 添付ファイルID
message_content       -- メッセージ内容
supplier_comments     -- サプライヤーコメント
```

### 4. 購買発注管理テーブル (purchase_orders)

変更に伴う発注を管理

```sql
-- 基本情報
po_id                 -- 発注ID（主キー）
po_number            -- 発注番号
change_id            -- 変更ID（外部キー）
supplier_id          -- サプライヤーID

-- 発注情報
order_date           -- 発注日
requested_date       -- 要求納期
promised_date        -- 回答納期
order_quantity       -- 発注数量
unit_price          -- 単価
total_amount        -- 合計金額
currency_code       -- 通貨コード

-- ステータス
po_status            -- 発注ステータス
confirmation_flag    -- 確認フラグ
acknowledgment_date  -- 受注確認日
```

### 5. 受入検査テーブル (receiving_inspections)

部品の受入と検査状況を管理

```sql
-- 受入情報
receiving_id          -- 受入ID（主キー）
po_id                -- 発注ID（外部キー）
receipt_number       -- 受入番号
grn_number          -- 入庫番号（Goods Receipt Note）
receiving_date      -- 受入日
received_quantity   -- 受入数量
accepted_quantity   -- 合格数量
rejected_quantity   -- 不合格数量

-- 検査情報
inspection_id        -- 検査ID
inspection_type      -- 検査タイプ（INCOMING/SAMPLING/FULL）
inspection_date      -- 検査日
inspection_status    -- 検査ステータス
qc_status           -- QCステータス（PASS/FAIL/CONDITIONAL/PENDING）
quality_rating      -- 品質評価
inspection_method   -- 検査方法

-- 検査結果
inspection_result    -- 検査結果
defect_code         -- 不良コード
ncr_number          -- 不適合報告書番号
deviation_number    -- 逸脱番号
corrective_action   -- 是正処置

-- ロット情報
lot_number          -- ロット番号
batch_number        -- バッチ番号
serial_number       -- シリアル番号
expiry_date        -- 有効期限
```

### 6. 在庫トランザクションテーブル (inventory_transactions)

入庫・出庫の動きを管理

```sql
-- トランザクション基本情報
transaction_id        -- トランザクションID（主キー）
transaction_type      -- 取引タイプ（RECEIPT/ISSUE/TRANSFER/ADJUST）
transaction_date      -- 取引日
transaction_number    -- 取引番号

-- 在庫移動情報
warehouse_code        -- 倉庫コード
location_from        -- 移動元ロケーション
location_to          -- 移動先ロケーション
bin_location         -- 棚番号
storage_area         -- 保管エリア

-- 数量情報
quantity             -- 数量
unit_of_measure      -- 単位
before_quantity      -- 移動前数量
after_quantity       -- 移動後数量

-- 参照情報
reference_type       -- 参照タイプ（PO/WO/SO）
reference_number     -- 参照番号
receiving_id         -- 受入ID（外部キー）
work_order_id        -- 製造指図ID
```

### 7. 製造ライン使用実績テーブル (production_line_usage)

ラインでの組み立て実績を管理

```sql
-- 基本情報
usage_id              -- 使用ID（主キー）
work_order_id         -- 製造指図ID
wo_number            -- 製造指図番号
production_date      -- 生産日
shift_code           -- シフトコード

-- ライン情報
line_id              -- ラインID
line_code            -- ラインコード
work_center_id       -- ワークセンターID
station_id           -- ステーションID
cell_id              -- セルID

-- 部品使用情報
part_number          -- 部品番号
consumed_quantity    -- 消費数量
planned_quantity     -- 計画数量
actual_quantity      -- 実績数量
scrap_quantity       -- スクラップ数量

-- 実績情報
start_datetime       -- 開始日時
end_datetime         -- 終了日時
cycle_time_actual    -- 実績サイクルタイム
operator_id          -- 作業者ID
completion_flag      -- 完了フラグ

-- トレーサビリティ
lot_number           -- 使用ロット番号
serial_number        -- 製品シリアル番号
traceability_code    -- トレーサビリティコード
```

### 8. ワークフロー管理テーブル (workflow_instances)

承認フローの実行状況を管理

```sql
-- ワークフロー情報
workflow_id           -- ワークフローID（主キー）
change_id            -- 変更ID（外部キー）
workflow_template_id  -- テンプレートID
current_step         -- 現在のステップ
total_steps          -- 総ステップ数

-- 承認情報
approver_id          -- 承認者ID
approval_level       -- 承認レベル
approval_date        -- 承認日
approval_result      -- 承認結果（APPROVED/REJECTED/PENDING）
comments             -- コメント
delegation_flag      -- 委任フラグ
escalation_flag      -- エスカレーションフラグ
```

## 🔧 共通カラム（全テーブルに追加）

```sql
-- 監査証跡
created_at           -- 作成日時
created_by           -- 作成者
updated_at           -- 更新日時
updated_by           -- 更新者
deleted_at           -- 論理削除日時
deleted_by           -- 削除者

-- レコード管理
is_active            -- 有効フラグ
is_deleted           -- 削除フラグ
version_number       -- バージョン番号
revision_number      -- リビジョン番号

-- テナント管理（マルチテナント対応の場合）
company_id           -- 会社ID
plant_code           -- 工場コード
site_id              -- サイトID
organization_id      -- 組織ID
```

## 📊 ステータスコードの例

### 変更実施ステータス
```sql
DRAFT              -- 下書き
PENDING_APPROVAL   -- 承認待ち
APPROVED           -- 承認済み
IN_PROGRESS        -- 実施中
SUPPLIER_NOTIFIED  -- サプライヤー通知済み
ORDER_PLACED       -- 発注済み
RECEIVING          -- 受入中
INSPECTION         -- 検査中
IN_STOCK          -- 在庫済み
IN_PRODUCTION     -- 生産使用中
COMPLETED         -- 完了
CANCELLED         -- キャンセル
ON_HOLD           -- 保留
```

## 💡 命名規則のベストプラクティス

### 1. 一貫性のあるサフィックス
- `_id`: 主キー、外部キー
- `_code`: コード値
- `_number`: 番号（人が読める識別子）
- `_date`: 日付のみ
- `_datetime`, `_at`: 日時
- `_flag`: ブールフラグ
- `_status`: ステータス
- `_type`: タイプ区分
- `_quantity`, `_qty`: 数量
- `_amount`: 金額
- `_count`: カウント数

### 2. 略語の使用ガイドライン
```
po      → purchase_order
wo      → work_order
so      → sales_order
qty     → quantity
wh      → warehouse
mfg     → manufacturing
bom     → bill_of_materials
uom     → unit_of_measure
grn     → goods_receipt_note
ncr     → non_conformance_report
ecn     → engineering_change_notice
```

### 3. 予約語の回避
```sql
-- 避けるべき名前 → 推奨名
order     → po_order, sales_order
user      → app_user, system_user
table     → data_table
index     → idx_number
```

## 🔍 インデックス設計の推奨

```sql
-- 複合インデックスの例
CREATE INDEX idx_change_status_date ON change_headers(status_code, effective_date);
CREATE INDEX idx_supplier_change ON supplier_notifications(supplier_id, change_id);
CREATE INDEX idx_part_warehouse ON inventory_transactions(part_number, warehouse_code);
```

## まとめ

製造業の変更管理システムでは、トレーサビリティと監査証跡が重要です。各工程の状態を正確に追跡できるよう、ステータス管理と日時記録を徹底し、部品の変更から実際の使用まで一貫した管理を実現することが大切です。

# 製造業システムのデータベーステーブル命名規則と実例集

## 📋 はじめに
製造業のシステム開発において、データベースのテーブル名は可読性と保守性に大きく影響します。本記事では、実際のメガベンチャーや大手製造業で使われているテーブル命名パターンを体系的にまとめました。

## 🏗️ テーブル命名の基本原則

### 1. 命名規則のパターン

#### **複数形 vs 単数形**
```sql
-- 複数形パターン（一般的）
products, orders, users, inventories

-- 単数形パターン
product, order, user, inventory

-- 日本企業でよく見る複合パターン
m_product, t_order  -- マスタ/トランザクション接頭辞付き
```

#### **スネークケース vs パスカルケース**
```sql
-- snake_case（推奨）
purchase_orders, inventory_transactions, quality_inspections

-- PascalCase
PurchaseOrders, InventoryTransactions, QualityInspections

-- 略語混在
po_headers, wo_details, bom_items
```

## 📊 カテゴリ別テーブル名サンプル

### 1. マスタデータ系テーブル

#### **製品・部品マスタ**
```sql
-- 基本形
products                    -- 製品マスタ
items                      -- 品目マスタ
parts                      -- 部品マスタ
components                 -- コンポーネントマスタ
materials                  -- 材料マスタ
articles                   -- 品番マスタ

-- 詳細形
product_master             -- 製品マスタ
item_master               -- 品目マスタ
part_master               -- 部品マスタ
material_master           -- 材料マスタ

-- 接頭辞付き
m_products                -- マスタ製品
m_items                   -- マスタ品目
mst_products              -- マスタ製品（mst接頭辞）
master_products           -- マスタ製品（フル表記）

-- 階層・カテゴリ
product_categories        -- 製品カテゴリ
product_families         -- 製品ファミリー
product_groups           -- 製品グループ
product_hierarchies      -- 製品階層
item_classifications     -- 品目分類
```

#### **BOM（部品表）関連**
```sql
-- 基本BOM
boms                      -- BOM
bill_of_materials        -- 部品表（フル表記）
bom_headers              -- BOMヘッダー
bom_details              -- BOM明細
bom_items                -- BOM品目
bom_components           -- BOM構成部品

-- BOM種類別
engineering_boms         -- 設計BOM
manufacturing_boms       -- 製造BOM
service_boms            -- サービスBOM
planning_boms           -- 計画BOM

-- BOM構造
bom_structures          -- BOM構造
bom_trees              -- BOMツリー
bom_revisions          -- BOMリビジョン
bom_alternatives       -- 代替BOM
where_used             -- 逆展開（使用先）
```

#### **組織・場所マスタ**
```sql
-- 会社・組織
companies               -- 会社
organizations          -- 組織
business_units         -- 事業部
departments            -- 部門
divisions              -- 部署
cost_centers           -- コストセンター

-- 製造拠点
plants                 -- 工場
sites                  -- サイト
factories              -- 工場
facilities             -- 施設
production_sites       -- 生産拠点
manufacturing_plants   -- 製造工場

-- 倉庫・保管場所
warehouses             -- 倉庫
storage_locations      -- 保管場所
warehouse_locations    -- 倉庫ロケーション
bins                   -- 棚
storage_bins          -- 保管棚
inventory_locations    -- 在庫場所
stockrooms            -- 在庫室
```

#### **取引先マスタ**
```sql
-- サプライヤー
suppliers              -- サプライヤー
vendors                -- ベンダー
suppliers_master       -- サプライヤーマスタ
vendor_master         -- ベンダーマスタ
business_partners     -- ビジネスパートナー
trading_partners      -- 取引先

-- 顧客
customers             -- 顧客
clients               -- クライアント
accounts              -- アカウント
customer_master       -- 顧客マスタ
ship_to_parties      -- 出荷先
bill_to_parties      -- 請求先
sold_to_parties      -- 販売先
```

### 2. トランザクション系テーブル

#### **受発注関連**
```sql
-- 発注
purchase_orders           -- 発注
po_headers               -- 発注ヘッダー
po_details               -- 発注明細
po_lines                 -- 発注行
purchase_requisitions    -- 購買要求
procurement_requests     -- 調達要求
rfqs                    -- 見積依頼（Request for Quotation）
quotations              -- 見積

-- 受注
sales_orders            -- 受注
so_headers              -- 受注ヘッダー
so_details              -- 受注明細
so_lines                -- 受注行
customer_orders         -- 顧客注文
order_entries           -- 注文入力
order_confirmations     -- 注文確認
```

#### **在庫移動・取引**
```sql
-- 在庫トランザクション
inventory_transactions    -- 在庫取引
stock_movements          -- 在庫移動
inventory_transfers      -- 在庫移管
material_movements       -- 材料移動
goods_movements         -- 商品移動

-- 入出庫
goods_receipts          -- 入庫
goods_issues            -- 出庫
receivings              -- 受入
receipts                -- 受領
stock_entries           -- 在庫入力
warehouse_entries       -- 倉庫入力

-- 棚卸
physical_inventories    -- 実地棚卸
inventory_counts        -- 在庫カウント
cycle_counts           -- サイクルカウント
stock_takes            -- 棚卸
inventory_adjustments   -- 在庫調整
```

#### **生産・製造関連**
```sql
-- 製造指図
work_orders             -- 製造指図
production_orders       -- 生産指図
manufacturing_orders    -- 製造オーダー
wo_headers             -- 製造指図ヘッダー
wo_operations          -- 製造指図作業
wo_components          -- 製造指図構成部品

-- 生産計画
production_plans        -- 生産計画
production_schedules    -- 生産スケジュール
master_schedules       -- マスタスケジュール
mps_records           -- MPS記録
mrp_records           -- MRP記録
capacity_plans        -- 能力計画

-- 生産実績
production_results      -- 生産実績
production_outputs     -- 生産出力
production_reports     -- 生産報告
shop_floor_reports     -- 現場報告
completion_reports     -- 完了報告
production_confirmations -- 生産確認
```

### 3. 品質管理系テーブル

```sql
-- 検査
inspections             -- 検査
quality_inspections     -- 品質検査
inspection_plans        -- 検査計画
inspection_results      -- 検査結果
inspection_records      -- 検査記録
qc_results             -- QC結果

-- 品質記録
quality_records         -- 品質記録
quality_issues         -- 品質問題
defects                -- 不良
defect_records         -- 不良記録
non_conformances       -- 不適合
ncrs                   -- 不適合報告（NCR）
ncr_records           -- NCR記録

-- 品質管理
quality_controls        -- 品質管理
quality_standards      -- 品質基準
specifications         -- 仕様
quality_certificates   -- 品質証明書
coa_records           -- 分析証明書（Certificate of Analysis）
test_results          -- テスト結果
```

### 4. 変更管理系テーブル

```sql
-- 変更管理
change_orders           -- 変更指示
change_requests        -- 変更要求
change_notices         -- 変更通知
engineering_changes    -- 設計変更
ecns                   -- 設計変更通知（ECN）
ecos                   -- 設計変更指示（ECO）
ecrs                   -- 設計変更要求（ECR）

-- 変更詳細
change_headers         -- 変更ヘッダー
change_details         -- 変更明細
change_items          -- 変更品目
change_impacts        -- 変更影響
change_implementations -- 変更実施
affected_items        -- 影響品目
```

### 5. 物流・配送系テーブル

```sql
-- 出荷
shipments              -- 出荷
shipping_notices       -- 出荷通知
delivery_notes        -- 納品書
packing_lists         -- パッキングリスト
dispatch_records      -- 発送記録
asns                  -- 事前出荷通知（ASN）

-- 配送
deliveries            -- 配送
delivery_schedules    -- 配送スケジュール
transport_orders      -- 輸送指示
freight_orders       -- 貨物注文
carrier_assignments  -- 運送業者割当
route_plans          -- ルート計画
```

### 6. 財務・コスト系テーブル

```sql
-- コスト
cost_records          -- コスト記録
standard_costs       -- 標準原価
actual_costs         -- 実際原価
cost_calculations    -- 原価計算
material_costs       -- 材料費
labor_costs         -- 労務費
overhead_costs      -- 間接費

-- 価格
price_lists         -- 価格表
pricing_records     -- 価格記録
price_histories     -- 価格履歴
discount_rules      -- 割引ルール
```

## 🔧 接頭辞・接尾辞パターン

### **接頭辞による分類**
```sql
-- マスタ/トランザクション
m_products           -- マスタ
t_orders            -- トランザクション
r_reports           -- レポート
v_views             -- ビュー
tmp_work_tables     -- 一時テーブル

-- システム別
erp_products        -- ERPシステム
mes_work_orders     -- MESシステム
wms_locations       -- WMSシステム
qms_inspections     -- QMSシステム
plm_changes         -- PLMシステム

-- 環境別
stg_products        -- ステージング
raw_products        -- 生データ
dwh_products        -- データウェアハウス
```

### **接尾辞による分類**
```sql
-- 構造表現
products_master      -- マスタ
orders_header       -- ヘッダー
orders_detail       -- 明細
orders_summary      -- サマリー

-- 状態・履歴
products_current    -- 現在
products_history    -- 履歴
products_archive    -- アーカイブ
products_backup     -- バックアップ

-- 一時・作業
products_temp       -- 一時
products_work       -- 作業
products_staging    -- ステージング
```

## 📐 リレーション・中間テーブル

```sql
-- 多対多の関係
product_suppliers           -- 製品-サプライヤー
product_categories_map      -- 製品-カテゴリマッピング
item_warehouse_locations    -- 品目-倉庫ロケーション
bom_substitute_parts       -- BOM代替部品

-- 関連・リンク
order_shipment_links       -- 注文-出荷リンク
po_so_relations           -- 発注-受注関係
work_order_materials      -- 製造指図-材料

-- ジャンクション
supplier_item_junction     -- サプライヤー品目ジャンクション
customer_product_xref      -- 顧客製品クロスリファレンス
```

## 🎯 業界特有のテーブル名

### **自動車業界**
```sql
vehicle_models         -- 車両モデル
vin_records           -- 車両識別番号記録
assembly_lines        -- 組立ライン
paint_schedules       -- 塗装スケジュール
jit_calls            -- JITコール
kanban_cards         -- かんばんカード
sequence_plans       -- シーケンス計画
```

### **電子機器業界**
```sql
pcb_designs          -- PCB設計
component_reels      -- 部品リール
smt_programs        -- SMTプログラム
reflow_profiles     -- リフロープロファイル
test_fixtures       -- テスト治具
firmware_versions   -- ファームウェアバージョン
```

### **医薬品・医療機器業界**
```sql
batches             -- バッチ
batch_records       -- バッチ記録
validation_records  -- バリデーション記録
stability_studies   -- 安定性試験
clinical_lots      -- 臨床ロット
dhr_records        -- 機器履歴記録（DHR）
dmr_records        -- 機器マスタ記録（DMR）
```

## 💡 命名のベストプラクティス

### 1. **一貫性を保つ**
```sql
-- Good: 一貫した命名
purchase_orders
purchase_order_lines
purchase_order_approvals

-- Bad: 不統一な命名
purchase_orders
po_lines
purchasing_approval
```

### 2. **略語の統一**
```sql
-- 組織で決めた略語リスト
po   = purchase_order    -- 発注
so   = sales_order       -- 受注
wo   = work_order        -- 製造指図
inv  = inventory         -- 在庫
qty  = quantity          -- 数量
mfg  = manufacturing     -- 製造
wh   = warehouse         -- 倉庫
```

### 3. **予約語の回避**
```sql
-- 避けるべき名前 → 推奨
order        → orders, sales_orders
user         → users, app_users
table        → data_tables
transaction  → transactions, trans_records
```

### 4. **長さのバランス**
```sql
-- 適切な長さ（15-30文字程度）
inventory_transactions    ✓
production_schedules      ✓

-- 長すぎる
inventory_transaction_detail_records_history  ✗

-- 短すぎて不明瞭
inv_tr  ✗
ps      ✗
```

## 🔍 パフォーマンス考慮の命名

```sql
-- インデックス対応の命名
-- 検索頻度の高いカラムを表す名前
orders_by_date         -- 日付別注文（日付インデックス想定）
products_active       -- アクティブ製品（ステータスインデックス想定）

-- パーティション対応
orders_2024          -- 年次パーティション
inventory_q1_2024    -- 四半期パーティション
sales_data_202401    -- 月次パーティション
```

## まとめ

テーブル命名は、チーム全体で統一したルールを持つことが重要です。製造業では特に、業務プロセスの流れを反映した分かりやすい名前付けが求められます。略語を使う場合は必ずドキュメント化し、新規メンバーでも理解できるようにしておきましょう。

また、将来的なシステム統合や国際化を見据えて、最初から英語での命名を採用することをお勧めします。

# 製造業におけるヘッダー/明細テーブルの命名パターン完全ガイド

## 📋 はじめに
製造業のデータベース設計では、ヘッダー/明細構造（親子関係）が頻繁に使用されます。本記事では、実際の企業で使われている様々な命名パターンを体系的に整理し、それぞれのメリット・デメリットを解説します。

## 🏗️ 基本的な命名パターン

### 1. **Headers/Details パターン（最も一般的）**

```sql
-- 発注の例
purchase_order_headers       -- ヘッダーテーブル
purchase_order_details       -- 明細テーブル

-- 短縮形
po_headers                   -- ヘッダーテーブル
po_details                   -- 明細テーブル

-- 実装例
CREATE TABLE order_headers (
    order_id         INT PRIMARY KEY,
    order_date       DATE,
    customer_id      INT,
    total_amount     DECIMAL(10,2)
);

CREATE TABLE order_details (
    detail_id        INT PRIMARY KEY,
    order_id         INT REFERENCES order_headers(order_id),
    line_number      INT,
    product_id       INT,
    quantity         INT,
    unit_price       DECIMAL(10,2)
);
```

**メリット：**
- 業界標準で最も認知度が高い
- ERP系システムで広く採用
- 親子関係が明確

**採用企業例：** SAP、Oracle ERP、Microsoft Dynamics

### 2. **Headers/Lines パターン**

```sql
-- Linesを使用するパターン
sales_order_headers         -- ヘッダーテーブル
sales_order_lines           -- 明細テーブル（Lineは「行」の意味）

-- 短縮形
so_headers                   -- ヘッダーテーブル
so_lines                     -- 明細テーブル

-- 他の例
invoice_headers              -- 請求書ヘッダー
invoice_lines               -- 請求書明細行

quotation_headers           -- 見積ヘッダー
quotation_lines            -- 見積明細行
```

**メリット：**
- 「明細行」という帳票イメージに合致
- 経理・会計系で好まれる
- Detailsより短い

**採用例：** NetSuite、QuickBooks、財務会計系システム

### 3. **Headers/Items パターン**

```sql
-- Itemsを使用するパターン
bom_headers                  -- BOMヘッダー
bom_items                    -- BOM構成品目

work_order_headers           -- 製造指図ヘッダー
work_order_items            -- 製造指図品目

shipment_headers            -- 出荷ヘッダー
shipment_items             -- 出荷品目

-- 実装例
CREATE TABLE bom_headers (
    bom_id           INT PRIMARY KEY,
    product_id       INT,
    revision         VARCHAR(10),
    effective_date   DATE
);

CREATE TABLE bom_items (
    item_id          INT PRIMARY KEY,
    bom_id           INT REFERENCES bom_headers(bom_id),
    component_id     INT,
    quantity         DECIMAL(10,3),
    uom              VARCHAR(10)
);
```

**メリット：**
- 「品目」という意味が明確
- 在庫・製品管理系で直感的
- BOMなど部品表系で標準的

### 4. **Master/Details パターン**

```sql
-- マスタ/詳細パターン
order_master                -- マスタテーブル
order_details               -- 詳細テーブル

change_master               -- 変更マスタ
change_details              -- 変更詳細
```

**メリット：**
- 日本企業でよく見るパターン
- 「マスタ」が親であることが明確

**注意点：**
- Masterは本来「マスタデータ」の意味なので混乱の可能性

### 5. **単数形/複数形の使い分けパターン**

```sql
-- 単数がヘッダー、複数が明細
purchase_order              -- ヘッダー（単数）
purchase_order_items        -- 明細（複数）

-- または
production_plan             -- 計画ヘッダー（単数）
production_plan_details     -- 計画詳細（複数）
```

## 📊 業務別の実例集

### **受発注管理**

```sql
-- パターン1: Headers/Details
purchase_order_headers
purchase_order_details

-- パターン2: Headers/Lines  
purchase_order_headers
purchase_order_lines

-- パターン3: 短縮形
po_headers
po_lines

-- パターン4: 番号付き
purchase_orders_h
purchase_orders_d

-- パターン5: レベル表記
purchase_orders_l0          -- レベル0（ヘッダー）
purchase_orders_l1          -- レベル1（明細）
```

### **製造指図**

```sql
-- パターン1: Headers/Operations
work_order_headers          -- WOヘッダー
work_order_operations       -- WO作業工程
work_order_materials       -- WO材料

-- パターン2: 3階層構造
wo_headers                  -- ヘッダー
wo_operations              -- 工程
wo_operation_materials     -- 工程別材料

-- パターン3: Headers/Details/Components
production_order_headers
production_order_details
production_order_components
```

### **在庫移動**

```sql
-- パターン1: Headers/Details
inventory_transfer_headers
inventory_transfer_details

-- パターン2: Documents/Lines
transfer_documents
transfer_document_lines

-- パターン3: Headers/Items
stock_movement_headers
stock_movement_items
```

### **品質検査**

```sql
-- パターン1: Headers/Results
inspection_headers          -- 検査ヘッダー
inspection_results         -- 検査結果

-- パターン2: Plans/Records
inspection_plans           -- 検査計画
inspection_records         -- 検査記録
inspection_measurements    -- 測定値

-- パターン3: Headers/Details/Defects
quality_check_headers
quality_check_details
quality_check_defects
```

## 🔧 特殊なパターン

### **1. 接頭辞/接尾辞による区別**

```sql
-- 接尾辞パターン
orders_hdr                  -- ヘッダー
orders_dtl                  -- 詳細

-- 接頭辞パターン
h_orders                    -- ヘッダー
d_orders                    -- 詳細
i_orders                    -- アイテム

-- 番号パターン
orders_01                   -- ヘッダー
orders_02                   -- 詳細
```

### **2. 階層表現パターン**

```sql
-- 親子孫の3階層
project_headers             -- プロジェクト
project_phases             -- フェーズ
project_tasks              -- タスク

-- BOM階層
bom_parents                -- 親品目
bom_children               -- 子品目
bom_components             -- 構成部品
```

### **3. ドキュメント指向パターン**

```sql
-- ドキュメント/レコード
shipping_documents          -- 出荷ドキュメント
shipping_records           -- 出荷レコード

-- ドキュメント/エントリー
journal_documents          -- 仕訳ドキュメント
journal_entries           -- 仕訳エントリー
```

## 💼 実際の企業での採用例

### **SAP風の命名**
```sql
-- EKKO/EKPO style (実際のSAPテーブル名を参考)
purchase_order_header      -- EKKO相当
purchase_order_item       -- EKPO相当

-- カスタムテーブル
z_change_headers
z_change_items
```

### **Oracle EBS風の命名**
```sql
-- Oracleスタイル
oe_order_headers_all
oe_order_lines_all
po_headers_all
po_lines_all
```

### **Microsoft Dynamics風**
```sql
-- Dynamics風
sales_table               -- ヘッダー
sales_line               -- 明細
purch_table              -- 購買ヘッダー
purch_line               -- 購買明細
```

## 📐 複雑な階層構造の例

### **多段階承認フロー**
```sql
approval_requests           -- 承認要求（ヘッダー）
approval_stages            -- 承認段階
approval_stage_approvers   -- 段階別承認者
approval_histories         -- 承認履歴
```

### **製造工程の階層**
```sql
routing_headers            -- 工程ヘッダー
routing_operations         -- 作業工程
routing_operation_resources -- 工程別リソース
routing_operation_tools    -- 工程別治具
```

### **変更管理の階層**
```sql
-- ECN/ECOの階層構造
change_notices             -- 変更通知（最上位）
change_orders             -- 変更指示
change_order_items        -- 変更品目
change_item_impacts       -- 品目別影響
change_implementations    -- 実施記録
```

## 🎯 選択基準とベストプラクティス

### **選択のポイント**

| パターン | 適している場合 | 避けるべき場合 |
|---------|--------------|--------------|
| Headers/Details | 汎用的、ERP統合 | 特になし |
| Headers/Lines | 帳票イメージ重視 | 品目管理中心 |
| Headers/Items | 在庫・品目中心 | 帳票系 |
| Master/Details | 日本企業文化 | グローバル展開 |

### **推奨される組み合わせ**

```sql
-- 🏆 最も推奨: Headers/Details
order_headers / order_details
change_headers / change_details

-- 📊 帳票系: Headers/Lines  
invoice_headers / invoice_lines
journal_headers / journal_lines

-- 📦 在庫系: Headers/Items
transfer_headers / transfer_items
count_headers / count_items

-- 🏭 製造系: Headers/Operations/Materials
wo_headers / wo_operations / wo_materials
routing_headers / routing_operations
```

## 🔍 アンチパターン（避けるべき命名）

```sql
-- ❌ 不統一な命名
order_headers / order_line_items  -- DetailsかLinesかItemsか統一すべき

-- ❌ 紛らわしい略語
oh / od  -- 短すぎて不明瞭

-- ❌ 予約語の使用
order / order_detail  -- orderは予約語

-- ❌ 単複の不統一
orders_header / order_details  -- 単複を統一すべき
```

## まとめ

ヘッダー/明細の命名は、システム全体で一貫性を保つことが最も重要です。一般的には以下の優先順位で選択することを推奨します：

1. **Headers/Details** - 最も汎用的で認知度が高い
2. **Headers/Lines** - 帳票系や会計系で直感的
3. **Headers/Items** - 在庫管理や品目管理で適切

チーム内で合意を取り、命名規則をドキュメント化して、全員が同じルールに従うようにしましょう。また、既存のERP/MESシステムと統合する場合は、そのシステムの命名規則に合わせることも検討してください。