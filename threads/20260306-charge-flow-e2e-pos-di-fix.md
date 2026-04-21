# Thread: 挂账流程联调与 POS DI 修复

> 日期: 2026-03-06
> 标签: #charge #e2e #pos #di #fx #verification

## Context
用户要求跑通挂账模块后端整条流程（backend + pos）。联调中发现 POS 服务反复重启，导致 `/api/v1/charge_customer` 与 `/api/v1/charge_record` 无法稳定验证。

## 关键决策
1. 先定位运行时故障，而不是继续盲目打接口。
原因：日志明确显示 Fx 依赖注入失败，属于服务启动级阻塞。
2. 参照 `cmd/backend/main.go` / `cmd/store/main.go` 的启动 wiring，在 `cmd/pos/main.go` 补齐 sequence provider。
原因：POS 新增挂账 handler 后引入 `domain.DailySequence` 依赖，启动模块未注册对应实现。
3. 在联调阶段绕过 eventcore 健康阻塞，使用 `docker compose up -d --force-recreate --no-deps backend pos`。
原因：eventcore 的 dapr 端口健康问题不影响本次挂账链路接口验证。

## 最终方案
1. 修复 POS 启动依赖：
- `cmd/pos/main.go` 新增 `domain` 与 `pkg/sequence` 引入。
- 在 `fx.Provide(...)` 中注册：
  - `sequence.NewDailySequence -> domain.DailySequence`
  - `sequence.NewIncrSequence -> domain.IncrSequence`
2. 验证：
- `gofmt -w cmd/pos/main.go`
- `go test ./cmd/pos`
3. 端到端接口联调通过，链路覆盖：
- backend：创建/查询/更新挂账客户
- pos：查询可挂账客户、创建挂账记录
- backend：查询挂账记录、创建还款单、查询还款单列表与详情

## 踩坑与偏差
1. 终端 here-doc 在当前会话多次出现输入流污染，导致长脚本输出不可信。
2. `docker compose up` 默认会受 `eventcore` 健康检查影响，需要针对本任务改为 `--no-deps` 启动目标服务。

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
