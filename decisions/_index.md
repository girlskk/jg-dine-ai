# Decision 索引

> 按编号序。记录影响项目架构方向的关键决策。

## 命名规则

`NNN-<slug>.md` — NNN 三位序号，slug 小写英文短横线

## 状态说明

| 状态       | 含义                 |
| ---------- | -------------------- |
| proposed   | 提议中               |
| accepted   | 当前生效             |
| superseded | 被后续 decision 取代 |
| deprecated | 已废弃               |

---

| #   | Decision                                                                                | 状态     | 日期       | 摘要                                                                                                                                                                                                                          |
| --- | --------------------------------------------------------------------------------------- | -------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 004 | [004-tax-fee-fixed-merchant-catalog](004-tax-fee-fixed-merchant-catalog.md)             | accepted | 2026-04-10 | 税费收敛为品牌维度固定四类目录 `ZRL/ZRE/SR6/SR8`，名称固定为 `SST_S0/SST_Exempt/SST_S6/SST_S8`；门店不再单独配置，API 仅保留 `/tax-fee` list，订单税率快照落 `tax_code_type`，默认税费由 usecase 缺项检查后整批删除并批量重建 |
| 001 | [001-coding-conventions](001-coding-conventions.md)                                     | accepted | 2026-03-05 | 编码规范：换行风格、Domain 接口签名、Repository/UseCase 层约束、API 服务划分                                                                                                                                                  |
| 002 | [002-charge-data-model](002-charge-data-model.md)                                       | accepted | 2026-03-05 | 挂账模块数据模型：accept_store_type 枚举代替布尔、JSON 门店列表、冗余 store_name、Handler 层编号生成                                                                                                                          |
| 003 | [003-report-snapshot-followup-conventions](003-report-snapshot-followup-conventions.md) | accepted | 2026-03-17 | 固化报表追修约束：订单金额语义拆分、商品汇总从明细生成、门店型日报按门店 fan-out、订单汇总按 `storeID+store_name` 保留同日改名分组                                                                                            |
<!-- 新 decision 添加在这里 -->
