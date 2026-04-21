# Decision 002: 挂账模块数据模型设计

> 状态: accepted
> 日期: 2026-03-05
> 关联 Thread: [20260305-charge-module](../threads/20260305-charge-module.md)

## 背景

挂账模块需要设计三张核心表（客户、消费记录、还款单）的数据模型。涉及三个关键设计点：
1. 客户的门店适用范围如何存储
2. 消费记录是否需要关联门店表
3. 业务编号如何生成

## 选项

### 门店适用范围

#### A. 布尔字段 `all_stores`
- 优点: 简单直观
- 缺点: 只能表达「全部」或「部分」，无法扩展到「排除指定门店」等模式

#### B. 枚举字段 `accept_store_type`（all / partial）
- 优点: 可扩展，未来可添加 exclude 等值；语义更清晰
- 缺点: 略增复杂度

### 门店关联存储

#### A. M2M 中间表
- 优点: 标准关系型设计，可反查
- 缺点: 仅需整体读写场景下额外 JOIN 开销大

#### B. JSON 列 `accept_store_ids`
- 优点: 读写简单，无需中间表；MySQL `JSON_CONTAINS` 支持查询
- 缺点: 无法建索引优化查询，不支持反查

### 消费记录与门店

#### A. 通过 edge 关联 Store 表
- 优点: 数据一致性强（门店改名自动生效）
- 缺点: 列表查询需 JOIN，历史消费记录门店名称会随改名而变

#### B. 冗余存储 `store_name`
- 优点: 查询快，历史数据保留消费时的门店名（符合业务语义）
- 缺点: 门店改名后新旧记录不一致（这恰好是期望行为）

## 结论

- **门店适用范围**：选 B — `accept_store_type` 枚举。查询条件：`accept_store_type = 'all' OR JSON_CONTAINS(accept_store_ids, storeID)`。
- **门店关联存储**：选 B — JSON 列。门店 ID 列表只需整体读写，不需反查，数量有限（几十个门店）。
- **消费记录门店**：选 B — 冗余 `store_name`。去除 store edge，消费记录不再 JOIN 门店表。符合「挂账记录反映消费时刻的店铺名称」的业务语义。
- **业务编号**：在 Handler 层通过 IncrSequence / DailySequence 生成，通过 params 传入 UseCase，保持 UseCase 不依赖序列基础设施。

## 后果

- `ChargeCustomer` 的 `accept_store_type` 为可扩展枚举，新增门店适用模式只需加枚举值 + 调整 buildFilterQuery
- `ChargeRecord` 不再有 store edge，所有涉及门店名称的查询直接读 `store_name` 字段
- 消费记录创建时**必须同时传入** `store_name`、`charge_no`、`order_no`（由调用方负责）
- 编号生成依赖 Redis 序列服务，序列 key 需在 `domain/seq.go` 统一管理
- `accept_store_ids` 的 JSON 查询性能在大数据量下可能成为瓶颈，但当前门店规模（< 100）不构成问题
