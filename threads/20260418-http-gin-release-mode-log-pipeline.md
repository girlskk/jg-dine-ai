# Thread: HTTP Gin Release Mode Log Pipeline

> 日期: 2026-04-18
> 标签: #http #gin #logging #eventcore #debugging #reflect

## Context

用户在服务器日志里看到 `order/paid` 路由相关文本：

`[GIN-debug] POST /api/v1/order/paid --> ...`

外部日志系统对这条日志套了 `JSON Parser - Full Message` extractor，结果把整行纯文本当 JSON 解析，报出：`Cannot deserialize value of type LinkedHashMap from Array value`。

表面上看像是 `eventcore` 的 `order/paid` handler 反序列化失败，实际不是业务事件解析，而是 Gin 在启动阶段打印了路由注册日志。因为这些日志包含 `/api/v1/order/paid`，很容易把排查方向带偏到 handler 本身。

## 关键决策

1. 不在 `api/eventcore/handler/order.go` 做业务层修补。
原因：报错源头不是 CloudEvent `DataAs`，而是 Gin 启动时输出的纯文本路由日志，改 handler 只是在错误层级上打补丁。

2. 不把修复限定在 `eventcore`。
原因：`admin/backend/customer/eventcore/frontend/pos/store/taskcenter` 8 个 HTTP 服务都用同一套 `RunMode == dev -> gin.DebugMode` 模式切换；只修 `eventcore`，其他服务仍会持续向日志系统输出同类纯文本路由注册日志。

3. HTTP 服务统一强制 `gin.ReleaseMode`，`AppConfig.RunMode == dev` 只保留为开发能力开关。
原因：真正需要保留的 dev 行为是 swagger、grpc reflection、错误详情等业务侧开发能力，不是 Gin 自带的路由调试输出。后者会污染日志管道，在 dev/uat 环境一样有害。

## 最终方案

- 新增 `pkg/ugin/mode.go`
  - 提供 `SetReleaseMode(runMode string) bool`。
  - 所有 HTTP 服务统一调用该 helper，把 Gin 显式切到 `release`。
  - helper 返回 `runMode == dev`，供 app 层决定是否开启 swagger 等 dev-only 能力。

- 更新 8 个 HTTP 服务入口：
  - `api/admin/app.go`
  - `api/backend/app.go`
  - `api/customer/app.go`
  - `api/eventcore/app.go`
  - `api/frontend/app.go`
  - `api/pos/app.go`
  - `api/store/app.go`
  - `api/taskcenter/app.go`

  上述入口不再直接调用 `gin.SetMode(gin.DebugMode)`；`eventcore/taskcenter` 只设置 release mode，其他带 swagger 的服务继续按 `runMode == dev` 控制 swagger 路由。

## 踩坑与偏差

1. 第一轮误判为“非 dev 没显式切 release，导致线上误进 debug”。
本地 compose 实测后发现 `etc/*.toml` 和部分环境配置本来就大量使用 `RunMode=dev`，因此即使“只在非 dev 切 release”，dev/uat 仍会持续输出 `[GIN-debug]` 路由文本，问题没有根治。

2. `order/paid` 只是被日志内容碰巧命中，不是根因。
如果沿着 handler 里的 `evt.DataAs(&eventData)` 往下挖，只会浪费时间，因为 extractor 报错根本发生在日志采集侧，而不是应用业务侧。

3. 本地整栈第一次 `docker compose up -d` 会停在依赖链初始化边界，不能据此误判服务启动失败。
重试一次整栈 `up -d` 后应用服务全部正常拉起，说明这一步更像 compose 依赖/健康检查时序问题，而不是本次代码改动引入的回归。

## Verify

已执行：

- `gofmt -w pkg/ugin/mode.go api/admin/app.go api/backend/app.go api/customer/app.go api/eventcore/app.go api/frontend/app.go api/pos/app.go api/store/app.go api/taskcenter/app.go`
- `go test ./api/admin ./api/backend ./api/customer ./api/eventcore ./api/frontend ./api/pos ./api/store ./api/taskcenter ./pkg/ugin`
- `cd deploy/overlays/local && docker compose down`
- `cd deploy/overlays/local && docker compose build builder`
- `cd deploy/overlays/local && docker compose up -d`
- `cd deploy/overlays/local && docker compose ps`
- `cd deploy/overlays/local && docker compose logs eventcore 2>&1 | rg -n '\[GIN-debug\]|/api/v1/order/paid|Listening and serving|run_mode'`
- `cd deploy/overlays/local && docker compose logs backend 2>&1 | rg -n '\[GIN-debug\]|/api/v1' | head -n 20`

结果：

- 相关 Go 包编译通过。
- 本地 compose 整栈启动成功，`eventcore` 健康。
- `eventcore` 日志中过滤 `[GIN-debug]` 和 `/api/v1/order/paid` 后无匹配。
- `backend` 日志中过滤 `[GIN-debug]` 和 `/api/v1` 后也无匹配，说明共享修复生效。

## 可复用模式

- 当日志系统报“JSON parser / extractor 失败”，先确认日志源是否真的是 JSON，不要被日志内容里的业务路由名带偏。
- `AppConfig.RunMode == dev` 不等于 Gin 必须运行在 debug mode。开发能力开关和日志输出模式是两件事，应拆开控制。
- 对多服务共享的启动噪音问题，优先在共享 helper 或统一入口修，不要在单个 handler 上做局部止血。