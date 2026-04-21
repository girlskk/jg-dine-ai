# 异步与 context

> 索引：2 条 pitfall

---

## 异步操作日志写库被请求上下文取消

**何时撞见**：操作日志列表为空；实际没有数据库错误。
**为什么**：中间件异步 goroutine 闭包复用请求 context；请求返回后 ctx 被取消。
**怎么办**：异步写库前调用 `context.WithoutCancel(c.Request.Context())` 剥离取消链；保留上下文 values/logging。goroutine 不直接闭包 `gin.Context`，只接收预先构造的 `ctx` 参数。
**历史**：threads/2026-03/20260330-operate-log-async-context-cancel.md

---

## 导出任务链路需显式恢复请求语言环境

**何时撞见**：异步导出任务表头输出错误语言或只有 message ID。
**为什么**：taskcenter 回调时没有恢复前端传入的 `locale`；bundle 未初始化或 context 为空。
**怎么办**：导出 payload 内嵌 `locale` 和 `file_name`；taskcenter 接收时通过 `i18n.WithLocalizer` 按 locale 恢复语言环境。taskcenter 启动 wiring 补齐 `i18nfx.Module`，确保进程级 bundle 可用。
**历史**：threads/2026-03/20260325-product-sale-export-runtime-i18n-download-fix.md
