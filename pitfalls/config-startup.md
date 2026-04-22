# 配置与启动

> 索引：6 条 pitfall

---

## POS DI 启动缺失序列服务

**何时撞见**：POS 反复重启；日志显示 Fx 依赖注入失败。
**为什么**：POS 新增挂账 handler 引入 `domain.DailySequence` 但 `cmd/pos/main.go` 未注册。
**怎么办**：参照 backend/store 的启动 wiring；`cmd/pos/main.go` 补齐 `sequence.NewDailySequence/IncrSequence` provider 注册。

---

## scheduler 首轮启动失败不在 Dapr 是在 TOML 映射

**何时撞见**：scheduler 反复重启；日志最后才出现 Dapr 连接超时。
**为什么**：`configor.Load()` 按 struct 字段名映射；字段名与 TOML section 不一致导致 `Cron == ""`。
**怎么办**：查看 `bootstrap/scheduler.go` 字段名是否与 `etc/scheduler.toml` section 一致（如 `ProductSaleDetailTask` vs `ProductSaleDetail`）。读配置库源码确认嵌套 struct 字段名作为递归前缀的映射机制。

---

## eventcore 启动失败的首个 fatal 在迁移数据冲突

**何时撞见**：eventcore 持续重启；日志充斥 Dapr 连接超时。
**为什么**：自动迁移失败（旧数据不满足新唯一索引）；后续重启日志被 Dapr 错误覆盖。
**怎么办**：用 `docker logs <container> | rg 'auto migration failed|OnStart hook failed'` 抓第一次失败。本地库若有冲突数据，直接软删除或迁移前备份。不改代码，先修数据。

---

## 桌台二维码配置需跨服务通用

**何时撞见**：backend 生成的二维码无法跳转；配置 H5 域名和 page path 硬编码。
**为什么**：配置写死在 usecase；跨服务 DI 会因缺少配置导致启动失败。
**怎么办**：配置放在共享 `domain.AppConfig`；`TableQRCodePagePath` 用默认值 `"peopleCount"`，不在 toml/env 重复声明。业务逻辑留在 `usecase/dinetable`；`backendfx` 只做装配，不承载业务。

---

## 本地 compose 启动要完整重建镜像与依赖

**何时撞见**：整栈启动失败或单点服务重启；eventcore/taskcenter/backend 陆续报 Auth 或 DI 错误。
**为什么**：跳过 `docker compose build builder` 或 `--no-deps` 导致旧二进制与新配置不一致；依赖服务启动顺序或环境变量不对。
**怎么办**：完整执行 `docker compose down && docker compose build builder && docker compose up -d` 后才判启动结果。多个服务缺 bootstrap 配置导出时，补齐所有需要的 `Config` 结构并通过 `etc/*.toml` 装配。用 `docker logs` 而不是 `compose up` 输出找根因。

