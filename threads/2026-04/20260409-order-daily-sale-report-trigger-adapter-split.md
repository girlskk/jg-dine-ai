# Thread: Order Daily Sale Report Trigger Adapter Split

> 日期: 2026-04-09
> 标签: #report #scheduler #adapter #frontend #fx #refactor #reflect

## Context

`frontend` 的订单上传 handler 依赖 `domain.OrderDailySaleReportTrigger`，但具体实现放在 `scheduler/task`，并由 `cmd/frontend` 手工注册。随后用户又指出，eventcore 里订单支付成功事件也必须触发同一套日报重算。

这导致边界有三层混在一起：

1. domain 业务端口：`OrderDailySaleReportTrigger`
2. asynq 生产者实现：enqueue + debounce + TaskID 去重
3. scheduler 消费者实现：任务 handler + 脏检查后重入队

结果是 `frontend` 为了发一个异步日报任务，必须 import 消费者语义很强的 `scheduler/task` 包；同时 handler 还直接依赖具体 trigger struct，重入队逻辑也被绑死在实现上。

用户要求把边界收干净，并且明确提出两个约束：

- 不要把这类业务实现塞进 `bootstrap` 这种偏基础设施装配目录。
- 要考虑 scheduler 消费后脏检查命中时仍然需要重新入队。
- eventcore 的 `order.paid` 成功事件，也要触发同一个日报重算入口。

## 关键决策

1. 保留 `domain.OrderDailySaleReportTrigger`，不把它替换成公开的通用 `DelayQueue`。
原因：`taskType`、payload、delay、TaskID 都是基础设施语言，不该上推到 domain/usecase。对外应该保留“触发当天报表重算”这个业务动作。

2. 具体 trigger 实现在 `adapter` 层，而不是 `bootstrap` 或 `scheduler/task`。
原因：它是典型的 domain 出站端口实现，语义上和 `Publisher`、`Storage`、`RMClientProvider` 一样，应该通过 `adapterfx` 统一注入。

3. 单独拆出 `scheduler/taskcontract` 承载任务契约。
原因：如果只把 trigger 挪到 adapter，但仍让 adapter 反向 import 整个 handler 包去拿 task type 和 payload，那只是把耦合藏起来，没有真正解开。task contract 需要和 handler 分离。

4. `OrderDailySaleReportHandler` 依赖 `domain.OrderDailySaleReportTrigger`，而不是具体 struct。
原因：scheduler 的脏检查重入队仍然是业务语义触发，不该绑死具体 asynq producer 实现。

5. `scheduler/queue.go` 保留在 `scheduler`，不下沉到 `bootstrap`。
原因：队列名是 scheduler 任务体系的共享契约，既被 server 配置使用，也被 producer/handler 使用；`bootstrap` 只是其中一个使用方，不应该拥有这组语义。

6. eventcore 的补点放在 `order.paid` handler，而不是 `payment.notify` 或通用 `OrderInteractor` 构造函数。
原因：`payment.notify` 只是原始支付通知，`HandleOrderPayment` 成功后才会发出真正的“订单已支付完成”事件。把 trigger 接在 `order.paid` 上，语义更准；同时避免把 trigger 依赖推到全局 usecase 构造函数扩大依赖面。

## 最终方案

核心变更：

- `scheduler/taskcontract/order_daily_sale_report.go`
  - 新增 `TaskTypeOrderDailySaleReport`、`OrderDailySaleReportDelay`、payload、task builder、TaskID helper、payload parser。

- `adapter/tasktrigger/order_daily_sale_report.go`
  - 新增 `OrderDailySaleReportTrigger` 的 asynq adapter 实现。
  - 统一封装 enqueue、queue、TaskID 去重和 debounce 延迟。

- `adapter/adapterfx/adapterfx.go`
  - 通过 `adapterfx` 注册 `domain.OrderDailySaleReportTrigger` 的 adapter 实现。

- `scheduler/task/order_daily_sale_report.go`
  - 删除 trigger concrete implementation。
  - handler 改依赖 `domain.OrderDailySaleReportTrigger`。
  - 改为使用 `taskcontract` 的任务契约。

- `cmd/frontend/main.go`
  - 删除 frontend 入口对 `task.NewOrderDailySaleReportTrigger` 的手工注入。

- `scheduler/schedulerfx/schedulerfx.go`
  - 删除 scheduler 模块对 trigger concrete implementation 的注册。

- `api/eventcore/handler/order.go`
  - 在 `order.paid` 事件处理时，直接使用事件携带的订单快照触发同一个 `OrderDailySaleReportTrigger`。
  - 只在订单快照存在且 `StoreID + BusinessDate` 齐全时触发。

- `cmd/eventcore/main.go`
  - 新增 `asynqfx.ClientModule`，为 eventcore 中的 adapter trigger 提供 asynq client。

## 踩坑与偏差

1. 首轮方案曾考虑把 trigger 落在 `bootstrap/asynq`。
这个方向不够准。`bootstrap` 更适合通用基础设施装配，不适合承载业务型 domain 端口实现。用户指出后，最终修正为 `adapter`。

2. 用户提出“是否抽象成一个延时队列接口”。
这个想法如果作为 adapter 内部 helper 可以接受，但如果上升为 domain 公开接口，会把基础设施细节上推，破坏原本的业务抽象，因此没有采纳为最终端口设计。

3. dirty-check 重入队一度容易被误解成“因此必须依赖具体 trigger struct”。
实际相反：正因为 frontend 和 scheduler handler 都要触发同一个动作，所以更应该依赖 `domain.OrderDailySaleReportTrigger`，共享同一套 enqueue 规则。

4. eventcore 补点时，起初容易把触发点挂在 `payment.notify`，但那只是支付通知，不是订单完成语义。
最终改为挂在 `order.paid`，复用 `HandleOrderPayment` 发出的完成态事件；同时局部给 eventcore 补 asynq client，而不把依赖推进全局 usecase 构造函数。

## Verify

已执行：

- `gofmt -w adapter/adapterfx/adapterfx.go adapter/tasktrigger/order_daily_sale_report.go api/eventcore/handler/order.go api/eventcore/handler/payment.go cmd/eventcore/main.go cmd/frontend/main.go scheduler/schedulerfx/schedulerfx.go scheduler/task/order_daily_sale_report.go scheduler/taskcontract/order_daily_sale_report.go`
- `go test ./adapter/... ./api/frontend/... ./api/eventcore/... ./scheduler/... ./cmd/frontend ./cmd/scheduler ./cmd/eventcore`

结果：全部通过。

## 可复用模式

- domain trigger 保持业务语义，不要被“通用队列接口”稀释成基础设施原语。
- 出站 trigger 的具体实现优先放 `adapter`，由 `adapterfx` 统一注入。
- scheduler 相关任务如果同时被 producer 和 consumer 共享，先拆 task contract，再拆 producer/handler；不要让 adapter 反向依赖整个 handler 包。
- queue 名称属于 scheduler 共享契约，留在 `scheduler` 比留在 `bootstrap` 更干净。
- 类似 eventcore 这种事件链路补点，优先挂在语义最终成立的事件上，例如 `order.paid`，不要过早挂在原始支付通知上。
- 单入口补点优先在入口 handler 收敛依赖，不要为了一个入口把通用 usecase 构造函数强行改成全局都要承担的新依赖。