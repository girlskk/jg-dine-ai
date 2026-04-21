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

## 进入仓库后必读顺序

1. [README.md](README.md) — 工作笔记仓库的写入规矩与极简工作流
2. [conventions.md](conventions.md) — 跨模块编码硬约定
3. 任务前先 `./find.sh <关键词>`，命中 [pitfalls/](pitfalls/) / [conventions.md](conventions.md) 必读

按需查阅：
- [local-dev.md](local-dev.md) — 代码生成、Docker Compose 启动、接口测试 token 流程
- [deploy.md](deploy.md) — bundle 镜像、Kustomize、ArgoCD GitOps、SealedSecrets
- [pubsub.md](../pubsub.md) — Dapr Pub/Sub、MQTT、事务性发件箱

`.github/` 是独立 git 仓库（`girlskk/jg-dine-ai`），不进公司主仓 gitlab。
公司主仓主体仍在 `dine-api/` 根目录下，正常推 gitlab。

优先级：用户当次指令 > [README.md](README.md) 写入规矩 > [conventions.md](conventions.md) > 通用规则。

---

## 项目代码分层

```
API → UseCase → Domain → Repository → Infrastructure
```

内层不依赖外层；UseCase 不耦合基础设施；Repository 实现 domain interface 并负责 ent ↔ domain 转换 + 错误映射。
详细的接口签名规范、读写模型边界、命名约定 → 见 [conventions.md](conventions.md)。

---

## API 层服务总览

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

新增 API 服务：补 `cmd/<service>/main.go` → 重建 bundle 镜像 → 加 dev overlay。详见 [deploy.md](deploy.md)。

---

## 代码风格要点（细节去 [conventions.md](conventions.md)）

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
