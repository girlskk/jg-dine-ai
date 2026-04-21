# Thread: 挂账退款拆分为独立流水表并收敛查询职责

> 日期: 2026-03-26
> 标签: #charge #refund #ent #repository #backend #reflect

## Context

上一轮已经把挂账支付/退款下沉为 `ChargeAccount` domain service，但退款仍然只体现在 `charge_records` 聚合字段上。用户继续收紧要求：

- 列表要支持“未全部退款”过滤
- 退款要拆到新的 `charge_refund` 表，保存每次退款流水
- `ChargeAccount` 不再暴露列表查询，而是只保留“按 `order_no` 查单条挂账单”和“按 `refund_no` 查单条退款单”

这意味着当前模型必须从“仅聚合态退款”升级为“聚合态 + 明细流水”双层表达。

## 关键决策

1. 保留 `charge_records` 上的退款聚合字段
- 不删除 `refunded_amount`、`refund_status`、`refunded_at`
- 它们继续承担聚合态职责，支撑列表过滤和剩余可退款金额计算
- 否则后台列表想做“未全部退款”就只能走子查询或实时汇总，复杂度没必要

2. 新增独立 `charge_refunds` 表承载退款流水
- 每次退款创建一条 `ChargeRefund`
- 记录调用方传入的 `refund_no`、`charge_no`、`order_no`、门店信息、退款金额、退款时间，以及所属 `charge_record_id / charge_customer_id`
- `ChargeAccount.Refund` 先更新聚合态，再写退款流水

3. `ChargeAccount` 查询职责收敛为单条查询
- 删除“获取支付记录列表 / 获取退款记录列表”的职责延伸
- 保留 `GetChargeRecord(ctx, orderNo)` 与 `GetChargeRefund(ctx, refundNo)`
- 这样 domain service 边界更清晰，不把后台列表查询混进支付账户服务

4. “未全部退款”过滤直接基于聚合态状态字段
- `ChargeRecordFilter` 增加 `NotFullyRefunded *bool`
- repository 中当该值为 `true` 时使用 `refund_status != refunded`
- 这满足用户诉求，而且与分页/排序查询天然兼容

## 最终方案

- `domain/charge_refund.go`
  - 新增 `ChargeRefund` 实体与 `ChargeRefundRepository`
- `domain/charg_pay.go`
  - `RefundChargeRecord` 改为返回 `*ChargeRefund`
  - `ChargeAccount.Refund` 内同时更新 `ChargeRecord` 聚合退款状态并创建退款流水
  - 查询职责收敛为 `GetChargeRecord` / `GetChargeRefund`
- `ent/schema/chargerefund.go`
  - 新增退款流水 schema
- `repository/charge_refund.go`
  - 新增退款流水仓储实现
- `repository/charge_record.go`
  - 列表过滤新增 `NotFullyRefunded`
- `api/backend/types/charge_record.go`
  - 列表请求新增 `not_fully_refunded`
- `api/backend/handler/charge_record.go`
  - 把 `not_fully_refunded` 透传到 domain filter

## 踩坑与偏差

1. 一开始验证跑了整包 `./repository` 测试
- 结果被仓库中既有失败用例淹没，包括 `Order.relation_type` 和若干 `Exists/ListBySearch` 老问题
- 这些失败和本次退款拆表没有直接关系
- 后续改为“相关包测试 + repository 编译验证”分开跑，避免误判

2. 退款拆表后不能把聚合字段删掉
- 直觉上独立流水表出来后聚合字段看起来重复
- 但用户要的是后台可分页筛“未全部退款”，这一能力更适合依赖聚合态字段而不是实时聚合退款流水

## Verify

- `go test -count=1 ./domain ./usecase/chargerecord ./api/backend/handler ./api/backend/types ./api/pos/handler` ✅
- `go test -count=1 -run '^$' ./repository` ✅
- `go test -count=1 ./repository` ❌
  - 失败点为仓库既有测试基线问题，不是本次退款拆表引入的直接编译或接口错误

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
