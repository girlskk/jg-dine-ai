# Thread: backend 桌台二维码 page path 从共享 AppConfig 拆分

> 日期: 2026-04-01
> 标签: #backend #dine-table #config #usecase #workflow #reflect

## Context

这次问题经历了三次收敛：

1. 初始状态：`CustomerBaseURL` 和 `TableQRCodePagePath` 都在共享 `AppConfig`，并通过共享配置传播。
2. 第一轮修正：试图把 `TableQRCodePagePath` 拆成 backend-only 配置，但过程中一度把业务逻辑写进 `backendfx`，这条路被用户否定。
3. 最终收敛：用户明确要求 `TableQRCodePagePath` 回到 `AppConfig`，但不要继续在配置文件里显式声明，而是用代码默认值 `peopleCount`，这样其他服务也不会因为缺配置而受影响。

真正的稳定约束不是“这个字段必须 backend-only”，而是：

- 业务逻辑必须留在 `usecase/dinetable`
- `backendfx` 不能承载业务逻辑
- 稳定默认值不要重复配置在 toml/env 中制造漂移点

## 关键决策

1. 保留 `CustomerBaseURL` 在共享 `domain.AppConfig`。
2. `TableQRCodePagePath` 也保留在共享 `domain.AppConfig`，并通过 `default:"peopleCount"` 提供默认值。
3. 不在 `config.env` 或 `backend.toml` 中显式配置 `TableQRCodePagePath`，避免重复配置。
4. 二维码生成逻辑继续留在 `usecase/dinetable`，而不是写到 `backendfx`。`backendfx` 只负责装配。
5. 删除中间态引入的 `domain.DineTableConfig` 与各服务 bootstrap 输出，避免为了装配额外制造配置结构。

## 最终方案

- `domain/app.go`
  - `AppConfig` 保留 `CustomerBaseURL`
  - `TableQRCodePagePath` 增加默认值 `default:"peopleCount"`
- `domain/dine_table.go`
  - 删除中间态引入的 `DineTableConfig`
- `usecase/dinetable/table.go`
  - 仅依赖 `AppConfig`，不引入 `fx.In`
- `usecase/dinetable/table_create.go`
  - 保留二维码生成逻辑，通过 `CustomerBaseURL + AppConfig.TableQRCodePagePath` 构造 H5 地址
- `bootstrap/*.go`
  - 删除为中间态方案添加的 `DineTableConfig` 输出
- `etc/backend.toml`
  - 删除显式 `TableQRCodePagePath` 配置，回退到代码默认值
- `api/backend/backendfx/backendfx.go`
  - 维持纯 wiring，不承载业务逻辑

## Verify

- `go test ./usecase/dinetable ./api/backend/backendfx ./cmd/backend`
  - 通过

## Integrate

- 更新 thread 本身，覆盖掉过时实现记录
- 更新 `threads/_index.md` 摘要，避免后续 Plan 阶段读到错误结论

---

> 可复用模式与反思已提取至 [knowledge/dine-table.md](../knowledge/dine-table.md)，按需查阅。
