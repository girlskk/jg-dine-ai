# Thread: 动态路由免认证白名单按 Gin 模板匹配

> 日期: 2026-03-30
> 标签: #auth #middleware #gin #customer #bugfix #reflect

## Context

customer `DineTableHandler` 新增了两层 group 路由 `/table/guest/:id`，声明了 `NoAuths()` 后仍然无法跳过认证。排查后确认问题不在 Gin 的嵌套路由组，而在通用认证跳过逻辑：`AllowPathPrefixSkipper` 读取的是 `c.Request.URL.Path`，白名单里声明的是 Gin 路由模板 `/table/guest/:id`，两者在动态段上天然不相等。

## 关键决策

1. 不改各 handler 的 `NoAuths()` 约定，继续允许声明 Gin 风格模板路径如 `/:id`。
2. 不把问题归因到“两层 group”，因为 group 只负责拼接出最终模板路径，真正失败点是运行时匹配策略。
3. 在共享 middleware 层统一修复，优先使用 `c.FullPath()` 做白名单匹配；当上下文没有匹配到 Gin 路由模板时，再回退到 `c.Request.URL.Path`，保留旧的前缀跳过能力。

## 最终方案

修改 `pkg/ugin/middleware/middleware.go`：

- 新增 `currentPath(c)`，优先返回 `c.FullPath()`，为空时回退到 `c.Request.URL.Path`
- `AllowPathPrefixSkipper` 和 `AllowPathPrefixNoSkipper` 统一改为基于 `currentPath(c)` 匹配

新增 `pkg/ugin/middleware/middleware_test.go` 回归测试：

- 验证 `/api/v1/table/guest/:id` 可以匹配实际请求 `/api/v1/table/guest/123`
- 验证当 `FullPath()` 为空时仍回退到请求 URL 做前缀判断

## 踩坑与偏差

- 表象容易误导成“嵌套 group 路由失效”，但 Gin 的 group 拼接没有问题。
- 只看 `NoAuths()` 字符串容易误判，必须同时看认证中间件拿的是模板路径还是实际请求路径。

---

> 可复用模式与反思已提取至 [knowledge/auth.md](../knowledge/auth.md)，按需查阅。
