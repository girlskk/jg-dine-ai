# Thread: 报表 grouped 查询联调与 curl 验证

> 日期: 2026-03-18
> 标签: #report #backend #curl #groupby #orderby #mysql #verification

## Context

用户要求对 backend 的商品销售明细与商品销售汇总接口做本地 `curl` 联调验证：
- `/data/product-sale-detail`
- `/data/product-sale-summary`

验证目标有两类：
1. 销售方式 / 订单类型 / 订单来源相关字段不传时，会触发既有 grouped 查询语义。
2. 接口默认排序字段在实际返回中生效。

联调过程中还需要补最小测试数据，并在真实本地服务上跑通请求。

## 关键决策

1. 不复用旧订单查询接口，直接验证新的报表快照接口和报表表数据，避免口径混淆。
2. grouped 查询不再复用 ent 生成的 `ByXxx` 排序 helper；这些 helper 会生成表限定列，在 MySQL `only_full_group_by` 下会导致 grouped 查询排序失败。
3. grouped 查询单独使用 select 别名排序，普通查询继续沿用 ent 生成排序 helper，避免影响非 grouped 场景。
4. 测试数据用最小 `COPILOT-*` 样本直接写入报表表，而不是反向构造整条订单链路，缩短验证闭环。
5. 本地 `eventcore` 重建后出现独立健康问题时，不阻塞报表 GET 验证；`backend` 用 `docker compose up -d --no-deps backend` 独立启动完成联调。
6. 默认排序链最后一级兜底从 `created_at` 改为 `id`，避免时间戳重复导致分页顺序不稳定；`created_at` 只保留为显式排序字段，不再承担默认保底职责。

## 最终方案

### 代码调整

- `repository/product_sale_detail.go`
  - 补齐 grouped 查询的 `created_at` / `updated_at` 聚合列。
  - grouped 查询改用 `groupOrderBy`，通过 `sql.Selector.OrderExprFunc` 按别名排序。
  - 普通查询和 grouped 查询都支持 `id` 排序，用于默认稳定兜底。
  - 保留普通查询的 `orderBy` 逻辑不变。
- `repository/product_sale_summary.go`
  - 补齐 grouped 查询的 `created_at` / `updated_at` 聚合列。
  - grouped 查询改用 `groupOrderBy`，按别名排序。
  - 普通查询和 grouped 查询都支持 `id` 排序，用于默认稳定兜底。
  - 保留普通查询的 `orderBy` 逻辑不变。
- `api/backend/handler/product_sale_detail.go`
  - 默认排序链最后一级从 `created_at desc` 改为 `id desc`。
- `api/backend/handler/product_sale_summary.go`
  - 默认排序链最后一级从 `created_at desc` 改为 `id desc`。

### 数据准备

- 向 `product_sale_details` / `product_sale_summaries` 写入 `COPILOT-DETAIL-*`、`COPILOT-SUM-*` 最小样本。
- 后续发现样本中使用了非法 UUID（例如 `...s101` / `...d101`），统一修正为合法十六进制 UUID。

### curl 验证结果

1. `product-sale-detail`
   - `sale_mode` 不传时，同一 `order_no=COP-DET-GRP-001` 的两条数据按既有 grouped 逻辑聚合为 1 条，`qty=3`，`total=30`。
   - 传 `sale_mode=single` 后不再跨销售方式聚合，返回 1 条明细，`qty=1`，`total=10`。
   - 排序验证中，`COP-DET-SORT-200` 排在 `COP-DET-SORT-100` 前，说明 `order_no desc` 生效。
  - 切换默认兜底后再次验证，返回顺序仍稳定，且结果尾部并列项现在由 `id desc` 打破而不是 `created_at desc`。
2. `product-sale-summary`
   - 三个字段都不传时，`COPILOT-SUM-GROUP` 的 3 条样本聚合为 1 条，`qty=6`，`total=60`。
   - 三个字段都传后，不走 grouped 查询，返回命中的单条数据，`qty=1`，`total=10`。
   - 排序验证中，`COPILOT-SUM-SORT-A(qty=9)` 在 `COPILOT-SUM-SORT-B(qty=1)` 前，说明 `qty desc` 生效。
  - 切换默认兜底后再次验证，接口继续返回 `SUCCESS`，并列情况下由 `id desc` 负责稳定排序。

## 踩坑与偏差

1. 首轮修复只补了排序映射和 grouped count，没有处理 grouped 排序里的表限定列，导致 MySQL 报 `only_full_group_by` 错误。
2. grouped 查询里即使把 `created_at` 聚合出来，仍不能直接复用 ent 的 `ByCreatedAt`，因为生成 SQL 仍然引用原表列而不是聚合别名。
3. 初始测试数据为了图省事写了非法 UUID，导致 grouped scan 在 summary 查询里直接报 `invalid UUID format`。
4. 本地 compose 中 `eventcore` 和 `eventcore-dapr` 必须成对重建；但即使它随后独立不健康，也不应阻塞纯 backend GET 联调。
5. `created_at` 适合作为业务展示字段，不适合作为默认稳定排序兜底；时间戳重复时会让分页边界不稳定，最终应该由唯一键 `id` 收口。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md), [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
