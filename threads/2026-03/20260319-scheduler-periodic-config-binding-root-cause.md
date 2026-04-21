# Thread: scheduler 启动后续出现 Dapr `127.0.0.1:50001` 超时的首个致命错误

> 日期: 2026-03-19
> 标签: #scheduler #configor #toml #periodic #cron #dapr #docker-compose #runtime

## Context

本地把容器全部 `down` 后重新 `up`，`scheduler` 一开始看起来正常，随后又报：

- `dapr: failed to create client: error creating connection to '127.0.0.1:50001': context deadline exceeded`

如果只盯着这个错误，很容易误判为 Dapr sidecar 启动时序或 compose 编排问题。

这次任务的目标是继续往前追，找到 **第一个让 scheduler 进入不稳定状态的致命错误**，而不是继续修补 `50001` 的表象。

## 关键决策

1. **按时间线找首个 fatal**：不再以最后一次 `50001` 超时为根因，而是回到 scheduler 首次退出前的日志。
2. **验证配置绑定而不是猜 compose**：发现首个 fatal 是 `failed to register periodic task: cron config is required` 后，优先检查 scheduler 配置结构与 `etc/scheduler.toml` 的 section 名是否一致。
3. **直接读依赖源码确认机制**：读取 `configor` 源码，确认嵌套 struct 的字段名会作为递归前缀参与配置映射，因此字段名不匹配会导致对应 section 完全不绑定。

## 最终方案

根因不是 Dapr，而是 **scheduler 配置 struct 字段名和 TOML section 名不一致**。

具体表现：

1. `etc/scheduler.toml` 使用的是 `[ProductSaleDetailTask]`、`[OrderSaleSummaryTask]`、`[StoreRankTask]`
2. `bootstrap/scheduler.go` 之前的字段名却是 `ProductSaleDetail`、`OrderSaleSummary`、`StoreRank`
3. `configor.Load()` 按字段名递归映射，导致这三个 periodic config 没有加载到 `Cron`
4. `bootstrap/asynq.NewScheduler()` 注册 periodic 时，`scheduler/periodic/store_rank.go` 因 `Cron == ""` 返回 `domain.ErrCronConfigRequired`
5. scheduler 因此启动失败并进入 restart loop，随后才出现上一个 thread 记录的 localhost / network namespace 脱节，表现成 `127.0.0.1:50001` 超时

修复方式：

1. 将 `bootstrap/scheduler.go` 中字段名改为和 TOML section 一致：
   - `ProductSaleDetailTask`
   - `OrderSaleSummaryTask`
   - `StoreRankTask`
2. 重新构建本地 bundle 镜像并 recreate `scheduler` / `scheduler-dapr`

## 验证

修复后验证结果：

1. `go test ./bootstrap/...` 通过，说明配置结构变更未破坏 bootstrap 编译
2. `scheduler` 日志中不再出现：
   - `failed to register periodic task: cron config is required`
   - `dapr: failed to create client: error creating connection to '127.0.0.1:50001'`
3. 同一轮启动日志明确出现：
   - `dapr client initializing for: 127.0.0.1:50001`
   - `已注册门店排名构建任务，Cron表达式: 0 5 * * *`
   - `Scheduler starting`
   - `started`
4. 启动后 `StoreRankHandler` 能实际执行并完成一次门店排名构建，说明 scheduler 已进入稳定工作态，而不是刚启动就退出

## 踩坑与偏差

- 只盯 `50001` 会把排查带偏。那是 restart loop 之后的次级症状，不是第一因。
- `docker compose ps` 看见 `scheduler-dapr` 还活着，并不能证明 scheduler 自己的启动链路没问题。
- 这类问题如果不读配置库源码，很容易停留在“可能是映射问题”的猜测层面。

---

> 可复用模式与反思已提取至 [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
