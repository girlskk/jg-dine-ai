# Thread: 挂账消费记录支付/退款领域入口收敛

> 日期: 2026-03-25
> 标签: #charge #domain #refund #usecase #reflect

## Context

挂账消费记录原本只有“还款状态”，没有表达挂账支付后的退款语义。需求要求：
- domain 提供挂账支付与挂账退款两个入口
- 支持按订单号多次退款，直到剩余可退款金额为 0
- 增加未退款 / 部分退款 / 已退款三态

第一版实现把 `Pay` 和 `Refund` 写成了 `ChargeRecord` 实例方法，但这会把“创建并初始化挂账支付记录”的责任推回调用方，导致 usecase 仍然要先手拼 `ChargeRecord`，领域入口名存实亡。

## 关键决策

1. 退款状态与还款状态拆开建模
- `status` 继续表示挂账记录是否已还款（unpaid/paid）
- 新增 `refund_status`、`refunded_amount`、`refunded_at` 表示支付后的退款进度
- 避免把“还款”和“退款”揉进一个字段造成状态语义污染

2. 支付入口改为函数式创建
- 新增 `PayChargeRecord(params *ChargeRecordPayParams) (*ChargeRecord, error)`
- 由 domain 负责返回初始化完成的 `ChargeRecord`
- usecase 只负责准备业务上下文，不再手动初始化退款相关默认值

3. 退款入口改为独立领域函数
- 新增 `RefundChargeRecord(record *ChargeRecord, amount decimal.Decimal, refundedAt time.Time) error`
- 允许对同一条记录多次退款
- 通过 `RefundableAmount()` 控制累计退款上限

## 实现结果

- `domain/charge_record.go`
  - 新增 `ChargeRecordPayParams`
  - 新增 `PayChargeRecord`
  - 新增 `RefundChargeRecord`
  - 新增 `ChargeRefundStatus`
  - 新增 `refunded_amount` / `refund_status` / `refunded_at`
- `usecase/chargerecord/charge_record_create.go`
  - 创建挂账记录改为调用 `domain.PayChargeRecord`
- `domain/charge_record_test.go`
  - 增加支付初始化、部分退款、全额退款、非法退款金额测试

## Verify

- `go test -count=1 ./domain ./usecase/chargerecord` ✅

## 偏差与复盘

1. 第一版把支付入口写成实例方法，是错误抽象
- 如果调用方还要先 `&ChargeRecord{...}`，那 domain 根本没有接管“创建支付记录”这件事
- 这类入口必须让 domain 直接产出实体或完成完整状态迁移

2. ent 生成链存在仓库级噪音
- 本次 schema 变更会牵动 ent 生成文件，但仓库当前 `go generate ./ent` 因缺失 `ent/intercept` 包无法稳定走 canonical 生成链
- 这不是本次业务改动的根因，因此验证先收敛到 domain 与直接 usecase

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
