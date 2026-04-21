# Thread: 挂账支付/退款下沉为 ChargeAccount Domain Service

> 日期: 2026-03-26
> 标签: #charge #domain-service #pos #refund #datastore #reflect

## Context

用户对前一轮实现提出了更严格的职责要求：

- `CreateChargeRecord` 不应再由 usecase 持有，而应放到 domain，供支付中心等调用方复用
- 调用方不再传 `charge_no`、客户编码、门店名称、收银员名称
- 调用方只传 `charge_customer_id`、`order_no`、`amount`；POS 场景下 `store_id` 与 `cashier_id` 由 token 上下文提供
- `charge_no` 需在方法内部基于门店信息生成
- 收银员合法性要通过 `StoreUser + GetUserRoleInfo/VerifyUserRoleCanLogin + LoginChannelPos` 校验
- 退款不能只改内存对象，必须接 `ctx + ds` 写库，并基于 `order_no` 支持多次退款

这意味着“挂账支付/退款”不再是实体方法或 usecase 编排，而是一个真正依赖 `DataStore` 的 domain service。

## 关键决策

1. 新增 `domain/charg_pay.go`
- 以 `ChargeAccount` 作为领域服务承载支付、退款、查询支付单、查询退款单
- 构造函数改为 `NewChargeAccount(ctx, ds, dailySequence, chargeCustomerID)`
- 虽然用户口头签名未写 `dailySequence`，但现有 `charge_no` 规则依赖 `DailySequence`，不显式注入就无法正确生成编号

2. `CreateChargeRecord` 改为 domain 顶层函数
- `CreateChargeRecord(ctx, ds, dailySequence, params)` 只是 domain 级包装
- 真正逻辑下沉到 `ChargeAccount.Pay`
- usecase 中旧的 `CreateChargeRecord` 删除，避免双轨实现

3. `RefundChargeRecord` 改为写库函数
- `RefundChargeRecord(ctx, ds, params)` 通过 `ChargeAccount.Refund` 执行
- 仓储新增 `FindByOrderNo` 与 `UpdateRefund`
- 退款同时回写 `ChargeRecord` 的退款字段，并扣减 `ChargeCustomer.used_amount`
- 后续已进一步收敛为“退款单号由调用方传入”，退款流程不再依赖 `DailySequence`

4. POS handler 改为只做 API 适配
- 请求参数收敛为 `charge_customer_id / order_no / amount`
- handler 直接使用 token 中的 `store_id / cashier_id`
- 业务补全与权限校验全部交给 domain

## 实现结果

- `domain/charge_record.go`
  - `CreateChargeRecordParams` 改为只保留 ID + 订单号 + 金额
  - `ChargeRecordRepository` 增加 `FindByOrderNo`、`UpdateRefund`
  - `ChargeRecordFilter` 增加 `OrderNo`、`RefundStatus`、`RefundStatuses`
- `domain/charg_pay.go`
  - 新增 `ChargeAccount`
  - 新增 `CreateChargeRecord` / `RefundChargeRecord` 顶层入口
  - `Pay` 内部查询客户、门店、收银员，校验 POS 登录渠道，生成 `charge_no`，创建记录并增加已用额度
  - `Refund` 内部按 `order_no` 查记录，推进退款状态并扣减已用额度；退款单号由调用方透传
- `repository/charge_record.go`
  - 新增按订单号查询与退款字段更新
  - 列表查询支持按订单号和退款状态过滤
- `api/pos/handler/charge_record.go`
  - 删除 handler 内的 `charge_no` 生成逻辑
  - 不再依赖 `ChargeRecordInteractor.CreateChargeRecord`
- `api/pos/types/charge_record.go`
  - 请求结构改为只收必要 ID 与金额
- `domain/charg_pay_test.go`
  - 新增基于 gomock 的 domain service 测试，覆盖支付补全与退款写库

## Verify

- `go test -count=1 ./domain ./usecase/chargerecord ./api/pos/handler ./api/backend/handler` ✅

## 偏差与复盘

1. 上一轮仍把“写库型领域动作”写成了纯实体入口，抽象层级不够彻底
- 这次修正后，domain 明确允许在服务对象中持有 `DataStore` 级依赖

2. `charge_no` 生成无法只依赖 `DataStore`
- 现有编号规则绑定 `DailySequence`
- 因此真正可复用的 domain service 必须显式吃 `DailySequence`，否则只是把编号逻辑藏回调用方

3. 旧测试已经失效
- 原测试保护的是被用户否定的旧 API
- 本次改为 gomock 驱动的 domain service 测试，验证查库补全与写库行为

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
