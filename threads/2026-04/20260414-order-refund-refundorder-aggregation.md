# Thread: 订单退款详情改为从 refundorder 聚合

> 日期: 2026-04-14
> 标签: #order #refund #read-model #customer #backend #reflect

## Context

订单领域里一直保留了 `order_refund` 字段，但订单详情/列表/OrderView 的读取链路从未真正回填它。用户要求把 `OrderRefund` 改为从 `refundorder` 读取，并特别指出多门店退款单记录的是主单 `id/order_no`，不是子单。

## 关键决策

1. 退款聚合放在 `usecase/order` 读取层，而不是塞进 `repository/order`。
   原因：`order` 主仓储只负责订单本体，`refundorder` 是另一个聚合来源；跨仓储拼装留在 usecase 更符合仓库分层约束。

2. 退款查询键统一收敛为“根订单 ID”。
   规则：独立单/主单查自身 `order.ID`；子单查 `parent_order_id`。这样单门店和多门店读取逻辑统一，避免子单详情永远查不到主单退款单。

3. `OrderRefund` 只映射完成态退款单，并优先选择最新一条。
   原因：`domain.OrderRefund` 没有 `status` 字段，直接把失败退款单暴露进去会误导前端；多条记录时按 `refunded_at/approved_at/created_at` 选择最新可见记录。

4. `OrderView` 必须显式透传 `OrderRefund`。
   之前即使 `Order` 补齐了退款信息，`toOrderView` 也不会把它拷过去，customer 侧仍然看不到结果。

## 最终方案

- 在 `usecase/order/order.go` 新增 `populateOrderRefund` / `populateOrdersRefunds`，分别覆盖详情和列表读取。
- 新增 `refundLookupOrderID`，用订单关系类型统一决定退款查询键。
- 新增 `buildOrderRefund`，把 `refundorder` 的 `refunded_by/refund_amount/refund_reason/approved_by/approved_at/remark` 映射到 `domain.OrderRefund`。
- 在 `usecase/order/order_view.go` 把 `order.OrderRefund` 透传到 `OrderView.OrderRefund`。
- 更新 `docs/订单详情字段映射.md` 与 `docs/订单schema变更说明.md`，去掉“`order_refund` 未填充/已废弃”的过时描述。

## 踩坑与偏差

- backend `ListOrderReq.OrderStatus` 仍不接受 `refunded`，所以无法直接用 `order_status=refunded` 做列表验收；这不是本次任务范围。
- 本地库没有现成 `refund_orders` 样本，也没有多门店订单样本，无法做现成数据验证。
- customer 游客订单详情接口在本地返回预存的 `500`，因此无法用它完成 `OrderView` 的运行时验收，只能通过代码路径和 backend 详情接口间接确认。
- 为了做真实运行验证，临时向本地 `refund_orders` 插入一条完成态样本，验证 backend `/order/{id}` 已返回 `order_refund` 后立即清理。

## 可复用模式

- 订单相关的跨表读聚合，如果业务实体实际挂在主单上，读取键必须先收敛到“根订单 ID”，不要直接拿当前订单 ID 查。
- `OrderView` 这类二次 DTO 不是自动继承 `Order` 字段；新增/补齐读模型字段时，必须检查 `toXxxView` 之类的转换函数有没有同步透传。
- 当聚合 DTO 缺少状态字段时，读取层宁可只暴露“完成态”记录，也不要把失败/中间态生搬硬套进响应。