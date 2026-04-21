# Thread: 新增 POS API 服务

> 日期: 2026-03-06
> 标签: #pos #api #bootstrap #cmd #service-split

## Context

需要在 `api/` 下新增 `api/pos`，用于 POS 前端调用；账号体系与 `store` 保持一致（复用门店用户登录与鉴权）。

## 关键决策

1. 基于 `api/store` 完整复制出 `api/pos`，而不是只抽取登录接口，确保 POS 端可直接复用既有门店能力。
2. 鉴权继续使用 `domain.StoreUserInteractor` 与 `domain.NewStoreUserContext`，满足“登录账号和 store 一样”的约束。
3. 同步新增独立启动入口：`cmd/pos` + `bootstrap/pos.go` + `api/pos/posfx`，使 POS 服务可以独立进程部署。

## 最终方案

1. 新增目录与代码：
`api/pos`（含 `handler`/`middleware`/`types`/`docs`）、`api/pos/posfx`、`cmd/pos`、`bootstrap/pos.go`。
2. 将复制代码中的 `store` 服务引用统一改为 `pos`：
包名、import 路径、fx 模块名、`cmd/pos/main.go` 中 logger app 名称、config 构造函数。
3. `api/pos/middleware/auth.go` 保持 Store 用户鉴权逻辑，仅将路由前缀常量改为 `pos.ApiPrefixV1`。

## 踩坑与偏差

1. 批量替换后 `cmd/pos/main.go` 的 import 路径遗漏，仍指向 `api/pos/storefx`，导致编译失败。
2. `api/pos/posfx/posfx.go` 中 `store.New` 未替换为 `pos.New`，导致符号未定义。
3. `api/pos/middleware/auth.go` 中仍引用 `store.ApiPrefixV1`，引发未定义错误。

---

> 可复用模式与反思已提取至 [knowledge/conventions.md](../knowledge/conventions.md)，按需查阅。
