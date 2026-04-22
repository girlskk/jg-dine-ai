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

1. **本文件下方"AI 文档维护契约"** — 不读 = 你会在三天内污染本仓库
2. [README.md](README.md) — 工作笔记仓库的写入规矩与极简工作流（长版）
3. [conventions.md](conventions.md) — 跨模块编码硬约定
4. 任务前先 `./find.sh <关键词>`，命中 [pitfalls/](pitfalls/) / [conventions.md](conventions.md) 必读

按需查阅：
- [local-dev.md](local-dev.md) — 代码生成、Docker Compose 启动、接口测试 token 流程
- [deploy.md](deploy.md) — bundle 镜像、Kustomize、ArgoCD GitOps、SealedSecrets
- [pubsub.md](../pubsub.md) — Dapr Pub/Sub、MQTT、事务性发件箱

`.github/` 是独立 git 仓库（`girlskk/jg-dine-ai`），不进公司主仓 gitlab。
公司主仓主体仍在 `dine-api/` 根目录下，正常推 gitlab。

优先级：用户当次指令 > 本文件 AI 文档维护契约 > [README.md](README.md) > [conventions.md](conventions.md) > 通用规则。

---

## AI 文档维护契约（强制，违反即视为污染本仓库）

### 两层文档定位（互斥，不允许重叠）

| 层 | 路径 | 写什么 | 不写什么 |
|---|---|---|---|
| **conventions** | `conventions.md`（单文件） | 跨模块的硬约定 | 一次性实现细节、模块介绍 |
| **pitfalls** | `pitfalls/<topic>.md` | 反复踩、未来仍会再撞的坑 | 一次性 bug、配置错误 |

调试过程只进 commit message。不写 thread、不留历史日志。不要建任何新目录（threads/ knowledge/ decisions/ acceptance/ prompts/ templates/ 全部已删，永不复活）。

### 任务完成时必须自检（不要等用户问）

每次任务结束前，问自己：
1. 本次有发现/修正/反转任何"硬约定"吗？ → 有 → 同步更新 `conventions.md`
2. 本次踩的坑三个月后我或下一个 AI 还会再撞吗？ → 是 → 写进 `pitfalls/<topic>.md`
3. 本次只是个一次性 bug 或配置失误？ → 是 → **只写 commit message，不动文档**

### 写入前 4 道 gate（任何一道答 No → 不写）

1. 这个结论 grep 现有 `.github/` 已经存在了吗？ → 是 → **不写**，更新原文档
2. 这是"三个月后我会再撞的坑"吗？ → 否 → **不写**，commit message 即可
3. 这条信息能用 1-2 行表达完吗？ → 否 → **拆**，每条 pitfall 单独写
4. 我能立刻指出"未来谁会查它"吗？ → 否 → **不写**，没读者的文档=垃圾

### 修正既有条目时（最容易出错的环节）

- **反转/推翻既有结论时，commit message 必须写明旧结论 + 反转理由**。否则下一个 AI 拿不到上下文，可能再反转回去（已经发生过：export 分流策略被反转两次）。
- 改条目时**就地 replace**，不要追加"补充说明"——文档不是 changelog。
- 默认**合并到现有文件**；新建文件必须能回答"为什么合不进现有文件"。

### 体量硬上限（超限即拆/砍）

- 单个 pitfall 文件 > 200 行 → 必须拆
- `conventions.md` > 300 行 → 重审哪些条目可删
- `pitfalls/` 总文件数 > 15 → 触发合并 / 删除

### 删除门槛

- 同一个坑 commit message 出现 ≥ 2 次 → 升级到 `pitfalls/<topic>.md`
- pitfall 对应代码已重构 / 不复存在 → **直接删，不要保留"历史"**
- conventions 条目代码已不存在 → 直接删

### 删除目录后必须做的事

删除任何文件/目录后，立刻 `grep -rn "<deleted-name>" .github/` 清理反向引用。曾经因为漏做这步在 pitfalls 里留了 13 处死链。

### 禁止项

- ❌ 不写 repo memory（不跨机、不可读、人类视角不友好）
- ❌ 不写"模块介绍"性质的文档（代码即文档）
- ❌ 不建 thread / 模板 / 调试日志 / acceptance / prompts 目录
- ❌ 不在 pitfall 里留 `**历史**：threads/...` 之类指向已删目录的链接

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
| `api/intl` | 独立 gRPC 微服务（cmd/intl + etc/intl.toml + intlfx），当前业务接口只有 `Ping`，预留承载未来集中式 i18n 资源（多端共享/热更新/租户覆盖）。当前 i18n 仍走进程内 `pkg/i18n` + `etc/language/*.toml`，详见 [conventions.md](conventions.md) |
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
