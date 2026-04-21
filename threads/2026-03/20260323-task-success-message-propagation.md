# Thread: 任务成功文案跨层透传与反馈修正

> 日期: 2026-03-23
> 标签: #taskcenter #task #scheduler #backend #ent #state-machine #import #convention

## Context
任务中心原本只有 `error_message`，成功态缺少稳定的人类可读文案字段。第一轮实现时，把成功文案设计成可由 scheduler 通用透传、并尝试让下载任务也回传成功提示，还顺手补了本地 migration。用户随后明确指出这套方案有三个问题：

1. `markTaskSuccess` 传空 `SuccessMsg`，这条通道本身就是无效设计。
2. 下载任务不需要成功文案；当前只有导入任务需要对用户展示额外信息。
3. 本地开发阶段不需要为这次字段调整补 migration，上线前统一处理。

另外，用户补充了两条非常具体但有复用价值的约束：

1. `SuccessMessage` 字段应放在 `ErrorMessage` 附近，而不是随意插在其他位置，方便人类阅读和维护。
2. `SuccessMessage` 的赋值时机应参考下载任务里的 `FileName/FileKey` 处理方式，也就是在 `UpdateTaskStatus` 的任务类型分支中按类型设置，而不是走一个抽象但无意义的通用参数。

## 关键决策
1. `success_message` 作为 `Task` 的一等终态字段持久化，而不是让前端自己解析 `task_result`。
2. 废弃通用 `SuccessMsg` 透传做法；成功文案和 `FileName/FileKey` 一样，在 `UpdateTaskStatus` 的 `switch task.TaskType` 分支里按任务类型设置。
3. 当前只允许导入类任务写入 `SuccessMessage`；下载类任务仍只负责文件结果，不额外回传成功提示。
4. 任务从失败重试回到 `pending` 时，清空终态展示字段（`error_message` / `success_message` / `task_result` / `completed_at`），避免 UI 出现“待处理但还挂着上次终态信息”的脏状态。
5. 本地开发阶段不为这次字段调整补 migration；上线前统一处理数据库变更。

## 最终方案
- 领域模型新增 `Task.SuccessMessage`，并将字段位置放在 `ErrorMessage` 附近：
  - `domain/task.go`
- 任务 schema、仓储读写、重试状态重置同步支持 `success_message`：
  - `ent/schema/task.go`
  - `repository/task.go`
- `UpdateTaskStatus` 取消通用 `SuccessMsg` 参数，改为在任务类型分支中赋值：
  - download: 只解析并回填 `FileName/FileKey`
  - import: 解析并回填 `SuccessMessage`
  - `usecase/task/update_task_status.go`
- 下载任务结果结构保持最小，只保留文件信息，不携带成功文案：
  - `domain/task.go`
  - `usecase/dinetable/process_task.go`
- 撤销本地 migration 产物，不在当前开发阶段引入数据库迁移文件。

## 踩坑与偏差
- 第一轮把成功文案抽象成通用 `SuccessMsg` 参数，并在 scheduler `markTaskSuccess` 里传空值。这看起来“留了扩展点”，实际是无意义的假抽象：既没有减少分支，也没有提供真实数据来源，只是把赋值时机从正确的任务类型分支里挪走了。
- 第一轮还让下载任务返回成功文案。这是边界失控。用户明确说当前只有导入任务要展示附加信息，下载任务只需要文件结果；继续给下载任务塞成功文案，只会污染返回结构。
- 第一轮顺手补了本地 migration。这和用户当前开发约束冲突。不是每次 schema 调整都要立刻把本地 migration 产物塞进仓库，尤其在用户已明确“上线前统一 migration”的前提下，这种动作只会制造噪音。
- 如果只补 `Task.SuccessMessage` 而不处理 retry 回到 `pending` 的终态清理，前端仍会读到旧状态残留。这是同一条状态机语义链上的问题，必须一起修。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
