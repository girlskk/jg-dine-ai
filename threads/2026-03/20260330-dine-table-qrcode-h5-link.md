# Thread: 桌台二维码改为配置化 H5 落地链接

> 日期: 2026-03-30
> 标签: #dine-table #qrcode #backend #customer #config #bugfix

## Context

创建桌台时生成的二维码内容只有桌台 ID，扫码后无法直接跳到 customer H5 页面。用户要求二维码内容改成完整 H5 链接，并携带桌台 ID；同时 `https://test-customer.jiguang.top` 和 `peopleCount` 必须拆成两个配置参数，不能硬编码在 usecase 里。

## 关键决策

1. 不新增独立配置依赖类型，直接复用所有服务都已注入的 `domain.AppConfig`，避免给共享 `usecasefx` 带来跨服务 DI 断裂；其中域名字段命名为更通用的 `CustomerBaseURL`，因为该域名语义上属于整个 customer 站点，不是桌台二维码私有域名。
2. 二维码内容生成从 `table.ID.String()` 收敛为专用 builder，显式校验 `baseURL` 和 `pagePath`，缺配置时直接返回错误，避免静默生成错误二维码。
3. 环境差异放在配置层处理：仓库默认配置保留本地值，dev 环境通过 `deploy/overlays/dev/config.env` 覆盖为测试域名。

## 最终方案

- `domain/app.go`
  - `AppConfig` 新增 `CustomerBaseURL` 和 `TableQRCodePagePath`
- `usecase/dinetable/table.go`
  - `DineTableInteractor` 注入 `AppConfig`
- `usecase/dinetable/table_create.go`
  - 新增 `buildQRCodeContent`
  - 使用 `url.JoinPath(baseURL, pagePath)` + `params=<tableID>` 生成二维码内容
- `usecase/dinetable/table_create_test.go`
  - 补 URL 拼接与缺配置回归测试
- `etc/backend.toml`
  - 补本地默认配置
- `deploy/overlays/dev/config.env`
  - 指定测试环境跳转到 `https://test-customer.jiguang.top/peopleCount`

## 踩坑与偏差

二维码生成点在 backend usecase，但 `DineTableInteractor` 是所有服务共用的 provider。若引入只在 backend 提供的新配置类型，会让其他服务的 Fx 装配直接失败。这个问题如果只盯业务代码，很容易漏掉。

---

> 可复用模式与反思已提取至 [knowledge/dine-table.md](../knowledge/dine-table.md)，按需查阅。
