# Decision 003: 报表快照追修约束

> 状态: accepted
> 日期: 2026-03-17
> 关联 Thread: [20260317-report-snapshot-followup-retrospective](../threads/20260317-report-snapshot-followup-retrospective.md)

## 背景

`20260316-report-daily-scheduler-snapshots` 建立了报表按日固化的基础模式，但后续三轮追修说明，光有“每日快照”这个框架还不够，至少还有四类约束必须明确：

1. 订单金额总额、三方支付总额、外卖平台拆分不是同一层语义
2. 商品汇总是否允许再次回查原始交易表
3. 门店型报表是否允许按全量门店一次生成
4. 汇总键到底应该保留哪些业务维度

如果这些约束不写成 decision，后续很容易再次被“直觉优化”改坏。

## 选项

### A. 延续临时性实现
- 优点: 局部改动快，遇到问题哪里炸补哪里
- 缺点: 容易把语义不同的金额继续混存；汇总和明细各自回查源表，口径漂移；任务继续膨胀成全门店大查询；聚合键由实现者临时拍板

### B. 把报表 follow-up 约束显式固化
- 优点: 数据模型、调度粒度、汇总来源和分组语义都有统一约束；后续 review 有明确判断基准
- 缺点: 需要接受部分规则不是“通用技术最优”，而是服从当前业务定义

## 结论

选 **B**，并固定以下约束：

### 1. 金额语义拆分约束
- `OrderSaleSummary.Amount` 表示订单金额汇总 JSON
- `OrderSaleSummary.ThirdPartyAmount` 表示三方支付总额
- 第三方平台拆分单独存 `OrderSaleSummary.ThirdPartyPlatform` JSON
- 后续新增平台继续扩展 JSON，不再回退成多个平铺标量列

### 2. 汇总来源约束
- 如果明细快照已存在，汇总优先基于明细快照聚合
- `ProductSaleSummary` 直接基于 `ProductSaleDetail` 生成，不再重新查询 `order_products`

### 3. 调度粒度约束
- 门店型日报快照任务优先按门店 fan-out
- usecase 的存在性校验和源数据查询按 `business_date + storeID` 收敛，避免全量门店单次大查询

### 4. 分组键约束
- 分组键必须由业务语义决定，不能只按技术主键或只按展示字段做一刀切约束
- 对当前 `OrderSaleSummary`，`StoreName` 参与统计口径，因此同一 `StoreID` 当天改名后应保留两条汇总；实现上以 `storeID + storeName` 作为聚合键

## 后果

- 以后再改报表字段时，先判断是否是“总额”和“分桶”两层语义；不要把不同口径揉进同一字段
- 以后新增门店型统计任务时，默认先做门店 fan-out，而不是直接写全店批处理
- 以后 review 报表汇总逻辑时，必须先确认业务是否要求保留名称、渠道、税名等维度，不能机械主张“只按 ID 合并”
- 若未来业务明确要求“同店当天改名也只保留一条订单汇总”，那将是新的业务决策，需要新 thread/decision 明确替换本结论