# 快照与持久化时机

> 索引：7 条 pitfall

---

## 报表快照日期持久化与幂等校验

**何时撞见**：报表生成任务重复执行或数据被覆盖。
**为什么**：没有按 `business_date` 做幂等校验；旧逻辑允许先删后插。
**怎么办**：三张报表 repo 增加 `ExistsByBusinessDate`；任务命中已生成日期时直接跳过。报表数据来源必须通过专用 repo 方法（不改旧逻辑）；聚合与映射在 usecase 内存完成。


---

## 导出任务阈值分流下同步结果需落表

**何时撞见**：同步导出完成后任务列表看不到这条记录或 `run_mode` 过滤失真。
**为什么**：同步直出不上报任务记录；`ReportTask` 和 `NewTask` 混用一个方法签名。
**怎么办**：默认全部模块走 300 条阈值分流——同步直出也必须 `domain.ReportTask` 落表（`run_mode=sync_direct`），异步走 `NewTask`（`run_mode=async_center`）。**唯一例外是 `ProductSaleDetail` / `ProductSaleSummary`**：查询带 `GROUP BY`，先 count 等于 group by 跑两遍；走完 group by 再判断分流就是浪费已完成的工作，因此这两个永远走异步、不分流。
