# 20260416-order-refund-batch-payment-delete

## Context

- POS 订单重传和退款单重传都会走 Upload 路径覆盖支付快照。
- 旧实现对 Cash 和 BankCard 各执行一次删除，产生两次 SQL，重复工作明显。
- 当前 repository 接口只支持单个 `paymentType`，导致 usecase 只能重复调用。

## Constraints

- 保持现有分层：批量删除能力下沉到 repository，usecase 只负责编排。
- 不改 API 契约，不引入 migration。
- order 和 refund 两条 Upload 路径都要一起收口，不能只修一边。

## Expected Output

- payment/refund repository 提供按多个 `paymentType` 一次删除的能力。
- `usecase/order.Upload` 与 `usecase/refundorder.Upload` 改为单次批量删除 Cash + BankCard。
- 已无调用的旧单条删除接口一并移除，避免接口面继续膨胀。

## Plan

1. 扩展 `domain.PaymentRepository` / `domain.RefundRepository` 接口，新增批量删除方法。
2. 在 `repository/payment.go` 和 `repository/refund.go` 用 `PaymentTypeIn(...)` 实现一次删除。
3. 修改 order/refund Upload 调用点为批量删除。
4. 更新 gomock。
5. 做最小编译验证。

## Solve

- 新增 `DeletePaymentRecordsByOrderIDAndTypes` 与 `DeleteRefundsByOrderIDAndTypes`。
- repository 删除条件从单个 `PaymentTypeEQ(...)` 改为 `PaymentTypeIn(...)`。
- order/refund Upload 使用同一组 `[]domain.PaymentMethodPayType{Cash, BankCard}` 一次删除旧快照。
- 更新 `domain/mock` 中对应仓储 mock 方法。
- 根据用户二次反馈，确认旧单条删除方法已无调用后，删除接口声明、实现与 mock。

## Verify

### ✅ 编译验证

执行：

```bash
gofmt -w repository/payment.go repository/refund.go
go test ./usecase/order ./usecase/refundorder ./repository ./domain ./domain/mock -run '^$'
```

结果：相关包纯编译通过。

### ℹ️ 额外观察

- 先前尝试直接跑 `go test ./repository` 时，存在与本次修改无关的既有失败项（如 `dine_table_test`、`payment_test`、`product_spec_test` 等），因此本次验证收敛为相关包纯编译。
- 未运行 acceptance：本次未改 handler/API 契约，不属于已有验收脚本覆盖边界。

## Integrate

- 已更新 thread 索引：`threads/_index.md`。
- 本线程记录了“支付/退款快照覆盖时，批量删 payment type 应下沉到 repository”的实现模式，供后续同类优化复用。

## Reflect

- 偏差：第一版为了保守保留了旧单条接口，这属于不必要的兼容心态。既然调用面已经清零，继续保留就是制造维护噪音。
- 正解：把能力边界放回 repository，用 `IN` 条件一次删除，多处调用共享同一能力。
- 后续若再增加其他可覆盖的支付方式，不应该继续在 usecase 叠加删除调用，而应直接扩充传入的 `paymentTypes` 切片。