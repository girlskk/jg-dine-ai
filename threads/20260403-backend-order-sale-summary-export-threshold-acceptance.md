# Thread: order sale summary 导出阈值验收补齐

> 日期: 2026-04-03
> 标签: #backend #acceptance #order-sale-summary #export #threshold #reflect

## Context

在 backend 相关 export 已接入 acceptance 之后，用户继续收窄要求：`/data/order-sale-summary/export` 不能只验证“接口能调通”，还必须显式验证 300 条阈值分流。

最终要验证的是两条行为边界：

1. `300` 条及以内，必须走 `sync_direct`
2. `300` 条以上，必须走 `async_center`

同时用户明确要求补一组 `500` 条数据来覆盖异步分支。

## 关键决策

1. 不新建独立 threshold 脚本，继续把阈值验收内嵌在 `.github/acceptance/backend/order_sale_summary.sh`，保持“资源脚本自带关联 export 验收”的边界一致。
2. 不复用现有 2026 年报表样本，也不去碰真实业务门店数据；改为使用隔离的 synthetic `store_id` 和未来日期窗口，避免把阈值测试变成脆弱的状态耦合。
3. 先直接往 `order_sale_summaries` 快照表写数据，再调用 export 接口断言 `run_mode`。这是因为该导出阈值判断本来就是通过 repository 的 `CountOrderSaleSummaries(...)` 对快照表计数，不需要绕订单主链路造 500 单业务数据。
4. 样本必须在脚本退出时清理，否则下次跑同一个日期窗口会把 300/500 条边界变成脏数据累加，测试就失去意义。

## 最终方案

在 `.github/acceptance/backend/order_sale_summary.sh` 中新增：

- MySQL helper：直接通过 local compose 的 mysql 容器执行 SQL
- merchant_id lookup：根据 backend 登录用户 ID 从 `backend_users` 反查 merchant_id
- seed / cleanup：
  - sync 样本：隔离 `store_id` + `2090` 年窗口，插入 `300` 条
  - async 样本：隔离 `store_id` + `2091-2092` 年窗口，插入 `500` 条
- seed count assert：插入后先确认 DB 中确实是 `300` / `500` 条
- export assert：
  - `300` 条窗口断言 `run_mode=sync_direct`，并要求返回 `export_file.key`
  - `500` 条窗口断言 `run_mode=async_center`，并要求 `export_file.key` 为空

## Verify

已完成：

- `bash -n .github/acceptance/backend/order_sale_summary.sh`
- `bash .github/acceptance/backend/order_sale_summary.sh`
- `bash .github/acceptance/backend/modules/report.sh`

关键结果：

- `order_sale_summary.sh`
  - merchant lookup 成功命中 backend 测试商户 `4a2cf54f-5439-4cd2-8eec-06b09a88412d`
  - sync seed count = `300`
  - async seed count = `500`
  - `2090` 窗口 export 返回 `sync_direct`
  - `2091-2092` 窗口 export 返回 `async_center`
- `report` 模块总报告：脚本 `5/5` 成功，HTTP `27/27` 为 `200`，`SKIP=0`

## 踩坑与偏差

1. 如果继续拿现有 2026 报表样本做阈值测试，就无法稳定控制 count，最后测到的只会是“当前环境碰巧是多少条”，不是阈值边界。
2. 如果 seed 不清理，300/500 这种边界测试只要多跑一次就会失真。这个问题不是偶发，而是必然累计。
3. `order_sale_summaries` 在 ent schema 里只有普通索引，没有 `(merchant_id, store_id, business_date)` 唯一约束，因此 acceptance 可以安全使用隔离 store/date 窗口造样本，但也意味着清理动作不能省略。

## 可复用模式

- 报表导出阈值验收要测的是 repository count 边界，不是订单链路本身；优先直写快照表，缩短验证闭环。
- 只要是 count-based 阈值测试，就必须自己控制样本窗口和 cleanup，不能依赖共享测试库里“刚好够多/够少”的历史数据。