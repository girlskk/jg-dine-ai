# 快照与持久化时机

> 索引：7 条 pitfall

---

## 报表快照日期持久化与幂等校验

**何时撞见**：报表生成任务重复执行或数据被覆盖。
**为什么**：没有按 `business_date` 做幂等校验；旧逻辑允许先删后插。
**怎么办**：三张报表 repo 增加 `ExistsByBusinessDate`；任务命中已生成日期时直接跳过。报表数据来源必须通过专用 repo 方法（不改旧逻辑）；聚合与映射在 usecase 内存完成。
**历史**：threads/2026-03/20260316-report-daily-scheduler-snapshots.md, threads/2026-03/20260317-report-snapshot-followup-retrospective.md

---

## 任务成功终态字段位置与重试清理

**何时撞见**：任务重试后前端仍显示上次的终态信息（error_message/success_message）。
**为什么**：`success_message` 和 `error_message` 位置不邻近；重试回到 `pending` 时未清理终态字段。
**怎么办**：`success_message` 放在 `error_message` 附近；重试转换到 `pending` 时清空 `error_message/success_message/task_result/completed_at`。`UpdateTaskStatus` 改为按任务类型分支赋值，不走通用参数。
**历史**：threads/2026-03/20260323-task-success-message-propagation.md

---

## 消费记录客户类型快照缺失

**何时撞见**：后台列表显示能按 `customer_type` 过滤，但响应字段为空。
**为什么**：Domain 声明了字段但 schema 缺列；repository 用关联过滤，不提取字段。
**怎么办**：`ChargeRecord` 作为快照表必须冗余存储 `customer_type` 列；写入时从 `ChargeCustomer` 透传；repository 过滤改为直接查表字段而不是关联。迁移时按 `charge_customer_id` 回填；不落库前收紧为 NOT NULL。
**历史**：threads/2026-03/20260331-charge-record-customer-type.md

---

## 订单支付快照聚合时机与过滤边界

**何时撞见**：订单详情缺少部分支付方式（如 account 类支付）或快照只在某些路径被产出。
**为什么**：订单支付快照聚合和 payment_infos 落库用了同一套过滤条件。
**怎么办**：聚合 `simplePayments` 不过滤非落库类型；落库保留现有 `cash/bank_card` 过滤。两条线分离后，快照包含完整来源数据，落库仍保持约束。
**历史**：threads/2026-04/20260417-order-payment-snapshot-source-split.md

---

## 挂账退款状态双字段持久化

**何时撞见**：已退款挂账记录在还款列表中可见或状态混乱。
**为什么**：只有 `refund_status` 字段；全额退款完成时 `status` 没有同步更新。
**怎么办**：全额退款时同时写入 `refund_status=refunded` 和 `status=refunded`；还款创建链路对 `refunded` 记录返回专用错误码；repository `UpdateRefund` 持久化 `status` 字段。
**历史**：threads/2026-04/20260421-charge-record-refunded-status.md

---

## 税费目录固定后快照需补字段

**何时撞见**：税率报表只能按数值 6%/8% 判断，无法按固定税种分类。
**为什么**：订单快照中 `OrderTaxRate` 只保留 tax_rate_id，丢失固定目录代码。
**怎么办**：`OrderTaxRate` 新增 `tax_code_type` 快照字段；报表按 `TaxCodeType` 判断而不是按数值税率比较；品牌创建时初始化四条固定税费并落库。
**历史**：threads/2026-04/20260410-tax-fee-fixed-catalog.md

---

## 导出任务阈值分流下同步结果需落表

**何时撞见**：同步导出完成后任务列表看不到这条记录或 `run_mode` 过滤失真。
**为什么**：同步直出不上报任务记录；`ReportTask` 和 `NewTask` 混用一个方法签名。
**怎么办**：新增 `domain.ReportTask` 单独承担同步上报；同步直出结果也要写成任务记录，`run_mode=sync_direct`；仅 `OrderSaleSummary/ShiftRecord/DineTable` 走阈值分流。
**历史**：threads/2026-03/20260331-report-export-sync-direct-threshold.md
