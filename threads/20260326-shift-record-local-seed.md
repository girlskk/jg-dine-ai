# Thread: 交班报表本地补 10 条完整样本数据

> 日期: 2026-03-26
> 标签: #shift-record #report #mysql #backend #verification #local-data

## Context

用户要求为交班报表补 10 条完整数据，用于本地联调与展示验证。

当前仓库/环境约束：
- `shift_records` 是快照表，最直接的闭环是向本地 compose MySQL 直接写入样本，而不是反推完整 POS 交班链路。
- POS 服务虽然存在 `api/pos/handler/shift_record.go`，但当前 `api/pos/posfx/posfx.go` 并未注册该 handler，本地 `GET /api/v1/shift-record` 返回 `404 page not found`，不能拿 POS 路由做最终验证。
- backend 已注册交班报表列表接口，可用默认测试账号 `test/123456` 做最终 API 验证。

## 关键决策

1. 直接向本地 `shift_records` 表插入 10 条完整样本，避免为了“造数”去改源码或重走复杂业务链路。
2. 使用固定主键和 `ON DUPLICATE KEY UPDATE`，让造数可重复执行，不因主键或 `(store_id, shift_no, deleted_at)` 唯一键冲突而失败。
3. 样本统一挂到现成本地测试商户/门店：
   - `merchant_id=4a2cf54f-5439-4cd2-8eec-06b09a88412d`
   - `store_id=84099c12-2c6c-4e50-bfb5-ed117b387775`
4. 所有 JSON 字段都填满：`discounts` / `payment_summary` / `cash_summary` / `refund_summary` / `charge_summary`，避免“只有主表字段完整，详情字段还是空壳”的假数据。
5. API 验证切到 backend `/api/v1/shift-record`，并显式带 `store_ids` + 日期区间。

## 最终方案

### 数据准备

- 先核对 live schema：`shift_records` 包含金额字段、计数字段以及 5 个 JSON 字段。
- 复用现有门店与收银员：
  - 门店 `store_name=222`
  - 收银员 `222-admin` / `test1`
- 插入 10 条样本，范围覆盖：
  - `business_date=2026-03-10 ~ 2026-03-19`
  - `shift_no=2026-03-10_1 ~ 2026-03-19_1`
  - `id=70000000-0000-0000-0000-00000000a201 ~ a210`

### 数据特征

- 每条记录都补齐：
  - 开班/交班时间、班次时长
  - 备用金、原价、附加费、营业额、优惠、实收
  - 订单数、收款笔数、退款笔数、退款订单数、退款金额
  - 优惠汇总、支付汇总、现金汇总、退款汇总、挂账汇总
- 金额设计保持基本自洽，例如 `actual_amount` 与 `payment_summary` 汇总一致。

## 验证

### 数据库验证

- 本地 `shift_records` 原有 2 条记录。
- 插入后总数变为 12 条，其中本次固定 ID 命中的样本数为 10 条。
- 抽查结果：
  - `2026-03-10_1` → `actual_amount=510.0000`、`refund_amount=12.0000`
  - `2026-03-19_1` → `actual_amount=800.0000`、`refund_amount=30.0000`

### API 验证

- backend 登录成功：`POST /api/v1/user/login` with `test/123456`
- 列表接口验证成功：
  - `GET /api/v1/shift-record?store_ids=84099c12-2c6c-4e50-bfb5-ed117b387775&start_date=2026-03-10&end_date=2026-03-19&page=1&size=20`
  - 返回 `code=SUCCESS`
  - 返回 `total=10`
  - 返回列表从 `2026-03-19_1` 到 `2026-03-10_1`，正好覆盖本次插入的 10 条样本

## 踩坑与偏差

1. 一开始尝试用 POS 接口验证，但命中 `404`。根因不是数据，而是 `ShiftRecordHandler` 未注册进 `api/pos/posfx/posfx.go`。
2. 终端 heredoc 在工具包装下显示异常，不能凭命令“看起来像执行了”就当成功，必须回查数据库结果。
3. 直接假设表字段名会踩坑，例如 `stores` 表是 `store_name`，不是 `name`；本地造数前先 `DESCRIBE` 才是正路。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md), [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
