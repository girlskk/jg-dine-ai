# Thread: 报表日快照生成 — scheduler 固化模式

> 日期: 2026-03-16
> 标签: #report #scheduler #snapshot #order #orderproduct #usecase #repository #idempotency

## Context

`ProductSaleDetail`、`ProductSaleSummary`、`OrderSaleSummary` 三张表不是“查询时临时聚合”的 API 视图，而是每天定时从 `orders` / `order_products` 拉取前一日数据后写入的统计快照表。此前模块已完成 domain / ent / repository / usecase / handler 的查询链路，但缺少实际产出数据的生成链路。

目标是把这三张报表接入 `scheduler`，每天凌晨 1 点自动生成昨天数据，且遵循现有项目分层和 `DailyRevenueFact` 已验证过的任务模式。

## 关键决策

1. **生成入口放在 usecase，不放在 scheduler/task**：scheduler handler 只负责触发和告警，真正的“前一天日期推导、幂等校验、事务包裹、批量写入”放到 interactor。
2. **按 `business_date` 做幂等，不做先删后插**：三张报表 repo 都增加 `ExistsByBusinessDate`，任务命中已生成日期时直接跳过，避免重复写入和误覆盖。
3. **repo 只取数，不做报表组装**：新增 `OrderProductRepo.ListPaidSnapshotsByBusinessDate` 只负责返回“订单商品 + 所属订单”的原始快照；`ProductSaleDetail`、`ProductSaleSummary` 的字段映射和聚合全部放回 usecase 内存中完成。
4. **订单汇总新增报表专用取数方法，不改旧逻辑**：用户明确要求不要动旧 `AllPaidByDate`，因此 `OrderSaleSummary` 改为基于新的 `OrderRepo.ListReportPaidByBusinessDate` 在 usecase 中按门店聚合当前可确定的金额、税额、纸巾费、人均/单均数据。旧方法继续保留给历史调用方。
5. **保留当前源数据缺口，不伪造字段语义**：`ledger_id` / `ledger_name` 在现有订单快照里没有可靠来源，外卖平台拆分（GrabFood / ShopeeFood / FoodPanda）也没有可稳定识别的独立字段，因此当前生成逻辑分别写空值或 `0`，不在任务里猜测映射规则。
6. **先修正本地库结构，再谈生成成功**：`order_products` 的 ent 定义已经切到 `attr_relations` JSON，但本地库还停留在 `attr_relation_id`；如果不先迁移，商品销售明细/汇总会在运行时报 `Unknown column 'order_products.attr_relations'`。

## 最终方案

### 调度链路

- `scheduler/periodic/*.go`：新增三个 cron 注册器，统一使用 `0 1 * * *`
- `scheduler/task/*.go`：新增三个 handler，只调用 `GenerateByDate(ctx, time.Now())`
- `bootstrap/scheduler.go` + `etc/scheduler.toml`：新增三个任务配置项

### 分层职责

- `usecase/productsaledetail/product_sale_detail_generate.go`
- `usecase/productsalesummary/product_sale_summary_generate.go`
- `usecase/ordersalesummary/order_sale_summary_generate.go`

三者共用同一模板：

1. `runDate = util.DayStart(date)`
2. `statDate = runDate.AddDate(0, 0, -1)`
3. 拒绝未来执行日期
4. `DataStore.Atomic(...)`
5. `Repo.ExistsByBusinessDate(statDate)` 命中则跳过
6. 从 `OrderProductRepo.ListPaidSnapshotsByBusinessDate(...)` 或 `OrderRepo.ListReportPaidByBusinessDate(...)` 取原始数据
7. `CreateBulk(...)` 批量落表

### Repository 约定

- 三张报表 repo 均补齐 `ExistsByBusinessDate(ctx, businessDate)`
- 三张报表 repo 的 `CreateBulk` 在空切片时直接返回 `nil`
- `OrderProductRepository` 负责查询日报所需的订单商品快照，不负责报表映射
- `OrderRepository` 保留历史读取方法，例如 `AllPaidByDate`；报表新增 `ListReportPaidByBusinessDate` 专用读取方法，避免改坏旧调用
- `ent/migrate/migrations/20260316170500_order_product_attr_relations.sql` 负责把旧 `attr_relation_id` 迁移为 `attr_relations` JSON，并回填历史数据

## 踩坑与偏差

1. **旧报表查询 DTO 不能直接复用为新快照写入模型**：`ProductSalesDetail` / `ProductSalesSummary` 旧查询更像接口返回，不包含新事实表所需的完整字段，强行复用只会留下半套数据。
2. **不要把“每天产出报表”做成 handler 内拼 SQL**：那会把业务编排、事务、幂等全部塞进 scheduler 层，直接违背现有分层。
3. **`OrderSaleSummary` 不能完全从当前 `Order` struct 重建支付拆分**：当前域对象没有 payment 明细，所以 `CashAmount` / `ThirdPartyAmount` 以及平台细分金额无法可靠计算；不要为了“字段齐全”继续绑定旧查询，或在任务里硬猜规则。
4. **不要为了“字段齐全”编造含义**：当前没有稳定来源的字段就保守落空值/零值，并在 thread 里写明原因，后续如果补了数据模型再升级任务。
5. **旧 `AllPaidByDate` 不能直接拿来做报表**：本地实测它按 `paid_at IS NOT NULL` 取数，会把已退款但曾支付过的订单带进来，导致订单销售汇总污染。正确做法是新增报表专用方法，按 `payment_status = paid` 过滤。
6. **schema 改了不等于库也改了**：代码编译通过不代表任务可跑。`attr_relations` 这种 ent 已生成但数据库未迁移的场景，会在 scheduler 真跑时才爆炸，所以这类变更必须把迁移纳入交付范围。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md), [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
