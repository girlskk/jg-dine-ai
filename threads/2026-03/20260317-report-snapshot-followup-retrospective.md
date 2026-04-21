# Thread: 报表快照三轮追修与复盘

> 日期: 2026-03-17
> 标签: #report #snapshot #reflect #scheduler #order #product #json #store

## Context

在 [20260316-report-daily-scheduler-snapshots](20260316-report-daily-scheduler-snapshots.md) 完成三张报表的“按日快照 + scheduler 生成”主链路后，后续三轮追修暴露出当时没有写透的业务语义与实现约束：

1. `OrderSaleSummary` 的金额字段里，`Amount`、`ThirdPartyAmount`、第三方外卖平台拆分不是同一个概念，不能继续混成若干标量列。
2. `ProductSaleSummary` 不应该再次回查原始交易表，而应该基于刚生成出来的 `ProductSaleDetail` 继续聚合。
3. 按日全门店一次性生成商品/订单报表会让单次查询过大，因此任务需要按门店拆分。
4. 我上一轮把 `OrderSaleSummary` 的聚合键误收敛成了 `StoreID`，但当前业务语义并不是“同店当天改名仍强行合并”，而是保留“同一 `StoreID`、不同 `StoreName` 视为两条日汇总”的统计结果。用户随后已直接在代码中修正。

这次 thread 的目标不是再描述首轮实现，而是把这三轮 follow-up 的真实结论、偏差和可复用约束补齐。

## 关键决策

1. **`OrderSaleSummary` 的金额语义拆开存**：
   `Amount` 继续承载订单金额汇总 JSON；`ThirdPartyAmount` 保持三方支付总额；新增独立 `ThirdPartyPlatform` JSON 存外卖平台拆分，便于未来继续扩展其他平台，而不是继续堆标量列。
2. **商品汇总必须从商品明细聚合，不再二次回查原始订单商品**：
   `ProductSaleDetail` 已经是报表事实快照，`ProductSaleSummary` 直接从内存中的 detail slice 聚合，减少重复查询与重复映射。
3. **门店维度报表任务统一按门店 fan-out**：
   商品和订单报表都先投递每个门店自己的任务，再由 worker 处理单门店数据；存在性校验与源数据查询都落在 `business_date + storeID` 范围内。
4. **`OrderSaleSummary` 的分组键不能被简化成单一技术主键**：
   当前业务语义下，门店名称变化会产生新的日汇总行，因此 `StoreName` 不是纯展示字段，而是当前统计粒度的一部分。现实现采用 `storeID-storeName` 作为聚合键，显式保留同日改名后的两条结果。
5. **我要把业务语义和技术幂等分开想，不然就会做错**：
   “按门店拆任务、按 `storeID` 校验是否已生成”解决的是计算范围与幂等问题；“汇总时是否合并改名前后的门店名”解决的是统计口径问题。这两个问题不能混成一个答案。

## 最终方案

### 订单汇总金额模型

- `domain/order_sale_summary.go`
- `ent/schema/ordersalesummary.go`
- `repository/order_sale_summary.go`
- `ent/migrate/migrations/20260316201000_order_sale_summary_amount_json.sql`

收敛为三层语义：

- `Amount`：订单整体金额汇总 JSON
- `ThirdPartyAmount`：三方支付总额
- `ThirdPartyPlatform`：第三方平台拆分 JSON（当前包含 GrabFood / ShopeeFood / FoodPanda）

### 商品报表生成链路

- `scheduler/task/product_sale_detail.go`
- `usecase/productsaledetail/product_sale_detail_generate.go`
- `usecase/productsalesummary/product_sale_summary_generate.go`
- `repository/order_product.go`

收敛为：

1. scheduler 先按门店投递任务
2. `ProductSaleDetail` 基于单门店的 `OrderProduct` 快照生成
3. `ProductSaleSummary` 直接聚合上一步得到的 detail slice
4. 汇总 key 覆盖业务要求的多维度组合，税务维度最终按 `TaxName` 区分

### 订单报表生成链路

- `scheduler/task/order_sale_summary.go`
- `usecase/ordersalesummary/order_sale_summary_generate.go`
- `repository/order.go`
- `repository/order_sale_summary.go`

收敛为：

1. scheduler 先按门店投递订单汇总任务
2. usecase 以 `business_date + storeID` 做存在性校验和源数据读取
3. `buildOrderSaleSummaries` 以 `storeID-storeName` 作为聚合键
4. 因此同一门店同一天如果中途改名，会生成两条订单销售汇总，这不是脏数据，而是当前业务口径

## 踩坑与偏差

1. **我上一轮把“避免全店大查询”错误延伸成“汇总必须只按 `StoreID` 合并”**。
   这属于典型的偷换问题：我把执行粒度问题误当成统计口径问题，导致错误地消除了业务上需要保留的名称维度。
2. **`StoreName` 在不同报表里的角色不一样，不能机械套规则**。
   在某些模型里它只是展示冗余；在 `OrderSaleSummary` 当前语义里，它参与分组口径。这个判断必须依赖业务定义，不能靠“字段是否可变”做拍脑袋裁决。
3. **汇总表重复回查源交易表会制造两份真相**。
   `ProductSaleSummary` 如果重新回查 `order_products`，就会和 `ProductSaleDetail` 的映射逻辑漂移，后续修字段时很容易漏一边。
4. **迁移文件和代码不同步时，最容易在中途反复回退**。
   `OrderSaleSummary` 的 JSON 迁移文件曾被撤销过一次，说明“代码改了”不等于“交付完成”，迁移和 hash 也必须纳入交付闭环。
5. **错误复盘必须写明是谁误判了什么**。
   这次最有价值的不是“又改对了”，而是明确记录：我曾把 `StoreID` 当成唯一正确答案，这是错误的；后续不能再把这个错误包装成所谓的最佳实践。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
