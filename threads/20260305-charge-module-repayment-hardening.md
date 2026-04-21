# Thread: 挂账模块后续修订（还款与筛选强化）

> 日期: 2026-03-05
> 标签: #charge #refactor #i18n #repository #security #followup

## Context

在挂账模块首版落地后，对客户/消费记录/还款单进行一轮后续修订，目标是补齐数据冗余字段、强化还款校验、统一 i18n 错误码，以及修复筛选与并发更新细节，确保线上行为稳定可追踪。

## 关键决策


1. **还款校验错误统一走领域错误 + errcode + i18n**
   将还款流程中的业务异常由临时字符串错误改为领域错误常量，Handler 统一映射 errcode，再由中间件做多语言翻译。

2. **额度变更使用数据库原子更新**
   `AddUsedAmount` / `SubUsedAmount` 改为 SQL 表达式更新，避免读改写带来的并发竞争窗口。

3. **门店筛选统一约束**
   `ChargeCustomerRepository.buildFilterQuery` 在 `store_id` 条件下固定采用：
   `accept_store_type = all OR accept_store_ids contains store_id`。

## 最终方案

- Ent Schema 调整：
  - `ent/schema/chargerecord.go`
  - `ent/schema/chargerepayment.go`
- Domain 调整：
  - `domain/charge_customer.go`
  - `domain/charge_record.go`
  - `domain/charge_repayment.go`
- Repository 调整：
  - `repository/charge_customer.go`
  - `repository/charge_record.go`
  - `repository/charge_repayment.go`
- UseCase 调整：
  - `usecase/chargecustomer/charge_customer.go`
  - `usecase/chargecustomer/charge_customer_create.go`
  - `usecase/chargecustomer/charge_customer_update.go`
  - `usecase/chargerepayment/charge_repayment_create.go`
- API/Types 与错误映射：
  - `api/backend/types/charge_customer.go`
  - `api/backend/types/charge_record.go`
  - `api/backend/types/charge_repayment.go`
  - `api/backend/handler/charge_customer.go`
  - `api/backend/handler/charge_record.go`
  - `api/backend/handler/charge_repayment.go`
  - `pkg/errorx/errcode/error_code.go`
  - `etc/language/zh-CN.toml`
  - `etc/language/en-US.toml`

## Verify

- 已执行 `go generate ./ent`，代码生成通过。
- 已执行 `go build ./...`，全量编译通过。
- 已执行 `go vet ./repository/... ./usecase/... ./api/backend/...`，未发现问题。

## 踩坑与偏差

1. `ChargeRecord.charge_repayment_id` 由 nillable 调整为 optional 后，关联类型需同步从指针语义切换到值语义，避免上层遗漏适配。
2. 仅在 Request Types 增加筛选字段不够，Handler 组装 Domain Filter 也必须同步透传，否则查询行为与文档不一致。

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
