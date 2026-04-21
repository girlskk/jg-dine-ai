# 挂账模块知识

> 来源 threads: charge-module, charge-module-repayment-hardening, charge-flow-e2e-pos-di-fix, chargerecord-err-naming, pos-charge-feedback-refactor, pos-charge-record-settlement, charge-record-pay-refund-domain-entrypoints, charge-account-domain-service-refactor, charge-refund-split-table-and-filter, charge-record-customer-type

## 核心模型

- 四核心表：`ChargeCustomer`（挂账客户）、`ChargeRecord`（消费记录）、`ChargeRepayment`（还款单）、`ChargeRefund`（退款流水）
- 门店适用范围用枚举 `accept_store_type`（all/partial），配合 JSON 列 `accept_store_ids`。不用布尔，为未来扩展"排除指定门店"预留空间
- 消费记录冗余门店名称 `store_name`，不关联 store edge。列表不 JOIN store 表
- 消费记录包含 `customer_type` 快照字段，冗余进 `charge_records`，不依赖运行时 join
- 消费记录只有 Repo 接口，无独立写入用例。记录创建发生在挂账支付流程中

## 退款建模

- 退款拆为聚合态 + 明细流水双层表达：
  - `charge_records` 保留 `refunded_amount`/`refund_status`/`refunded_at` 聚合字段（支持列表过滤"未全部退款"）
  - `charge_refunds` 表保存每次退款流水
- 退款状态与还款状态拆开建模：`status` 表示是否已还款（unpaid/paid），`refund_status` 表示支付后退款进度（未退款/部分退款/已退款）
- `ChargeRecordFilter` 增加 `NotFullyRefunded *bool`，repository 中 `refund_status != refunded`

## Domain Service（ChargeAccount）

- `ChargeAccount` 是 domain service，持有 `DataStore`、`DailySequence`，负责支付、退款、单条查询
- `CreateChargeRecord(ctx, ds, dailySequence, params)`：domain 顶层入口。内部查询客户、门店、收银员，校验 POS 登录渠道，生成 `charge_no`，创建记录并增加已用额度
- `RefundChargeRecord(ctx, ds, params)`：按 `order_no` 查记录，推进退款状态并扣减已用额度。退款同时更新聚合态并写退款流水
- POS handler 只传 `charge_customer_id / order_no / amount`，`store_id / cashier_id` 由 token 上下文提供
- 查询职责限制在单条查询（`GetChargeRecord(ctx, orderNo)` / `GetChargeRefund(ctx, refundNo)`）。后台列表、分页、筛选属于独立读模型

## 门店筛选

- `buildFilterQuery` 中 `store_id` 条件固定采用 `accept_store_type = all OR accept_store_ids contains store_id`

## 还款流程

- 创建还款单 → 校验客户存在 → 查询消费记录 → 校验全部未还款且属于该客户 → 计算总额 → `receivedAmount = totalCharge - discount` → 事务内创建还款单 + 批量更新记录状态 + 扣减已用额度

## 编号规则

- `customer_code`：`{品牌编号后4位}{yymmdd}{0001递增}`，IncrSequence
- `charge_no`：`{门店编号后8位}{yymmdd}{0001每日递增}`，DailySequence，key 用 `seq:charge_no`
- `repayment_no`：`{customerCode}{0001每日递增}`，DailySequence

## 踩坑

- `ChargeRecord.charge_repayment_id` 从 nillable 改为 optional 后，关联类型需同步切换值语义
- 首版 `chargeoperation` 独立模块被回收。应优先扩展现有 interactor/repo 接口
- ent schema 仅改动单实体时，生成后需检查并收敛 diff
- POS `DailySequence` 注入缺失导致启动失败：新增带编号生成的 handler 后，必须同步注册序列依赖
