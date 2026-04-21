# Thread: 桌台码导出改为异步 Excel 并输出二维码 URL

> 日期: 2026-03-25
> 标签: #dine-table #export #taskcenter #backend #i18n #storage

## Context

桌台码导出原先只完成了创建任务，`ProcessTask` 仍停留在 `TODO`，而且思路还是“生成二维码图片并打 zip 包”。用户这次明确要求和其他导出保持一致：

1. 继续走异步任务。
2. 支持多语言。
3. 导出内容按表格字段输出，而不是 zip 图片包。
4. 在图片里的字段基础上新增一列 `qrcode`，并且这一列必须是二维码文件的实际 URL，不是对象 key。

## 关键决策

1. 保留现有 backend 路由 `/table/download-qrcode` 和任务事件类型，不额外发明一条新接口；只把任务处理语义从“二维码文件包”收敛为“桌台二维码 Excel 导出”。
2. `TableQRCodePayload` 补齐 `locale` 和 `file_name`，由 usecase 在建任务前生成多语言文件名。
3. `DineTableRepository` / `DineTableInteractor` 新增 `ListTables`，导出不复用分页查询。
4. 导出行的 `qrcode` 列不直接输出 `DineTable.QRCodeURL`，而是通过 `Storage.GetURL(ctx, key)` 转成实际可访问 URL。
5. 导出文件使用 `Storage.ExportExcel`，字段固定为：`code`、`name`、`capacity`、`qrcode`。

## 最终方案

- `domain/dine_table.go`
  - 仓储和用例接口新增 `ListTables`
  - `TableQRCodePayload` 新增 `locale` / `file_name`
  - 新增 `ToFilter()`
  - `DownloadQRCode` 入参从分散参数收敛为 `payload`
- `repository/dine_table.go`
  - 新增 `ListTables`
- `usecase/dinetable`
  - `download_qrcode.go` 改为直接消费 `payload`，在 usecase 内补文件名
  - `process_task.go` 实现真正的 Excel 导出逻辑
  - 导出表头 helper：`tableQRCodeExportHeaders`
  - 导出行 helper：`buildTableQRCodeExportRow`
- `api/backend/handler/dine_table.go`
  - handler 侧新增 `buildTableQRCodeExportPayload`，与其他报表导出保持相同分层
- `api/backend/types/dine_table.go`
  - `TableQRCodeDownloadReq` 补 `json` tag
- `etc/language/*.toml`
  - 补齐导出文件名和四列表头翻译键

## 验证

1. `go build ./cmd/backend ./cmd/taskcenter` 通过。
2. 本地 backend 登录成功。
3. 调用 `POST /api/v1/table/download-qrcode` 成功返回 `job_id`。
4. 新任务成功完成，生成文件：
   - `tenant/.../report/dine_table/...xlsx`
5. 解压 xlsx 验证：
   - 表头为 `Table Code / Table Name / Seats / qrcode`
   - `qrcode` 列内容是 `http://localhost:9000/dine/...png` 形式的实际 URL，而不是对象 key。

## 踩坑与偏差

1. 桌台码导出之前其实并没有“差一列”，而是整个 `ProcessTask` 还是空实现。这类 `TODO` 如果不在进入任务时彻底对照现有导出模式，很容易误判成局部补丁。
2. `DineTable.QRCodeURL` 这个字段名字本身容易让人以为库里存的是 URL，但实际存的是对象 key。导出场景必须显式转 URL，不能直接透传字段字面值。
3. 只把任务执行逻辑对齐还不够，创建任务入口如果还保留“platform/merchantID/storeID”这类分散参数，桌台码流程仍然是特例；要和其他报表一样由 handler 先组装 payload，再交给 usecase。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md), [knowledge/dine-table.md](../knowledge/dine-table.md)，按需查阅。
