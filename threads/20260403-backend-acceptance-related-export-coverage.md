# Thread: backend 验收补齐关联 export 接口

> 日期: 2026-04-03
> 标签: #backend #acceptance #export #task #reflect

## Context

用户要求把 backend 下此前未纳入验收的 export 接口补进 acceptance，但范围不是“所有 backend export”，而是仅限于当前已经有验收脚本、且和现有接口成对出现的 export 路由。

这意味着不能把整个 backend 的导出接口扫一遍塞进验收目录，否则会把无关模块混进来，破坏当前按资源脚本组织的边界。

## 关键决策

1. 不新增独立 export 脚本，导出验收直接内嵌到对应资源脚本里。
2. 只补 5 个当前有直接关联的接口：
   - `order_sale_summary.sh` → `POST /data/order-sale-summary/export`
   - `product_sale_detail.sh` → `POST /data/product-sale-detail/export`
   - `product_sale_summary.sh` → `POST /data/product-sale-summary/export`
   - `shift_record.sh` → `POST /shift-record/export`
   - `dine_table.sh` → `POST /table/download-qrcode`
3. `additional_fee` / `tax_fee` 这类配置 CRUD 脚本不补统计导出，因为那是不同资源、不同 handler，不属于“当前验收脚本直接关联的 export”。
4. export 覆盖引入了更多 `sync_direct` 下载任务后，`task.sh` 的 retry 取样必须显式限制为 `run_mode=async_center`，否则会把不可 retry 的同步直出任务拿去重试并稳定报 `400`。

## 最终方案

在原脚本中补 export 调用：

- `order_sale_summary.sh`：新增 export minimal/full body
- `product_sale_detail.sh`：新增 export minimal/full body
- `product_sale_summary.sh`：新增 export minimal/full body
- `shift_record.sh`：新增 export minimal/full body
- `dine_table.sh`：新增二维码下载 minimal/full body

同时修正 `task.sh`：

- fail 样本查找只取 `run_mode=async_center`
- success seed source 只取 `task_type=download + run_mode=async_center`

## 验证

已完成：

- `bash -n .github/acceptance/backend/order_sale_summary.sh .github/acceptance/backend/product_sale_detail.sh .github/acceptance/backend/product_sale_summary.sh .github/acceptance/backend/shift_record.sh .github/acceptance/backend/dine_table.sh .github/acceptance/backend/task.sh`
- `ACCEPTANCE_RUN_LABEL=merchant-dine-table-export-coverage bash .github/acceptance/backend/modules/merchant.sh dine_table`
- `ACCEPTANCE_RUN_LABEL=report-export-coverage-rerun-7 bash .github/acceptance/backend/modules/report.sh`
- `ACCEPTANCE_RUN_LABEL=task-direct-rerun-7 bash .github/acceptance/backend/task.sh`

最终结果：

- `merchant/dine_table`: 脚本 `1`，HTTP `11`，全部 `200`，`SKIP=0`
- `report`: 脚本 `5`，HTTP `25`，全部 `200`，`SKIP=0`

## 踩坑与偏差

- 第一轮补 export 后，报表模块不是 export 接口本身失败，而是 `task.sh` 被新生成的 `sync_direct` 任务污染了 retry 样本池，导致 retry 命中“不支持重试的同步导出任务”。
- 这类问题如果只看新增接口的 `HTTP_STATUS`，很容易漏掉；必须看模块总报告，才能发现联动回归落在 `task.sh` 而不是 export 脚本本身。

## 可复用模式

- backend 某个资源脚本如果已覆盖 list/detail/write，而 handler 同时暴露成对的 export 路由，导出验收应内嵌到同一个脚本里，不要再拆一份 export-only 脚本。
- 带 `retry` 语义的任务验收一旦和 export 联动，样本选择必须区分 `sync_direct` 和 `async_center`，不能按 `task_type=download` 粗抓。