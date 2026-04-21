# Thread: 导出任务 300 条阈值分流与同步结果上报收敛

> 日期: 2026-03-31
> 标签: #report #taskcenter #backend #store #task #reflect

## Context

当前多个导出入口只有一条路径：创建 `pending` 下载任务，交给 scheduler 回调 taskcenter 再执行。用户先提出“按 300 条阈值分流 + 拆开异步创建与同步上报”的要求，随后又明确收窄范围：

1. `OrderSaleSummary`
2. `ShiftRecord`
3. `DineTable` 二维码下载

只有这三个入口需要先判断导出数据量。

- 小于等于 300 条：同步直接导出
- 大于 300 条：创建异步任务，由任务中心调度

同时用户明确要求，"创建异步调度任务" 和 "上报已完成任务" 不能继续共用一个方法，必须分开，并且任务中心要通过 `RunMode` 区分任务类型。`ProductSaleDetail` 和 `ProductSaleSummary` 必须保持纯异步导出，不能跟着一起改成阈值直出。

## 关键决策

1. 保留 `domain.NewTask` 作为异步任务创建入口，但新增 `domain.ReportTask` 单独承担同步直出结果上报，避免“待调度任务”和“已完成任务”继续混用同一套入参语义。
2. `scheduler` 继续只消费 `run_mode=async_center` 的 `pending` 任务；同步直出任务绝不能伪装成 pending，否则会被重复执行。
3. 只有 `OrderSaleSummary`、`ShiftRecord`、`DineTable.DownloadQRCode` 走 300 条阈值分流，并且总数必须通过 repository 层显式 `Count` 方法获取，不能借分页列表接口绕路拿 `total`。
4. `ProductSaleDetail`、`ProductSaleSummary` 虽然接口返回值改为 `ExportTaskResult`，但行为保持纯异步，只返回 `async_center + task_id`。
5. 同步直出路径仍然要把结果上报为任务记录，保证任务列表、下载记录和 `run_mode` 过滤一致可见。
6. 门店任务归属 helper 收敛为 `domain.ExportTaskStoreID(platform, ...uuid.UUID)`，统一兼容单个 `store_id` 和多个 `store_ids`；导出耗时 helper 也收敛进 `domain/task.go`，避免每个 usecase 各写一份局部版本。

## 最终方案

- `domain/task.go`
  - 新增 `DirectExportThreshold = 300`
  - 新增 `ReportTaskReq`
  - 新增 `ReportTask`
  - 新增 `ExportTaskStoreID`
  - 新增 `ExportDurationSec`
- `repository/task.go`
  - `Create` 增加 `SetTaskResult`，允许 `ReportTask` 落库完整结果快照
- `OrderSaleSummary.Export` / `ShiftRecord.Export`
  - 先调用 repository 的 `Count...` 获取总数
  - `total > 300`：调用 `NewTask` 创建异步任务
  - `total <= 300`：直接调用 `ProcessTask` 导出，再调用 `ReportTask` 记录 `sync_direct` 成功任务
- `DineTable.DownloadQRCode`
  - 接口返回值从 `uuid.UUID` 改为 `ExportTaskResult`
  - 先用 repository 的 `CountTables(...)` 获取总数
  - `total > 300`：创建异步下载任务
  - `total <= 300`：直接执行 `ProcessTask`，并上报同步完成任务
- `ProductSaleDetail` / `ProductSaleSummary`
  - 仅把返回值对齐为 `ExportTaskResult`
  - 保持纯异步导出，不参与阈值分流

## Verify

- `gofmt -w ...` 已执行，覆盖本次范围内修改文件
- `go build ./cmd/backend ./cmd/store ./cmd/taskcenter` 通过
- 本次范围内修改文件 `get_errors` 全部无报错

## 踩坑与偏差

1. 第一版实现改得太宽，连商品销售两个导出和其它调用点都一起碰了，直接违背了用户后续的范围约束。这不是“顺手优化”，是擅自扩张需求。
2. 如果把同步直出任务也创建成 `pending`，scheduler 会二次拾取执行，结果不是“兼容”，而是明显的数据和状态重复。
3. 如果只在 HTTP 响应里返回文件，不上报任务记录，任务列表就会丢失同步导出的可追踪性，`run_mode` 过滤也会失真。
4. 判断阈值时借 `Get...` 列表接口拿 `total` 也不对。即使只查 1 条数据，过滤、分页、排序和列表语义仍然被强绑在一起，后续很容易继续演化成重查询路径。
5. thread 如果不按最终收敛结果修正，会把错误范围固化成“项目约定”，后续 agent 会沿着错误摘要继续改错文件。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
