# Thread: POS 订单支付快照必须直接来自 upload payload

> 日期: 2026-04-17
> 标签: #order #payment #snapshot #frontend #reflect

## Context

用户提供了一组 POS `order/upload` 的请求体、返回体和数据库现状：请求里 `payments` 含一条 `payment_method=account` 的完成态支付，但返回里的 `simple_payments` 为 `null`，数据库 `orders.order_payments` 也为空。这说明不是详情读取把快照弄丢了，而是 upload 入口一开始就没把这类支付聚合进订单快照。

## 关键决策

1. 把“订单支付快照聚合”和“payment_infos 落库”拆成两条线。
	原因：POS 详情页依赖的是订单主表快照，不是 payment 表回推；即便某些支付方式当前不进 `payment_infos`，也不能在快照阶段被过滤掉。

2. 保持 `payment_infos` 的现有过滤边界不扩张。
	原因：用户刚明确说明不要为未证实场景扩张类型边界；同理，这里先只修“快照丢失”，不顺手扩大 payment record 的持久化范围。

## 最终方案

- 在 `api/frontend/handler/order.go` 中，先对所有上传 `payments` 聚合 `simplePayments` / `OrderPayments`，不再把 `account` 之类的非落库类型在快照阶段直接 `continue` 掉。
- `payments` 切片的落库构造仍保留当前 `cash` / `bank_card` 过滤规则，避免把未评估的支付类型直接写进 `payment_infos`。
- 最终 `domain.Order` 在 upload 成功响应和后续详情读取时，都能保留来自 POS payload 的 `simple_payments` 快照。

## 踩坑与偏差

- 这条问题很容易被误判成“详情接口没查对”或“repository 没回填”，但用户给的 upload 请求/响应对照已经说明快照在入口处就被过滤掉了。
- 本地运行态验证仍被环境阻塞：当前 compose 缺可用 `dine-bundle` 镜像，而 builder 重建又会 OOM，所以本次只能做代码级编译验证。

## 可复用模式

- 当某个读模型字段的 source of truth 明确来自上传 payload 时，先检查入口聚合有没有把数据过滤掉，再去追读取链路。
- “快照聚合”和“明细流水落库”不要共用同一层过滤条件；前者面向读模型完整性，后者面向持久化边界，两者不是一回事。
