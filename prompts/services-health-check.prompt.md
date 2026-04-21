---
name: Services Health Check
description: "批量检查本地 8091-8096 服务是否正常启动（curl /api 健康地址）"
argument-hint: "例如：ports=8091,8092,8093,8094,8095,8096 base=http://localhost path=/api"
agent: agent
---
请在 `dine-api` 仓库执行本地服务健康检查，并输出可读报告。

输入参数（若用户提供则优先）：
- `base`：基础地址，默认 `http://localhost`
- `ports`：端口列表，默认 `8091,8092,8093,8094,8095,8096`
- `path`：健康检查路径，默认 `/api`
- `timeout_sec`：单次请求超时秒数，默认 `8`

严格按以下流程执行：

1. 检查前置状态
- 使用 `curl` 对每个目标地址发起请求：`${base}:${port}${path}`。
- 记录每个地址的 HTTP 状态码与响应体。
- 请求失败（超时/连接失败）时，记录失败原因，不要编造结果。

2. 结果判定
- 当某地址返回 `HTTP 200` 且响应体为有效 JSON（如包含 `build_version`、`run_mode`）时，判定该服务“启动正常”。
- 其余情况判定为“异常”，并给出建议（查看 `docker compose ps`、对应服务日志、依赖服务状态）。

3. 报告输出（必须）
- `Summary`: 正常数量 / 总数量
- `Details`: 每个地址的 `URL`、`HTTP`、`Body(摘要)`、`Status(正常/异常)`
- `Conclusion`: 是否可认定“服务启动正常”

执行要求：
- 遵循 `.github/WORKFLOW.md` 的 Verify 思路，给出 checkpoint 通过/失败结论。
- 输出必须基于真实执行结果；若无法执行，明确阻塞原因与下一步建议。
