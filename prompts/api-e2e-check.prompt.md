---
name: API E2E Check
description: "本地部署后执行接口端到端检查（登录、鉴权、请求、结果清单）"
argument-hint: "例如：service=backend endpoint=/charge_record method=POST body={...}"
agent: agent
---
请在 `dine-api` 仓库内执行一次接口 E2E 检查，并输出可读的验证报告。

输入参数（若用户提供则优先使用）：
- `service`：`admin` | `backend` | `store` | `frontend` | `pos` | `customer`
- `endpoint`：接口路径（例如 `/api/v1/charge_record`）
- `method`：`GET` | `POST` | `PUT` | `DELETE`
- `body`：JSON 请求体（可选）
- `headers`：额外请求头（可选）
- `repeat`：压测次数（可选，默认 `1`）

严格按以下流程执行：

1. 部署与状态检查
- 使用本仓库标准本地流程，不要直接 `go run` 单服务。
- 进入 `deploy/overlays/local` 后执行：
  - `docker compose build builder`
  - 先按依赖关系确认最小启动链路（来自 `deploy/overlays/local/compose.yaml`）：
    - `eventcore` 依赖：`mysql` + `redis` + `emqx` + `jaeger`
    - `admin/backend/store/pos/frontend/customer` 依赖：`mysql` + `redis` + `emqx` + `jaeger` + `eventcore`
    - `scheduler` 依赖：`mysql` + `redis` + `emqx` + `jaeger` + `eventcore`
    - `taskcenter` 依赖：`mysql` + `redis` + `jaeger`（不依赖 `eventcore`）
  - 按目标服务启动，不要固定启动 `backend`，并显式包含依赖链：
    - `service=admin`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore admin`
    - `service=backend`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore backend`
    - `service=store`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore store`
    - `service=pos`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore pos`
    - `service=frontend`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore frontend`
    - `service=customer`：`docker compose up -d --force-recreate mysql redis emqx jaeger eventcore customer`
    - 若用户要求全量环境，使用：`docker compose up -d`
  - 启动后检查目标服务和依赖：`docker compose ps mysql redis emqx jaeger eventcore eventcore-dapr <service>`
- 若因依赖不健康导致失败，则启动全部服务：`docker compose up -d`，并检查目标服务状态。
- 确认目标服务健康后继续；若服务未启动或持续不健康，记录失败并结束检查。

2. 鉴权准备（按 service 选择）
- `admin`：`http://127.0.0.1:8091/api/v1/user/login`，账号 `admin/123456`
- `backend`：`http://127.0.0.1:8092/api/v1/user/login`，账号 `test/123456`
- `store`：`http://127.0.0.1:8093/api/v1/user/login`，账号 `test/123456`
- `pos`：`http://127.0.0.1:8095/api/v1/user/login`，账号 `test/123456`
- `frontend`：不需要 token，请求头添加 `X-Merchant-ID: 4a2cf54f-5439-4cd2-8eec-06b09a88412d`
- `customer`：若接口无鉴权则直接请求；如需鉴权按用户提供信息执行

3. 请求执行
- 组装完整 URL（默认本机端口映射）。
- 若 `repeat > 1`，循环请求并统计 `success/fail`，记录失败响应样本。
- 优先用可复现实测脚本（`curl` 或 Python）并保存结果摘要。

4. 输出报告（必须）
- `Request`: method/url/headers(脱敏)/body
- `Auth`: 登录是否成功、token 是否获取
- `Result`: HTTP 状态码、业务 code、核心响应字段
- `Repeat Summary`（当 `repeat > 1`）：总次数、成功数、失败数、失败样本
- `Checklist`:
  - 服务已启动
  - 鉴权正确
  - 接口返回符合预期
  - 失败原因与建议修复

执行要求：
- 遵循仓库 `.github/WORKFLOW.md` 的 Verify/Integrate/Reflect 思路，至少给出 checkpoint 通过/失败结论。
- 不要编造请求结果；无法执行时明确说明阻塞原因与替代验证方案。
- 输出中不要泄露完整敏感信息（token 仅展示前后缀）。
