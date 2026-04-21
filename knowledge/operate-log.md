# 操作日志知识

> 来源 threads: operate-log-module, operate-log-async-context-cancel, operate-log-error-code-message-fallback

## 架构

- 三层中间件设计：
  - `pkg/ugin/middleware/operate_logger.go`（核心共享逻辑）
  - `api/backend/middleware/operate_logger.go`（backend 用户提取器）
  - `api/store/middleware/operate_logger.go`（store 用户提取器）
- 声明式路由注册：handler 实现 `OperateLogs() []OperateLogRoute` 接口声明需记录的路由。中间件启动时收集并构建 map
- 完整分层：domain → ent schema → repository → usecase → middleware → handler → fx wiring

## 核心机制

- 替换 `gin.ResponseWriter` 捕获响应体，从 JSON 提取 `code/data/message/err`
- `ResData` 只存 `data` 字段（业务数据），code/err/message 存独立列
- 异步写库：goroutine 异步写入不阻塞响应。必须用 `context.WithoutCancel(c.Request.Context())` 剥离请求取消链
- 存在异步最终一致性窗口（写入后不会立即出现在列表查询中）
- `UserExtractor` 返回 `*domain.OperateLogUser` 结构体，不返回多个值

## 从 gin.Errors 补记失败信息

- OperateLogger 位于 ErrorHandling 内层，`c.Next()` 返回时统一错误响应还没写回客户端
- 必须从 `gin.Errors` 读取 `errorx.Error` 做 code/message 兜底
- 非 5xx 场景补记 `code/message`；若 `Message` 是错误码占位则做一次 i18n 翻译
- 只要 `gin.Errors` 有错误就标记 `success=false`，不按 writer status 默认 200 误判

## Action 与 Service 规则

- Action 表示"动作类型"，Service 表示"操作对象"。区分粒度的职责在 Service，不在 Action
- 禁止为"相同动作 + 不同对象"创建新 Action。新增对象 → 新增 Service
- 同一 handler 中多个写路由操作不同实体时，用不同 Service 区分（如商品 vs 套餐、菜单 vs 菜单组、口味做法 vs 子项、分类 vs 子分类）
- 标准 Action 映射：Create/Update/Delete/Enable/Disable/EnableSale/DisableSale/Import/Export/SetDefault/ChangePassword/ConfigurePermission/Distribute/IssueCoupon/Retry/Download

## 新增 Action / Service 变更清单（6 处）

1. `domain/operate_log.go` const 块新增常量
2. `domain/operate_log.go` `Values()` 方法追加
3. `pkg/i18n/enum.go` label switch 新增 case
4. `etc/language/zh-CN.toml` 新增翻译
5. `etc/language/en-US.toml` 新增翻译
6. handler `OperateLogs()` 引用新枚举

命名约定：Go 常量 `PascalCase`，字符串值 `snake_case`，TOML 键 `SCREAMING_SNAKE_CASE`

## i18n 枚举标签

- domain 枚举 → `pkg/i18n/enum.go` switch 函数 → TOML 翻译键
- API handler 中通过 DTO 增加 `ActionLabel`/`ServiceLabel` 字段返回翻译后的值

## Path 构造

- `"/" + routeGroup + routeSuffix`（例如 group=`"product/category"`，suffix=`"/:id"` → Path=`"/product/category/:id"`）
