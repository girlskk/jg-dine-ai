# Thread: 操作日志异步写库被请求上下文取消

> 日期: 2026-03-30
> 标签: #operate-log #middleware #backend #async #context #debugging #reflect

## Context

用户反馈操作日志“没有记录到数据”。本地 backend 已接入操作日志中间件和列表接口，但实际写操作后列表始终为空，需要确认是路由未命中、落库失败，还是查询链路有问题。

## 关键决策

1. 先做运行态复现，不先改代码。
   - 用 backend 登录 -> 调用写接口 -> 查询操作日志列表。
   - 结果显示列表为空，排除了“只是前端展示问题”的侥幸判断。
2. 直接查 backend 日志定位异步写库报错。
   - 日志明确报 `failed to create operate log: context canceled`。
   - 根因不是 repository/SQL，而是中间件异步 goroutine 复用了请求上下文，请求返回后 ctx 被取消。
3. 在共享中间件里修，而不是在 backend/store 分支各修一份。
   - 根因位于 `pkg/ugin/middleware/operate_logger.go`，backend/store 都共用这段逻辑。
4. 保留异步写库，但把上下文从请求取消链剥离。
   - 使用 `context.WithoutCancel(c.Request.Context())` 保留上下文 values/logging，同时避免请求结束后 DB 写入被取消。
5. 补回归测试锁死这个根因。
   - 测试里主动取消 request context，验证 `Create` 收到的 ctx 不会变成 canceled。

## 最终方案

- 修改 `pkg/ugin/middleware/operate_logger.go`
  - 异步写库前先基于请求上下文创建 `WithoutCancel` 上下文。
  - goroutine 不再直接闭包读取 `gin.Context`，只接收预先构造好的 `ctx` 和 `log`。
- 新增 `pkg/ugin/middleware/operate_logger_test.go`
  - 构造最小 Gin 路由，手动取消 request ctx，验证异步 `Create` 不会拿到 canceled ctx。

## 踩坑与偏差

1. 第一层根因修完后，接口“立刻查询”仍然可能返回 0。
   - 直接查库可见记录已写入；等待约 2 秒后再查列表即可看到数据。
   - 这是异步写入带来的最终一致性窗口，不是再次落库失败。
2. `docker compose up -d backend` 被 `eventcore` 健康依赖卡住，不能据此误判 backend 修复失败。
   - 最后通过直接启动已有 backend 容器完成验证。

---

> 可复用模式与反思已提取至 [knowledge/operate-log.md](../knowledge/operate-log.md)，按需查阅。
