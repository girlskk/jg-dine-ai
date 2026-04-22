# 本地开发与测试

> 入口文件：[copilot-instructions.md](copilot-instructions.md)
> 部署细节：[deploy.md](deploy.md)

---

## 代码生成

```bash
go generate ./... && go mod tidy
just ent                        # ent 代码生成
just ent_new +names             # 新建 ent schema
just proto name=<svc>           # proto 生成
just migrate name=<desc>        # 迁移
just run <service>              # air 单服务调试（仅限无 Dapr 依赖场景）
```

`justfile` 没有独立 `lint`/`test`，用 `go test ./...`。

---

## 本地全栈启动（Docker Compose）

```bash
cd deploy/overlays/local
docker compose build builder    # 改了 Go 代码必须重建
docker compose up -d            # 全部启动
docker compose ps               # 状态
docker compose logs -f <svc>    # 查日志（启动失败第一时间用，别看 compose up 输出）
docker compose up -d --force-recreate scheduler scheduler-dapr backend  # 部分重启
```

基础设施：`mysql:8` / `redis:7` / `emqx:5.8` / `jaeger:latest`。

服务端口（host → container 都是 `8080`，taskcenter 是 `3500`）：

| 服务       | host port    | Dapr sidecar    |
| ---------- | ------------ | --------------- |
| admin      | 8091         | —               |
| backend    | 8092         | —               |
| store      | 8093         | —               |
| frontend   | 8094         | —               |
| pos        | 8095         | —               |
| customer   | 8096         | —               |
| taskcenter | 3502 (→3500) | taskcenter-dapr |
| eventcore  | 内部         | eventcore-dapr  |
| scheduler  | 内部         | scheduler-dapr  |

依赖链：所有应用服务 → `eventcore (healthy)` → `mysql + redis + emqx + jaeger`。

---

## 接口测试

测试账号统一 `username=test / password=123456`（admin 是 `admin/123456`）。

- Merchant ID：`4a2cf54f-5439-4cd2-8eec-06b09a88412d`
- Store ID：`84099c12-2c6c-4e50-bfb5-ed117b387775`

### 拿 token 通用脚本

```bash
TOKEN=$(curl -sS -X POST 'http://127.0.0.1:8092/api/v1/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"123456"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')

curl -sS 'http://127.0.0.1:8092/api/v1/xxx' -H "Authorization: Bearer $TOKEN"
```

各服务登录端点（端口换一下即可）：

| 服务    | 登录 URL                                  | 账号           |
| ------- | ----------------------------------------- | -------------- |
| admin   | `http://127.0.0.1:8091/api/v1/user/login` | `admin/123456` |
| backend | `http://127.0.0.1:8092/api/v1/user/login` | `test/123456`  |
| store   | `http://127.0.0.1:8093/api/v1/user/login` | `test/123456`  |
| pos     | `http://127.0.0.1:8095/api/v1/user/login` | `test/123456`  |

### 不需要 token 的服务

- **frontend (8094)**：在 header 设 `X-Merchant-ID: 4a2cf54f-5439-4cd2-8eec-06b09a88412d`。
- **customer (8096)**：H5 扫码点餐，匿名/guest token 流程见 `pitfalls/auth.md`。

```bash
# frontend 示例
curl -sS 'http://127.0.0.1:8094/api/v1/xxx' \
  -H 'X-Merchant-ID: 4a2cf54f-5439-4cd2-8eec-06b09a88412d'
```

---

## 调试套路

- 启动失败 → `docker compose logs -f <svc>`，不要盯 `compose up` 输出
- DI/handler 注册问题 → 看 fx 启动日志的 `provided`/`invoked` 段
- Dapr 不通 → `docker compose logs <svc>-dapr`，确认 components 配置
- ent migration 失败 → `eventcore` 容器日志，迁移由它兜底执行
- 接口 401 → 先确认 `Authorization` header 没漏（`-H "Authorization: Bearer $TOKEN"`），再看是不是 handler 的 `NoAuths()` 名单问题
