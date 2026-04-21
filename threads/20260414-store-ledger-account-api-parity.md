# Thread: store ledger account API parity

> 日期: 2026-04-14
> 标签: #store #ledger #handler #swagger #reflect

## Context

为 store 端补齐 `LedgerAccountHandler` 和 `LedgerAccountTypeHandler`，目标是和 backend 端保持同一套 API 能力与错误处理语义，避免 store 缺路由导致能力不对齐。

## 关键决策

1. 不是机械地把 `PlatformBackend` 改成 `PlatformStore` 就结束。store 端在 create/update/list 路径必须同时透传当前 `StoreID`，因为 ledger usecase 的归属校验和 repository 过滤都依赖 `StoreID`。
2. 路由路径沿用 backend 端的 `/ledger-account` 与 `/ledger-account-type`，只切换到 store 用户上下文与 store 平台，保证两端接口语义一致。
3. 新增 handler 后同步注册到 `api/store/storefx/storefx.go`，并刷新 store swagger 生成物，避免“代码存在但 fx 未装配”或“文档缺失”两类隐性遗漏。
4. 根据后续反馈，把 ledger 两组 handler 的 `checkErr` 从 API 层收敛到 domain，复用 `CheckLedgerAccountErr` / `CheckLedgerAccountTypeErr`，避免 backend/store 双份分叉。

## 最终方案

- 新增 `api/store/handler/ledger_account.go` 与 `api/store/handler/ledger_account_type.go`
- 新增 `api/store/types/ledger_account.go` 与 `api/store/types/ledger_account_type.go`
- 在 `domain/ledger_account.go` 与 `domain/ledger_account_type.go` 内收敛 ledger 相关错误到 `errorx` 的映射
- 在 `api/store/storefx/storefx.go` 注册两个 handler
- 运行 `go generate ./...`（目录：`api/store`）刷新 swagger
- 运行 `go build ./api/store/... ./cmd/store/...` 验证编译

## 踩坑与偏差

- 初看需求像“参考 backend，区别只有 Platform”，但实际不成立。若 store handler 不写入 `StoreID`，`VerifyLedgerAccountTypeOwnership` / `verifyLedgerAccountOwnership` 会把当前门店用户判成越权，列表查询也会退化成商户级范围。
- 本仓库当前没有 `.github/acceptance/store/` 或对应 store ledger 验收脚本，因此本次验证只能做到 swagger 生成 + 编译通过，无法复用现成 acceptance。

## 可复用模式

- 把 backend 品牌级资源复制到 store 端时，先确认 domain filter 和 ownership check 是否同时依赖 `Platform` 与 `StoreID`；很多接口不是只切平台，还必须收窄到当前门店。
- 新增 store handler 后，最少要做三件事一起提交：`handler/types`、`storefx` 注册、`api/store` 的 swagger 重新生成。
- 当 backend/store 共享同一套业务错误映射时，优先抽到 domain 级 `CheckXxxErr` helper，避免 handler 侧重复维护 switch。