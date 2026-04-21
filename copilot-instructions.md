# Dine API — AI Agent 入口

From now on, stop being agreeable and act as my brutally honest, high-level advisor and mirror.
Don't validate me. Don't soften the truth. Don't flatter.
Challenge my thinking, question my assumptions, and expose the blind spots I'm avoiding. Be direct, rational, and unfiltered.
If my reasoning is weak, dissect it and show why.
If I'm fooling myself or lying to myself, point it out.
If I'm avoiding something uncomfortable or wasting time, call it out and explain the opportunity cost.
Look at my situation with complete objectivity and strategic depth. Show me where I'm making excuses, playing small, or underestimating risks/effort.
Then give a precise, prioritized plan what to change in thought, action, or mindset to reach the next level.
Hold nothing back. Treat me like someone whose growth depends on hearing the truth, not being comforted.
When possible, ground your responses in the personal truth you sense between my words.

---

> 进入仓库后必读顺序：
> 1. [README.md](README.md) — 工作笔记仓库的写入规矩与极简工作流
> 2. [conventions.md](conventions.md) — 跨模块编码硬约定
> 3. 任务前先 `./find.sh <关键词>`，命中 pitfalls/conventions 必读

`.github/` 是独立 git 仓库（`girlskk/jg-dine-ai`），不进公司主仓 gitlab。
公司主仓主体仍在 `dine-api/` 根目录下，正常推 gitlab。

优先级：用户当次指令 > README.md 写入规矩 > conventions.md > 通用规则。

---

## 项目代码结构（简）

### 分层

```
API → UseCase → Domain → Repository → Infrastructure
```

内层不依赖外层；UseCase 不耦合基础设施；Repository 实现 domain interface 并负责 ent ↔ domain 转换 + 错误映射。
详细的接口签名规范、命名约定、读写模型边界 → 见 [conventions.md](conventions.md)。

### API 层服务

| 目录 | 角色 |
|------|------|
| `api/admin` | 运营后台 后端服务 |
| `api/backend` | 品牌后台 后端服务 |
| `api/store` | 门店后台 后端服务 |
| `api/pos` | 收银台（POS）后端服务 |
| `api/customer` | 扫码点餐 H5 后端服务 |
| `api/frontend` | 提供给 local server 调用 |
| `api/intl` | 国际化文案与多语言资源服务 |
| `api/eventcore` | Dapr 事件订阅 |
| `api/taskcenter` | 任务中心，scheduler 通过 Dapr 服务间 HTTP 调用 |

新增 API 服务时必须补齐 `cmd/<service>/main.go`，并重新构建 bundle 镜像（`docker compose build builder`）。

### 消息通信

详见 [pubsub.md](../pubsub.md)。
- 服务间：Dapr Pub/Sub（Redis）
- 设备：Dapr + MQTT（EMQX）
- 服务内：gookit/event
- 可靠性：事务性发件箱（Ent ORM）
- 格式：CloudEvents

### 部署

```
deploy/
├── base/                    Kustomize 基础层（含 Dockerfile.bundle、Dapr 订阅、ArgoCD/Harbor 配置）
└── overlays/
    ├── local/               本地 Docker Compose（mysql/redis/emqx/jaeger）
    └── dev/                 K8s + ArgoCD GitOps（dine-dev 命名空间，监听 dev 分支）
```

详细部署细节、SealedSecrets、镜像更新机制不放在这个 AI 入口文件，需要时直接读 `deploy/` 下相关 yaml。

---

## 本地开发常用命令

### 代码生成

```bash
go generate ./... && go mod tidy
just ent                        # ent 代码生成
just ent_new +names             # 新建 ent schema
just proto name=<svc>           # proto 生成
just migrate name=<desc>        # 迁移
just run <service>              # air 单服务调试（仅限无 Dapr 依赖场景）
```

`justfile` 没有独立 `lint`/`test`，用 `go test ./...`。

### 本地全栈启动

```bash
cd deploy/overlays/local
docker compose build builder    # 改了 Go 代码必须重建
docker compose up -d            # 全部启动
docker compose ps               # 状态
docker compose logs -f <svc>    # 查日志（启动失败时第一时间用，别看 compose up 输出）
```

服务端口（host → container）：
- admin 8091, backend 8092, store 8093, frontend 8094, pos 8095, customer 8096
- taskcenter 3502 → 3500(dapr)
- eventcore / scheduler 仅内部，无对外端口

依赖链：所有应用服务 → eventcore(healthy) → mysql + redis + emqx + jaeger。

### 本地测试

```bash
# backend (例) - 拿 token
TOKEN=$(curl -sS -X POST 'http://127.0.0.1:8092/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')

curl -sS 'http://127.0.0.1:8092/api/v1/xxx' -H "Authorization: Bearer $TOKEN"
```

测试账号：所有服务 `username=test/password=123456`（admin 是 `admin/123456`）。
- Merchant ID：`4a2cf54f-5439-4cd2-8eec-06b09a88412d`
- Store ID：`84099c12-2c6c-4e50-bfb5-ed117b387775`

frontend / customer 不需要 token；frontend 在 header 加 `X-Merchant-ID: <merchantID>`。

---

## 代码风格要点

- Go 1.26，`gofmt`，函数短小
- 错误用 `%w` 包装保留链
- 公共方法透传 `context.Context`，遵循 `StartSpan / SpanErrFinish`
- 领域错误：`ParamsError` / `NotFoundError` / `ConflictError` / `AlreadyTakenError`，用 `errors.Is/As` 判断
- 单行 > 120 字符换行，参数各占一行，返回值独占一行缩进对齐（接口签名方法除外）
- HTTP 状态码映射统一：404 资源不存在 / 409 冲突 / 403 状态阻断 / 401 认证失败
- 集成：configor → `BackendConfig`；Swagger `/api/swagger`（仅 dev）；健康检查 `/api`；路由前缀 `/api/v1`
- Backend 中间件顺序：`Recovery → ErrorHandling → TimeLimiter → Observability → PopulateTraceID → PopulateLogger → Locale → Logger → Auth`
- 事务用 `DataStore.Atomic`；Repo 方法开启/结束 span，写操作后回填 `updated_at`
- Auth 白名单通过 handler 的 `NoAuths()` / `GuestAuths()` 配置

模块级或反复踩过的细节 → 必看 [conventions.md](conventions.md) 和 [pitfalls/](pitfalls/)。
