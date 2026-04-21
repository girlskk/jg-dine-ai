# 报表与导出知识

> 来源 threads: report-daily-scheduler-snapshots, report-tables-pattern-conventions, report-snapshot-followup-retrospective, report-grouped-curl-verification, order-sale-summary-curl-verification, product-sale-export-task-flow, product-sale-export-runtime-i18n-download-fix, order-sale-summary-shift-record-export-corrections, report-export-sync-direct-threshold, dine-table-qrcode-export-url, task-success-message-propagation, shift-record-local-seed

## 日报快照生成模板

- 生成入口放在 usecase，scheduler handler 只负责触发和告警
- 幂等用 `ExistsByBusinessDate` 跳过，不做先删后插
- repo 只取数，不做报表组装。字段映射和聚合全部放回 usecase 内存完成
- 新增报表专用取数方法，不改旧逻辑
- 缺失数据写空值/零值并在 thread 写明，不伪造字段语义
- schema 改了不等于库也改了：迁移必须纳入交付范围
- 门店维度报表任务统一按门店 fan-out

### 快照生成步骤

`runDate = util.DayStart(date)` → `statDate = runDate.AddDate(0, 0, -1)` → 拒绝未来执行日期 → `DataStore.Atomic(...)` → `Repo.ExistsByBusinessDate(statDate)` 命中跳过 → 取原始数据 → `CreateBulk(...)` 批量落表

## 报表字段语义

- `OrderSaleSummary` 金额拆三层：`Amount`（订单整体金额汇总 JSON）、`ThirdPartyAmount`（三方支付总额）、`ThirdPartyPlatform`（第三方平台拆分 JSON）。不堆标量列
- `OrderSaleSummary` 聚合键用 `storeID-storeName`。同一门店同日改名会生成两条汇总，这是业务口径
- 聚合键必须服从业务口径，先问清楚再决定 key
- 上层 domain model 不要再镜像底层聚合字段（如 `OrderSaleSummary.RoundingAmount` vs `Amount.RoundingAmount`）

## 明细与汇总关系

- 先生成明细，再从明细推汇总。`ProductSaleSummary` 从内存中的 `ProductSaleDetail` slice 聚合，不二次回查原始交易表

## Grouped 查询

- grouped 查询排序优先按 select 别名排序，不复用 ent `ByXxx` 字段排序 helper（MySQL `only_full_group_by` 下失败）
- paged grouped 查询优先直接写在 ent query 链上：`Order + Limit/Offset + GroupBy + Aggregate`
- `ProductSaleSummary` grouped 查询直接扫描到 `*ent.ProductSaleSummary`。含 JSON 字段（attr/toppings）的需自定义 row struct + 显式反序列化

## 导出任务链路

- 异步导出模板：handler build payload → usecase create task → ProcessTask export
- 文件名在创建任务前生成，同时写入 `Task.FileName` 和 payload。callback 结果只回传 `file_key`
- payload 必须自包含（拿到它就能执行）且显式携带 locale
- 导出 PathTemplate 各自独立（`tenant_report_product_sale_detail` / `tenant_report_product_sale_summary`）
- 导出查询与列表查询不共享分页语义：导出走 `List...`（全量），列表页走 `Get...`（分页）
- 枚举翻译键按 domain 原始枚举类型和值命名（`CHANNEL_POS`、`DINING_WAY_DINE_IN`），不按报表字段名命名
- 导出逻辑独立文件，`xxxExportHeaders` 和 `buildXxxExportRow` 成对存在
- `Platform` 不能写死，由调用方通过 payload 显式传入

## 300 条阈值分流

- 仅适用于 `OrderSaleSummary`、`ShiftRecord`、`DineTable.DownloadQRCode`。`ProductSaleDetail` / `ProductSaleSummary` 保持纯异步
- ≤300 同步直出：直接调用 `ProcessTask` 导出，再调 `ReportTask` 记录 `sync_direct + success` 任务
- \>300 异步：调用 `NewTask` 创建 `pending` 任务，scheduler 消费
- `NewTask`（异步创建）和 `ReportTask`（同步上报）必须拆开
- 同步直出任务也必须写入任务表且标记 `sync_direct + success`，保证下载中心和筛选完整
- 阈值判断必须走 repository 层显式 `Count` 方法，不能借分页列表拿 `total`
- domain 公共 helper：`DirectExportThreshold = 300`、`ReportTaskReq`、`ReportTask`、`ExportTaskStoreID`、`ExportDurationSec` 收敛进 `domain/task.go`
- 导出文件名 helper 下沉到 `domain/task.go`（纯格式拼接），翻译由 usecase 提供

## 任务终态字段

- `success_message` 作为 `Task` 的一等终态字段，不塞在 `task_result` 里
- `SuccessMessage` 赋值在 `UpdateTaskStatus` 的 `switch task.TaskType` 分支里按类型设置。只有导入类任务写入
- 任务从终态回到非终态（retry → pending）时，必须同步清空终态展示字段

## 导出调试

- 按链路拆层验证：backend 建任务 → scheduler 调度 → taskcenter callback → task 状态回填 → download-url → 真实文件内容
- taskcenter 必须显式加载 `i18nfx.Module`，否则导出表头退化为 message ID
- taskcenter `ErrorHandling` middleware 必须真正挂进执行链
- 验证导出内容时解压 xlsx 的 `xl/sharedStrings.xml`，不只看日志
- 导出验证覆盖四件事：任务成功、download-url 可访问、对象能下载、sharedStrings 不含原始 message ID

## 报表联调样本

- GET 验证时优先直写快照表，不浪费时间还原完整上游链路
- 直写本地 MySQL 前先 `DESCRIBE` 真实表结构
- 报表联调样本 UUID 必须用合法十六进制字符
