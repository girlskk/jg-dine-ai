# Thread: backend 日志列表 curl 验收与 sms/log 修复

> 日期: 2026-04-01
> 标签: #backend #sms-log #login-log #operate-log #curl #repository #docker-compose #reflect

## Context

用户要求在 `testdata/test/` 下新增测试文件，验收 backend 的三个列表入口：短信记录列表 `SMSHandler.LogList`、登录日志列表 `LoginLogHandler.List`、操作日志列表 `OperateLogHandler.List`。后续又明确要求不要做 handler 单测，而是使用 curl 方式测试，并且运行脚本时要直接打印出实际请求的 curl。

第一次真实执行后，`login-log` 和 `operate-log` 返回 `200`，但 `sms/log` 返回 `500`。日志栈定位到 `repository/sms_log.go`，确认这是现网可触发的空指针问题，不是脚本误报。

仓库里这几个接口没有现成的 curl 验收脚本，`testdata/test/` 也是空目录，所以关键不是“补几行命令”，而是把登录取 token、查询参数拼接、实际请求打印这三个动作收敛成一个可重复执行的脚本。

## 关键决策

1. 放弃先前的 handler 单测实现，改用用户明确要求的 curl 验收脚本。继续保留 Go 单测只会制造两个互相竞争的测试入口。
2. 脚本默认走 backend 测试账号 `test/123456` 登录，自动拿 token，再顺序请求三个列表接口。
3. 每个请求在执行前都打印一条可直接复制的 curl，GET 请求中的鉴权头打印为 `Bearer $TOKEN` 占位，而执行时使用真实 token，兼顾可读性和可运行性。
4. `sms/log` 的根因修复要落在 repository，而不是 handler。`SendAtGte/SendAtLte` 是指针，不能在 nil 时直接调用 `.IsZero()`。
5. 本地接口验收遵循全量 compose 启动，而不是只拉起单个服务。之前的启动失败本质是依赖链未完全就绪，不应误判为部署文件本身有问题。

## 最终方案

新增 `testdata/test/api/backend/handler/` 下的拆分脚本：

- `common.sh` 负责登录、query 组装、curl 打印与执行。
- `sms.sh`、`login_log.sh`、`operate_log.sh` 各自只负责对应 handler 的请求参数。
- `logs.sh` 作为聚合入口，复用同一个 token 顺序执行三个列表验收。
- 默认请求 `http://127.0.0.1:8092/api/v1`。
- 所有筛选参数都支持通过环境变量覆盖，避免把测试条件写死。
- 支持 `DRY_RUN=1` 只打印 curl，不实际发请求。
- 列表请求统一追加 `HTTP_STATUS` 输出，验收时可以直接判断接口是否成功。
- 每个列表都执行两类请求：最小参数请求与包含完整筛选条件的请求。

修复 `repository/sms_log.go`：

- `buildSMSLogQuery` 增加 `nil filter` 兜底。
- `SendAtGte` / `SendAtLte` 改为先判空，再决定是否追加 sent_at 过滤条件。

新增 `repository/sms_log_test.go`：

- 覆盖 `nil filter`、无时间筛选、仅开始时间、仅结束时间四种场景，锁死 nil 指针回归。

验证：

- `go test ./repository -run TestSMSLogRepositoryTestSuite`
- `cd deploy/overlays/local && docker compose up -d && docker compose ps`
- `bash testdata/test/api/backend/handler/logs.sh`
- 实际结果：`/sms/log`、`/login-log`、`/operate-log` 的最小参数请求与全参数请求均返回 `HTTP_STATUS:200`

## 踩坑与偏差

- 一开始按常规思路写成了 Go handler 单测，但这和用户明确要求的 curl 验收方式不一致，属于方向性偏差，不是实现细节偏差。已经删除，避免遗留错误测试范式。
- 首轮 `sms/log` 失败里混了两个问题：先是脚本 header 拼接错误导致 `401`，修正后才暴露出 repository nil 指针导致的 `500`。如果停在第一层报错上，根因会被遮住。
- 中途一度尝试把 bundle 构建产物迁到 `/out` 来隔离镜像内容，但用户明确要求回撤这条改动，因此最终代码保持原部署文件不变，验收靠全量 `docker compose up -d` 保证依赖就绪。

---

> 可复用模式与反思已提取至 [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
