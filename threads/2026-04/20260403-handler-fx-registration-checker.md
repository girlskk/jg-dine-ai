# Thread: handler fx registration checker

> 日期: 2026-04-03
> 标签: #api #handler #fx #tooling #static-check #reflect

## Context
`api/*/handler` 下新增 handler 文件后，如果忘了在对应 `api/*/*fx` 模块里 `asHandler(handler.NewXxxHandler)` 注册，服务会静默缺路由并表现为 404。仓库里已有 `testdata/scripts/handler-routes/main.go` 可以检查已注册 handler 的 `Routes()` 是否漏挂方法，但不能覆盖“整个 handler 根本没进 fx”这一层缺口。

## 关键决策
1. 检测口径定为“handler 构造函数 vs fx provider”，而不是比对 Swagger、Gin 路径字符串或运行时路由表。根因在 DI 装配层，直接检查 `New*Handler` 是否进入 `api/*/*fx` 更稳定。
2. 只把“返回 `*XxxHandler` 且该类型实现了 `Routes(gin.IRouter)`”的构造函数视为待注册对象，避免把普通 helper 构造函数误报为缺失注册。
3. 兼容两种入口：`-root .`（仓库根目录）和 `-root ./api`（贴近现有脚本习惯），降低使用门槛。

## 最终方案
新增 `testdata/scripts/fx-registration/main.go`：
- 扫描 `api/*/handler/*.go`，收集实现 `Routes()` 的 handler 类型以及对应 `New*Handler` 构造函数。
- 扫描 `api/*/*fx/*.go`，收集 `asHandler(handler.New*Handler)` / `fx.Annotate(handler.New*Handler, ...)` 形式的已注册构造函数。
- 输出所有“有 Routes 逻辑，但未进 fx”的构造函数，并返回非零退出码。

验证命令：
- `go run testdata/scripts/fx-registration/main.go`
- `go run testdata/scripts/fx-registration/main.go -root ./api`

两次运行都命中当前仓库已有漏注册项，包括 `api/store/handler/coupon_stat_day.go`、`api/pos/handler/order.go`、`api/eventcore/handler/store.go` 等。

## 踩坑与偏差
- 不能沿用 `check_handler_routes` 的方法级别检测思路。那个脚本默认前提是 handler 已经进了容器；这次 bug 恰好发生在这个前提失效的时候。
- 单纯 grep `New*Handler` 会误把所有构造函数都算进去，必须先确认返回类型确实实现了 `Routes()`。

## 可复用模式
- 这类路由静态守护应拆两层：
  1. `handler -> Routes()` 是否漏挂方法。
  2. `handler constructor -> fx` 是否漏装配。
- 对采用统一 DI 包装器的服务，优先检查“声明对象集合”和“装配对象集合”的差集，往往比校验运行时结果更直接、更便宜。