# HTTP 状态码与错误透传

> 索引：2 条 pitfall

---

## 操作日志从 gin.Errors 兜底业务失败

**何时撞见**：接口响应已有业务错误，但操作日志里的 `code/message/success` 与响应不一致。
**为什么**：操作日志中间件回看响应体不稳定；错误响应可能还没写入缓冲区，但 `gin.Errors` 已携带 `errorx.Error`。
**怎么办**：业务失败优先从 `gin.Errors` 取 `errorx.Error`；HTTP 状态码 < 500 时也要记录业务 `Code/Message` 并标记失败。`Message` 仍是占位符时按当前 locale 翻译一次。

---

## REST 错误映射按模块和完整调用链审计

**何时撞见**：同一 domain 在 backend/store/customer/POS 的 HTTP 状态码不一致，或 usecase 深层业务错误冒成 500。
**为什么**：handler 各自维护 `checkErr`；只看入口函数显式返回，容易漏掉内部调用链里的角色、权限、状态类错误。
**怎么办**：按 domain 模块审计所有端的 handler；沿完整 usecase 调用链列出业务错误。资源不存在 404，唯一性/状态冲突 409，权限/状态阻断 403，参数非法 400；重复逻辑抽到 domain `CheckXxxErr` helper。
