# 配置与启动排障

> 索引：5 条 pitfall

---

## 新增依赖后必须逐服务检查 Fx wiring

**何时撞见**：某个服务单独反复重启；日志显示 Fx 依赖注入失败或缺 provider。
**为什么**：编译只能证明类型存在，不能证明每个 `cmd/<service>/main.go` / bootstrap 都注册了运行时依赖；backend/store/pos/taskcenter/eventcore 的 wiring 互不兜底。
**怎么办**：先定位实际启动入口，再对照同类服务补齐 provider/exported config；新增 usecase/handler/domain service 依赖时，用 `rg "NewXxx|domain.Xxx|fx.Provide" cmd bootstrap api usecase adapter` 查所有需要启动的服务。

---

## TOML section 必须匹配 bootstrap struct 字段

**何时撞见**：scheduler 反复重启；日志最后才出现 Dapr 连接超时。
**为什么**：`configor.Load()` 按 struct 字段名映射；字段名与 TOML section 不一致导致 `Cron == ""`。
**怎么办**：查看 `bootstrap/scheduler.go` 字段名是否与 `etc/scheduler.toml` section 一致（如 `ProductSaleDetailTask` vs `ProductSaleDetail`）。读配置库源码确认嵌套 struct 字段名作为递归前缀的映射机制。

---

## eventcore 首个 fatal 常被后续 Dapr 日志盖住

**何时撞见**：eventcore 持续重启；日志充斥 Dapr 连接超时。
**为什么**：真正的启动失败通常在第一段 fatal（如自动迁移、配置加载、provider 初始化）；服务重启后只剩下游 Dapr/依赖超时噪音。
**怎么办**：用 `docker logs <container> | rg 'auto migration failed|OnStart hook failed|panic|fatal'` 抓第一次失败。本地库若有冲突数据，先修数据；不要为本地问题生成 SQL migration 文件。

---

## VS Code 宿主机调试新 schema 时旧 eventcore 不会替你迁库

**何时撞见**：F5 调宿主机 gateway/taskcenter 新代码，接口报 `Unknown column '<table>.<new_field>'`。
**为什么**：被调试服务跑的是工作区源码，但迁移靠容器里的 eventcore；旧 `dine-bundle` 不认识新 ent schema。
**怎么办**：先 `docker compose build builder && docker compose up -d --force-recreate eventcore`；若只救本地库，可手工补 nullable 新列，但不要生成 SQL migration 文件。

---

## 本地整栈排障先消除旧镜像与半启动状态

**何时撞见**：整栈启动失败或单点服务重启；eventcore/taskcenter/backend 陆续报 Auth 或 DI 错误。
**为什么**：跳过 `docker compose build builder` 或 `--no-deps` 导致旧二进制与新配置不一致；依赖服务启动顺序或环境变量不对。
**怎么办**：完整执行 `docker compose down && docker compose build builder && docker compose up -d` 后才判启动结果。多个服务缺 bootstrap 配置导出时，补齐所有需要的 `Config` 结构并通过 `etc/*.toml` 装配。用 `docker logs` 而不是 `compose up` 输出找根因。
