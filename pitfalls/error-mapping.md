# HTTP 状态码与错误透传

> 索引：3 条 pitfall

---

## 操作日志缺记业务失败的错误码与文案

**何时撞见**：操作日志表中 `code` 和 `message` 为空；接口响应明确包含业务错误。
**为什么**：`OperateLogger` 在 `ErrorHandling` 内层；`c.Next()` 返回时错误响应还未写入缓冲区；中间件只兜底了 5xx 场景。
**怎么办**：从 `gin.Errors` 的 `errorx.Error` 做非 5xx 兜底；对 HTTP 状态码 < 500 的业务失败，直接读取 `Code` 和 `Message`；若 `Message` 仍是占位符则按当前 locale 翻译一次。存在任何错误都标记 `success=false`。
**历史**：threads/2026-03/20260330-operate-log-error-code-message-fallback.md

---

## 按模块审计 REST 状态码映射不一致

**何时撞见**：同模块在 backend/store/customer 端返回的错误码不一致；某些接口返回 400 而应返回 404。
**为什么**：各服务 handler 各自维护 `checkErr`；没有按模块统一审计映射规则。
**怎么办**：按模块（不按服务）梳理所有 handler；资源不存在统一 404；唯一性冲突用 409；权限/状态阻断用 403；参数非法用 400。login 错误单独处理：认证失败 401，账号状态阻断 403。抽到 domain `CheckXxxErr` helper 复用。
**历史**：threads/2026-04/20260413-owned-modules-rest-http-status-audit.md

---

## POS 挂账创建错误映射遗漏深层链路

**何时撞见**：POS 挂账创建返回 500；实际调用链经过角色校验但 handler 没映射这些错误。
**为什么**：`CreateChargeRecord` 内部走 `VerifyUserRoleCanLogin`；可能返回 `ErrUserRoleNotExists`、`ErrRoleDisabled`、`ErrLoginChannelNotAllowed`；handler 的 `checkErr` 只覆盖浅层。
**怎么办**：沿全调用链梳理所有可能的业务错误；POS handler 补齐对角色校验错误的映射（都返回 403）。只要链路里走 `VerifyUserRoleCanLogin` 或 `UserRoleRepo.FindOneByUser`，就要把这类错误视为实际错误面。
**历史**：threads/2026-04/20260413-pos-charge-record-create-error-mapping.md
