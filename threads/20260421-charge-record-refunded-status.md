# Thread: Charge Record Refunded Status

> 日期: 2026-04-21
> 标签: #charge #refund #status #backend #reflect

## Context

用户要求给 `ChargeRecordStatus` 增加“已退款”枚举，用来标识已退款的挂账消费记录。仓库原本把“是否还款”与“退款进度”拆成 `status` 和 `refund_status` 两个字段；如果只扩枚举定义，不同步退款落库和还款校验，新值会变成死枚举，业务语义也会继续错位。

## 关键决策

1. 保留 `refund_status` 作为退款进度字段，同时仅在**全额退款完成**时把 `status` 置为 `refunded`。
2. 将 `ChargeRecordRepo.UpdateRefund` 一并更新 `status`，避免 domain 已变更但仓储没有持久化。
3. 还款创建链路显式区分 `paid` 和 `refunded`，对已退款记录返回专用业务错误和错误码，而不是继续误报“已还款”。
4. 验证层采用两段式：先跑常规 `go test` 观察基线，再用 `go test -run '^$' ...` 做 compile-only，避开仓库中与本次无关的已有 repository 红测。

## 最终方案

- `domain/charge_record.go` 新增 `ChargeRecordStatusRefunded`，补齐注释、`Values()` 和 `CanRefund()` 防御。
- `domain/charg_pay.go` 在退款累计金额等于原挂账金额时，同时写入 `refund_status=refunded` 和 `status=refunded`。
- `repository/charge_record.go` 的 `UpdateRefund` 改为持久化 `status`。
- `usecase/chargerepayment/charge_repayment_create.go` 对 `refunded` 记录返回 `ErrChargeRecordAlreadyRefunded`。
- `api/backend/handler/charge_repayment.go` 与 `pkg/errorx/errcode/error_code.go` 补齐已退款冲突映射。
- 重新生成 ent 和 backend swagger，使枚举校验与接口文档跟上新状态值。

## 踩坑与偏差

- 第一次补丁时把 `chargerepayment` 的上下文写错，导致 `apply_patch` 未命中，需要按当前文件内容重新落补丁。
- 本地 `swag` 版本会同时重写很多 `x-enum-descriptions` 元数据，导致 backend docs diff 范围明显大于本次语义改动。
- 常规 `go test ./domain ./repository ./usecase/chargerepayment ./api/backend/... ./ent/...` 命中了仓库里既有的 repository 测试失败，与本次改动无直接关系，因此追加 compile-only 验证确认改动本身可编译。

## 可复用模式

- 给 ent enum 扩值时，不能只改 domain 常量；必须一并检查写路径、读模型过滤、业务校验、handler 错误映射和生成代码。
- 当仓库存在已知红测时，可以先保留失败事实，再用 `go test -run '^$' ...` 对受影响包做 compile-only 验证，隔离本次改动的信号。