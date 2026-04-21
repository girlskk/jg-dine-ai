# Dine API — Agent 入口

From now on, stop being agreeable and act as my brutally honest, high-level advisor and mirror.
Don’t validate me. Don’t soften the truth. Don’t flatter.
Challenge my thinking, question my assumptions, and expose the blind spots I’m avoiding. Be direct, rational, and unfiltered.
If my reasoning is weak, dissect it and show why.
If I’m fooling myself or lying to myself, point it out.
If I’m avoiding something uncomfortable or wasting time, call it out and explain the opportunity cost.
Look at my situation with complete objectivity and strategic depth. Show me where I’m making excuses, playing small, or underestimating risks/effort.
Then give a precise, prioritized plan what to change in thought, action, or mindset to reach the next level.
Hold nothing back. Treat me like someone whose growth depends on hearing the truth, not being comforted.
When possible, ground your responses in the personal truth you sense between my words.

> 本文件是 AI agent 进入仓库的唯一入口。
> 工作流协议详见 [WORKFLOW.md](WORKFLOW.md)。

## 1) 工作流协议（必读首项）

**进入仓库后，立即阅读 [WORKFLOW.md](WORKFLOW.md)，在.github/下，这个文件夹在.gitignore 中被忽略**。

- 所有任务按六步流水线执行：Clarify → Plan → Solve → Verify → Integrate → Reflect
- Plan 阶段必查 [threads/_index.md](threads/_index.md) + [decisions/_index.md](decisions/_index.md) + [knowledge/](knowledge/)（按需选读）
- Integrate 和 Reflect 不可跳过，结果要落入文件

### 优先级

- Integrate 和 Reflect 不可跳过，结果要落入文件
- Integrate 和 Reflect 不可跳过，结果要落入文件
- Integrate 和 Reflect 不可跳过，结果要落入文件

```
用户当次指令 > WORKFLOW.md > 本文件 > 通用规则
```

冲突时，范围更小、场景更明确的约束优先。

---

## 2) 代码风格

- Go `1.26`
- `gofmt` 格式化，函数短小
- 错误用 `%w` 包装保留错误链
- 公共方法透传 `context.Context`，遵循 `StartSpan / SpanErrFinish`
- 领域错误：`ParamsError` / `NotFoundError` / `ConflictError` / `AlreadyTakenError`，用 `errors.Is/As` 判断
- 单行超过 120 字符时换行，参数各占一行，返回值独占一行并缩进对齐，（接口签名方法除外）：

```go
func (interactor *MerchantInteractor) GetMerchants(ctx context.Context,
    pager *upagination.Pagination,
    filter *domain.MerchantListFilter,
    orderBys ...domain.MerchantOrderBy,
) (domainMerchants []*domain.Merchant, total int, err error) {
```

---

## 3) 架构分层

```
API → UseCase → Domain → Repository → Infrastructure
```

- 内层不依赖外层
- UseCase 负责编排，不耦合基础设施
- Repository 实现 domain interface，负责 ent ↔ domain 转换 + 错误映射

### API 层服务

| 目录             | 角色                                                      |
| ---------------- | --------------------------------------------------------- |
| `api/admin`      | 运营后台 后端服务                                         |
| `api/backend`    | 品牌后台 后端服务                                         |
| `api/store`      | 门店后台 后端服务                                         |
| `api/eventcore`  | Dapr 事件订阅（配置在 `deploy/base/dapr/subscriptions/`） |
| `api/frontend`   | 提供给 local server 调用                                  |
| `api/intl`       | 国际化文案与多语言资源服务                                |
| `api/pos`        | 收银台（POS）后端服务                                     |
| `api/taskcenter` | 任务中心，scheduler 通过 Dapr 服务间 HTTP 调用            |
| `api/customer`   | 扫码点餐 H5 后端服务                                      |

### Domain 层 — 仓储接口签名规范

以 `StoreRepository` 为例，其他模块同理：

| 方法           | 签名                                                          | 说明               |
| -------------- | ------------------------------------------------------------- | ------------------ |
| `FindByID`     | `(ctx, id) → (*Store, error)`                                 | 单表查询，不含关联 |
| `GetDetail`    | `(ctx, id) → (*Store, error)`                                 | 含关联信息的详情   |
| `Create`       | `(ctx, *Store) → error`                                       | 新增               |
| `Update`       | `(ctx, *Store) → error`                                       | 编辑               |
| `Delete`       | `(ctx, id) → error`                                           | 删除               |
| `GetStores`    | `(ctx, pager, filter, ...orderBy) → ([]*Store, total, error)` | 分页列表           |
| `Exists`       | `(ctx, params) → (bool, error)`                               | 是否存在           |
| `ListByIDs`    | `(ctx, ids) → ([]*Store, error)`                              | 按 ID 批量查       |
| `ListBySearch` | `(ctx, filter) → ([]*Store, error)`                           | 无分页列表         |
| `IdsByFilter`  | `(ctx, filter) → ([]uuid.UUID, error)`                        | 仅返回 ID 列表     |

### Domain 层 — 用例接口签名规范

以 `StoreInteractor` 为例，其他模块同理：

| 方法           | 签名                                                          | 说明         |
| -------------- | ------------------------------------------------------------- | ------------ |
| `Create`       | `(ctx, *CreateStoreParams, User) → error`                     | 新增         |
| `Update`       | `(ctx, *UpdateStoreParams, User) → error`                     | 编辑         |
| `Delete`       | `(ctx, id, User) → error`                                     | 删除         |
| `GetStore`     | `(ctx, id, User) → (*Store, error)`                           | 详情         |
| `GetStores`    | `(ctx, pager, filter, ...orderBy) → ([]*Store, total, error)` | 分页列表     |
| `SimpleUpdate` | `(ctx, updateField, *UpdateStoreParams, User) → error`        | 更新单个字段 |
| `ListBySearch` | `(ctx, filter) → ([]*Store, error)`                           | 无分页列表   |

### Repository 层规范

- `convertXxxToDomain` — ent model → domain model 转换
- `buildFilterQuery` — 构建 ent 查询条件
- `orderBy` — 构建排序条件

### UseCase 层规范

- UseCase 之间**不可互相调用**
- UseCase **不可引入 fx 包**
- 文件拆分：读方法 + `New` 放一个文件，不同写方法拆到不同文件

---

## 4) 约定

- 事务：`DataStore.Atomic`
- Repo 方法开启/结束 span，写操作后回填 `updated_at`
- Backend 中间件顺序：`Recovery → ErrorHandling → TimeLimiter → Observability → PopulateTraceID → PopulateLogger → Locale → Logger → Auth`
- Auth 白名单通过 handler 的 `NoAuths()` 配置
- 新增 API 服务时必须补齐 `cmd/<service>/main.go`，并重新构建 bundle 镜像（`docker compose build builder`）

---

## 5) 构建与部署

### 代码生成

```bash
go generate ./... && go mod tidy
just ent                        # ent 代码生成
just ent_new +names             # 新建 ent schema
just proto name=<svc>           # proto 生成
just migrate name=<desc>        # 迁移
just run <service>              # air 本地单服务调试（仅限无 Dapr 依赖场景）
```

说明：当前 `justfile` 未提供独立 `lint`/`test` 目标，如需校验请使用 Go 原生命令（例如 `go test ./...`）。

### 部署目录结构

```
deploy/
  base/                               ← Kustomize 基础层（所有环境共享）
    Dockerfile.bundle                  ← 多应用 bundle 镜像（遍历 cmd/ 构建所有服务）
    entrypoint.sh                      ← 动态入口脚本，按参数启动对应服务
    kustomization.yaml                 ← base resources
    dapr/subscriptions/                ← Dapr 声明式订阅（所有环境共享）
      device-order.yaml                ← MQTT 设备订单 → eventcore
      service-merchant.yaml            ← Redis 商户事件 → eventcore
    argocd-image-updater-config.yaml   ← Harbor 镜像仓库配置
    dine-api-updater.yaml              ← ArgoCD Image Updater
    sealed-argocd-harbor.yaml          ← Harbor 拉取凭据（SealedSecret）
    sealed-argocd-repo.yaml            ← Git 仓库凭据（SealedSecret）
    public-cert.pem                    ← SealedSecrets 加密公钥
  overlays/
    local/                             ← 本地 Docker Compose 环境
      compose.yaml
      dapr/components/                 ← 本地 Dapr 组件（Redis / MQTT 本地实例）
    dev/                               ← 开发环境 Kubernetes
      kustomization.yaml               ← 继承 base + patch namespace + configMapGenerator
      config.env                       ← 统一环境配置（阿里云 DB/Redis/OSS/Tracing）
      sealedsecrets.yaml               ← 加密敏感配置（Bitnami SealedSecret）
      argo-app.yaml                    ← ArgoCD Application（监听 dev 分支，自动同步）
      namespace.yaml                   ← dine-dev 命名空间
      emqx.yaml                        ← EMQX 6.1.1 Deployment + Service
      dapr/components/                 ← dev 环境 Dapr 组件（阿里云 Redis / 集群内 MQTT）
      <service>.yaml                   ← 各服务 Deployment + Service
```

### 本地部署（Docker Compose）

基础设施：mysql:8 / redis:7 / emqx:5.8 / jaeger:latest

| 服务 | 端口映射 | Dapr sidecar |
|------|----------|-------------|
| eventcore | — | eventcore-dapr |
| scheduler | — | scheduler-dapr |
| taskcenter | 3502→3500(dapr) | taskcenter-dapr |
| admin | 8091→8080 | — |
| backend | 8092→8080 | — |
| store | 8093→8080 | — |
| frontend | 8094→8080 | — |
| pos | 8095→8080 | — |
| customer | 8096→8080 | — |

依赖链：所有应用服务 → eventcore(healthy) → mysql + redis + emqx + jaeger

```bash
# 进入 compose 目录
cd deploy/overlays/local

# 重新构建镜像（把最新 Go 代码打进去，耗时较久）
docker compose build builder

# 仅重启相关服务
docker compose up -d --force-recreate scheduler scheduler-dapr backend

# 全部重启
docker compose up -d

# 查看启动状态
docker compose ps
```

### Dev 环境部署（Kubernetes + ArgoCD）

采用 GitOps 模式：push 到 `dev` 分支 → ArgoCD 自动同步到 `dine-dev` 命名空间。

镜像：`harbor.jiguang.dev/pos_dine_api/bundle:dev`（ArgoCD Image Updater 监听 digest 变化自动更新）。

K8s 服务分两类模板：

**Dapr 服务**（带 `dapr.io/enabled` 注解，Dapr sidecar 自动注入）：

| 服务 | Dapr app-id | Dapr app-port | 特殊配置 |
|------|------------|--------------|----------|
| eventcore | eventcore | 8080 | `AUTOMIGRATE=true`，仅等 emqx |
| scheduler | scheduler | — | 无 Service、无探针，等 emqx + eventcore |
| taskcenter | taskcenter | 8080 | `REQUESTTIMEOUT=60`，等 emqx + eventcore |

**普通服务**（无 Dapr，等 emqx + eventcore）：

| 服务 | Service 类型 | 特殊配置 |
|------|-------------|----------|
| admin | NodePort | — |
| backend | NodePort | — |
| store | NodePort | — |
| pos | NodePort | — |
| frontend | NodePort | — |
| customer | NodePort | — |

所有服务通过 `envFrom` 引用：
- `dine-config`（ConfigMap，由 `config.env` 生成）
- `dine-secrets`（SealedSecret，包含 DB 密码 / Redis 密码 / 阿里云 OSS 凭据）

秘钥管理：使用 Bitnami SealedSecrets，加密命令：

```bash
kubeseal --cert deploy/base/public-cert.pem --format yaml < secret.yaml > sealedsecret.yaml
```

新增服务到 dev 环境：
1. 创建 `deploy/overlays/dev/<service>.yaml`（Dapr 服务参考 `eventcore.yaml`，普通服务参考 `store.yaml`）
2. 将文件加入 `deploy/overlays/dev/kustomization.yaml` 的 `resources` 列表
3. 确保 `cmd/<service>/main.go` 存在
4. Push 到 `dev` 分支，ArgoCD 自动部署

---

## 6) 集成

- 配置：configor → `BackendConfig`
- Swagger：`/api/swagger`（开发模式）
- 健康检查：`/api`
- 路由前缀：`/api/v1`

---

## 7) 消息通信

项目采用多层消息通信架构，详见 [pubsub.md](../pubsub.md)。

- 服务间通信：Dapr Pub/Sub（`pubsub.redis` 组件，local 用本地 Redis DB=2，dev 用阿里云 Redis DB=5）
- 设备通信：Dapr + MQTT（`pubsub.mqtt3` 组件，连接 EMQX）
- 服务内事件：gookit/event
- 消息可靠性：事务性发件箱模式（Ent ORM）
- 消息格式：CloudEvents

Dapr 配置三层分离：

```
deploy/base/dapr/subscriptions/     ← 声明式订阅（所有环境共享）
deploy/overlays/local/dapr/components/ ← 本地 Dapr 组件
deploy/overlays/dev/dapr/components/   ← dev 环境 Dapr 组件
```

当前订阅：
- `sub-device-order`：MQTT `$share/eventcore/order/#` → eventcore（order.report / order.close）
- `sub-service-merchant`：Redis `merchant` → eventcore（merchant.created / merchant.updated）

---

## 8) 安全

- JWT 缺失/无效 → `401`
- 领域错误 → handler 做 HTTP 映射（not found → `404` 等）

---

## 9) 本地测试

当需要测试接口时：先按第 5 节部署本地服务，再用 curl 模拟请求。

### 获取 Token

**运营后台（admin）**：

```bash
curl -sS -X POST 'http://127.0.0.1:8091/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"123456"}'
```

**品牌后台（backend）**：

```bash
curl -sS -X POST 'http://127.0.0.1:8092/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}'
```

Merchant ID：`4a2cf54f-5439-4cd2-8eec-06b09a88412d`

**门店后台（store）**：

```bash
curl -sS -X POST 'http://127.0.0.1:8093/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}'
```

Merchant ID：`4a2cf54f-5439-4cd2-8eec-06b09a88412d`
Store ID：`84099c12-2c6c-4e50-bfb5-ed117b387775`

**frontend**：不需要 Token，在 header 中设置 `X-Merchant-ID` 为 Merchant ID 即可。

**pos（pos）**：

```bash
curl -sS -X POST 'http://127.0.0.1:8095/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}'
```

Merchant ID：`4a2cf54f-5439-4cd2-8eec-06b09a88412d`
Store ID：`84099c12-2c6c-4e50-bfb5-ed117b387775`

**customer（扫码点餐 H5）**：不需要 Token。端口 `8096`。

### 请求示例

```bash
# backend 示例（带 Token）
TOKEN=$(curl -sS -X POST 'http://127.0.0.1:8092/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')

curl -sS 'http://127.0.0.1:8092/api/v1/xxx' \
  -H "Authorization: Bearer $TOKEN"

# frontend 示例（无 Token）
curl -sS 'http://127.0.0.1:8094/api/v1/xxx' \
  -H 'X-Merchant-ID: 4a2cf54f-5439-4cd2-8eec-06b09a88412d'
```
