# Thread: 订单销售汇总接口 curl 验证

> 日期: 2026-03-20
> 标签: #report #backend #curl #order-sale-summary #mysql #verification

## Context

用户要求为 backend 的 `/data/order-sale-summary` 补测试数据，并用真实 `curl` 验证接口是否正常。

当前仓库存在两个现实约束：
- 该接口读取的是报表快照表 `order_sale_summaries`，不是实时聚合订单明细。
- 当前工作区无法直接重建最新 backend 镜像：`docker compose build builder` 在 Go 编译阶段被 `signal: killed` 终止，同时本地源码还存在与本接口无关的编译问题，无法用当前源码直接起新进程替换现有 backend 容器。

## 关键决策

1. 不反向构造完整订单链路，直接对 `order_sale_summaries` 注入最小合法快照样本，缩短验证闭环。
2. 先对现有 backend 容器做基线 curl 验证，确认认证和接口链路本身正常，再追加 `COPILOT` 样本避免和历史数据混淆。
3. 明确区分“当前运行容器验证成功”和“最新工作区代码已重新构建”这两个结论，避免把旧镜像结果误当成源码联调结果。

## 最终方案

### 数据准备

- 先查询 live MySQL 的 `order_sale_summaries` 表结构和已有样本，确认实际列名为 `tax_6_amount` / `tax_8_amount`，并复用现有 merchant/store：
  - `merchant_id=4a2cf54f-5439-4cd2-8eec-06b09a88412d`
  - `store_id=84099c12-2c6c-4e50-bfb5-ed117b387775`
- 直接插入一条最小测试数据：
  - `id=60000000-0000-0000-0000-00000000a102`
  - `store_name=COPILOT-ORDER-SUMMARY`
  - `business_date=2026-03-19`
  - `order_count=8`
  - `total_diners=14`
  - `cash_amount=88.0000`
  - `third_party_amount=132.0000`

### curl 验证

- backend 登录成功，返回 `SUCCESS` 和 token。
- 基线请求：
  - `GET /api/v1/data/order-sale-summary?business_date_start=2026-03-18&business_date_end=2026-03-18&page=1&size=20`
  - 返回已有快照 1 条，说明现有 backend 容器的接口链路正常。
- 插入样本后再次请求：
  - `GET /api/v1/data/order-sale-summary?business_date_start=2026-03-19&business_date_end=2026-03-19&page=1&size=20`
  - 返回 `COPILOT-ORDER-SUMMARY` 样本 1 条，字段值与插入数据一致：`order_count=8`、`total_diners=14`、`cash_amount=88`、`third_party_amount=132`。

## 踩坑与偏差

1. 代码里的 repository 使用 `tax6_amount` / `tax8_amount`，但 live MySQL 列名是 `tax_6_amount` / `tax_8_amount`；如果不先 `DESCRIBE` 表结构，按代码想当然写 SQL 会直接失败。
2. `docker compose build builder` 在 bundle 编译阶段被 OOM 杀掉，不能指望每次接口联调都先重建整套镜像。
3. 当前工作区还存在与本任务无关的 backend 编译问题，导致无法用本机 `go test ./cmd/backend/...` 或直接 `go run` 来验证最新源码。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
