# Thread: 挂账模块（Charge Account Module）

> 日期: 2026-03-05
> 标签: #charge #cross-layer #new-module #code-generation

## Context

品牌后台需要挂账功能：商户可为客户（个人/企业）开设挂账账户，客户消费时可挂账，后续统一还款。模块涉及三张核心表：挂账客户（ChargeCustomer）、消费记录（ChargeRecord）、还款单（ChargeRepayment）。

从零搭建，覆盖 Domain → Ent Schema → Repository → UseCase → API Handler 全链路。

## 关键决策

1. **门店适用范围用枚举代替布尔** — 最初设计为 `all_stores bool`，后改为 `accept_store_type` 枚举（all/partial），为未来扩展"排除指定门店"模式预留空间。详见 [Decision 002](../decisions/002-charge-accept-store-type.md)。

2. **门店关联用 JSON 列代替 M2M** — `accept_store_ids` 存储为 JSON 数组而非中间表。查询时用 MySQL `JSON_CONTAINS` + `accept_store_type=all` 的 OR 条件。理由：门店 ID 列表只需整体读写、不需反查、数量有限。

3. **消费记录冗余门店名称** — `ChargeRecord` 不再关联 store edge，改为冗余存储 `store_name`。避免列表查询时 JOIN store 表，以查询效率换取数据一致性成本（门店改名后历史记录不变，这恰好是期望行为）。

4. **编号在 Handler 层生成** — 参考 Store 模块的 `generateStoreCode`，三种业务编号（customer_code / charge_no / repayment_no）在 API Handler 层生成，通过 params 传入 UseCase。保持 UseCase 不依赖序列基础设施。

5. **消费记录仅有 Repo 接口，无写入用例** — `ChargeRecordInteractor` 仅暴露查询。记录创建发生在订单支付流程中（跨模块），通过直接调用 `ChargeRecordRepo().Create` 完成。

## 最终方案

### 文件清单

| 层      | 文件                                      | 职责                                                                                                   |
| ------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Domain  | `domain/charge_customer.go`               | 客户实体、枚举（CustomerType/AcceptStoreType）、Repository/Interactor 接口                             |
| Domain  | `domain/charge_record.go`                 | 消费记录实体、状态枚举（unpaid/paid）、Repository/Interactor 接口                                      |
| Domain  | `domain/charge_repayment.go`              | 还款单实体、Repository/Interactor 接口                                                                 |
| Domain  | `domain/seq.go`                           | 序列常量：`ChargeCustomerSequenceKey`、`DailySequencePrefixChargeNo`、`DailySequencePrefixRepaymentNo` |
| Schema  | `ent/schema/chargecustomer.go`            | customer_code/accept_store_type/accept_store_ids(JSON)                                                 |
| Schema  | `ent/schema/chargerecord.go`              | charge_no/order_no/store_name（去除 store edge）                                                       |
| Schema  | `ent/schema/chargerepayment.go`           | repayment_no/operator_id                                                                               |
| Repo    | `repository/charge_customer.go`           | JSON_CONTAINS 门店过滤、AcceptStoreType 枚举查询                                                       |
| Repo    | `repository/charge_record.go`             | 列表查询 eager load ChargeCustomer（不再 load Store）                                                  |
| Repo    | `repository/charge_repayment.go`          | GetDetail eager load ChargeCustomer + ChargeRecords                                                    |
| UseCase | `usecase/chargeaccount/` (4 files)        | 客户 CRUD，事务内重名检查                                                                              |
| UseCase | `usecase/chargerepayment/` (2 files)      | 还款单创建（校验金额、批量更新记录状态、扣减已用额度）                                                 |
| UseCase | `usecase/chargerecord/` (1 file)          | 消费记录列表查询                                                                                       |
| Handler | `api/backend/handler/charge_customer.go`  | CRUD + 列表，注入 IncrSequence + MerchantInteractor 生成 customer_code                                 |
| Handler | `api/backend/handler/charge_repayment.go` | 创建 + 详情 + 列表，注入 DailySequence + ChargeCustomerInteractor 生成 repayment_no                    |
| Handler | `api/backend/handler/charge_record.go`    | 列表查询                                                                                               |
| Types   | `api/backend/types/charge_*.go` (3 files) | 请求/响应结构体                                                                                        |

### 编号生成规则

| 编号            | 格式                                    | 序列机制                                       | 生成位置                                     |
| --------------- | --------------------------------------- | ---------------------------------------------- | -------------------------------------------- |
| `customer_code` | `{品牌编号后4位}{yymmdd}{0001递增}`     | IncrSequence（全局递增，prefix 区分品牌+日期） | `ChargeCustomerHandler.generateCustomerCode` |
| `charge_no`     | `{门店编号后8位}{yymmdd}{0001每日递增}` | DailySequence（key 不含 storeID，每日重置）    | 待接入订单流程                               |
| `repayment_no`  | `{customerCode}{0001每日递增}`          | DailySequence（key 不含 customerID，每日重置） | `ChargeRepaymentHandler.generateRepaymentNo` |

### 还款流程核心逻辑

```
创建还款单 → 校验客户存在 → 查询消费记录 → 校验全部未还款且属于该客户
→ 计算总额 → receivedAmount = totalCharge - discount
→ 事务内：创建还款单 → 批量更新记录状态为 paid → 扣减客户已用额度
```

## 踩坑与偏差

1. **ent generate 未生效** — 首次 `go generate ./ent` 无输出但未实际更新生成文件。改用完整命令 `go run -mod=mod entgo.io/ent/cmd/ent generate --feature ... ./ent/schema` 解决。
2. **GetMerchant 签名遗漏 User 参数** — Handler 中调用 `MerchantInteractor.GetMerchant(ctx, id)` 编译失败，该接口需要第三个 `User` 参数。
3. **AcceptStoreType 的 ent 枚举**使用 `GoType(domain.AcceptStoreType(""))` 注册，生成的字段类型直接是 `domain.AcceptStoreType`，repo 中的 cast `domain.AcceptStoreType(ec.AcceptStoreType)` 虽冗余但无害。
4. **all_stores → accept_store_type 迁移** — 枚举设计比布尔更灵活，但需确保 `buildFilterQuery` 中的 OR 条件同步更新（`AllStoresEQ(true)` → `AcceptStoreTypeEQ(domain.AcceptStoreTypeAll)`）。

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
