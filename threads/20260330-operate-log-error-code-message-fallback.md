# Thread: 操作日志补记业务失败的 code/message

> 日期: 2026-03-30
> 标签: #operate-log #middleware #backend #store #bugfix #reflect

## Context

用户反馈操作日志在失败场景下会漏记 `code` 和 `message`。这些字段在接口响应里本来有值，尤其是非 5xx 的业务失败，但日志表里为空，导致审计信息不完整。

## 关键决策

1. 不改 middleware 链顺序，先修共享中间件的取值时机问题。
   - `OperateLogger` 位于 `ErrorHandling` 内层，`c.Next()` 返回时统一错误响应还没由 `ErrorHandling` 写回客户端。
   - 因此不能只依赖响应体缓冲区提取 `code/message`。
2. 从 `gin.Errors` 的 `errorx.Error` 做非 5xx 兜底。
   - 对业务失败，直接读取 `Code` 和 `Message`。
   - 若 `Message` 仍是错误码占位，则在中间件内按当前请求上下文做一次 i18n 翻译，尽量贴近最终响应。
3. 同步修正 `Success` 判定。
   - 只要 `gin.Errors` 有错误，就不能继续按当前 writer status 的默认 `200` 误判成功。

## 最终方案

- 修改 `pkg/ugin/middleware/operate_logger.go`
  - 保留原有成功响应 JSON 解析。
  - 新增 `gin.Errors` 兜底逻辑：对 `errorx.Error` 且 HTTP 状态码 `< 500` 的场景，补记 `code/message`。
  - 只要存在 `gin.Errors`，统一将 `success=false`。
- 修改 `pkg/ugin/middleware/operate_logger_test.go`
  - 在现有 detached context 回归测试基础上，新增“业务失败时记录 code/message”测试。

## Verify

- `go test` 定向测试通过：`pkg/ugin/middleware/operate_logger_test.go`

---

> 可复用模式与反思已提取至 [knowledge/operate-log.md](../knowledge/operate-log.md)，按需查阅。
