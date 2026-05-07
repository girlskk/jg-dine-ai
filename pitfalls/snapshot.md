# 快照与持久化时机

> 索引：3 条 pitfall

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


---

## 多门店拆单：全订单级字段不要在 per-store 循环里复制

**何时撞见**：H5/POS 多门店下单后，配送费/打包费/平台折扣等"整单级"金额被乘以门店数，母单 `amount_due` 异常膨胀。
**为什么**：handler 把 `req.DeliveryInfo`（全订单级输入）在 `for _, storeOrder := range req.StoreOrders` 循环里写到每张子单的 `Amount` 上；usecase `recalcOrdersAmount` 按子单逐个汇总到母单 → N 倍累加。
**怎么办**：全订单级字段（外卖费用、平台折扣、整单备注等"非每店独立"的输入）必须按"单店直写 / 多店走独立参数"拆开传递：
- 单店（`len(orders)==1`）：handler 直接写到唯一订单的 `Amount/DeliveryPlatform`，usecase recalc 时一并算入。
- 多店：handler 构造独立 DTO（如 `domain.OrderDeliveryInfo`）作为参数传给 usecase；usecase **不下放到任何子单**，聚合后在 `mainOrder.Amount` 上一次性补齐并 `RecomputeAmountDue`。
判别口诀：写在循环里的字段必须是"每店独立"的；全订单级字段从循环里搬出来。
