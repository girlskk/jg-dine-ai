# Thread: 商品销售 spec_name 空值排查与套餐子项快照兜底

> 日期: 2026-04-13
> 标签: #report #order-upload #snapshot #bugfix #reflect

## Context

用户反馈 `product_sale_details` 与 `product_sale_summaries` 的 `spec_name` 大多数为空，要求只基于订单快照排查，不能回查当前 SKU 主数据。

沿链路复查后，结论需要收窄：

1. `ProductSaleSummary` 只是复用 `ProductSaleDetail.SpecName` 聚合，本身不会独立生成规格名。
2. 普通商品明细直接使用 `order_products.sku.spec_name`，链路本身没有丢字段。
3. 真正会丢值的是套餐子项路径：`buildGroupProductSaleDetail` 之前只读 `groups.details[].spec_name`，不会回退到同一份快照里的 `groups.details[].sku.spec_name`。
4. 上传/存量快照里可能已经有 `groups.details[].sku.spec_name`，但顶层 `groups.details[].spec_name` 为空，于是报表把本来就在快照里的规格名写丢了。

这解释了“订单快照里明明有规格数据，统计表却空”的现象，而且全程不需要碰主数据，也不需要引入 `skus` 旧结构假设。

## 关键决策

1. 删除错误方向上的 `skus` 兼容代码。
   用户已经明确当前问题不是旧 `skus` 列或旧 `skus` JSON 结构，继续保留只会污染判断。
2. 修复点放在“同一份订单快照内的字段兜底”。
   如果套餐子项顶层 `spec_name` 为空，但嵌套 `sku.spec_name` 已有值，就直接回退使用该快照值。
3. 同时在快照读写层做轻量归一化。
   这样上传时漏填的套餐子项顶层 `spec_name` 会被补齐，历史快照读取后也会统一成报表所需结构。

## 最终方案

1. `domain.NormalizeOrderProductSnapshot` 仅保留套餐子项快照内归一化：
   - 补 `groups.details[].skuid`
   - 当 `groups.details[].spec_name` 为空时，用 `groups.details[].sku.spec_name` 回填
2. `repository/order.go` / `repository/order_product.go` 读取订单商品快照后统一执行该归一化。
3. `repository/order_product.go` 写入订单商品快照前也执行该归一化，避免上传方漏顶层字段时把脏结构继续存回去。
4. `usecase/productsaledetail/product_sale_detail_generate.go` 在生成套餐子项报表时显式兜底：
   - 先取 `detail.spec_name`
   - 若为空，再取同一快照里的 `detail.sku.spec_name`

## Verify

已执行：

1. `go test ./repository -run 'TestConvertOrderProductToDomainNormalizesSetMealDetailSpecName|TestNormalizeOrderProductSnapshotFillsSetMealDetailSpecName'`
2. `go test ./usecase/order ./usecase/productsaledetail ./usecase/productsalesummary ./repository -run '^$'`

结果：全部通过。

## Integrate

本次没有新增架构决策，只更新 thread 和索引；同时补一条 repo memory，明确商品销售报表对套餐子项 `spec_name` 的快照回退规则。

## Reflect

1. 这次最大的偏差是过早把问题归因到历史 `skus` 结构，说明在用户已经明确“当前表里有数据”的前提下，继续追历史兼容就是跑偏。
2. 报表字段排查不能只盯顶层 `order_products.sku`。套餐/组合商品经常有独立的子项快照层，真正丢字段的位置往往在那里。
3. 这类问题最稳的修法不是“猜上传方会不会补齐”，而是在读取快照和消费快照两个点都做同源兜底，保证已有快照值不会再次丢失。