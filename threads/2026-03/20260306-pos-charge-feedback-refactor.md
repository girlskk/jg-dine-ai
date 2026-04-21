# Thread: POS 挂账模块反馈重构（职责拆分）

> 日期: 2026-03-06
> 标签: #pos #charge #refactor #repository #usecase

## Context
用户反馈当前实现职责边界不清晰：
1) `findChargeCustomerByCode` 通过列表查询客户，不符合 `customer_code` 唯一索引语义；应下沉仓储 `FindByCode`。
2) `ChargeRecordInteractor` 不应返回 `ChargeCustomers`，客户列表应由 `ChargeCustomerInteractor` 负责。
3) POS 中 `ChargeRecordHandler` 不应承载客户列表接口，应拆分 `ChargeCustomerHandler`。

## 关键决策
1. 在 `ChargeCustomerRepository` 增加 `FindByCode(ctx, customerCode)`，按唯一键查单条。
2. 从 `ChargeRecordInteractor` 删除 `GetAvailableChargeCustomers`，保持挂账记录职责纯净。
3. POS API 拆分资源 handler：
   - `ChargeCustomerHandler` 负责 `GET /charge_customer`
   - `ChargeRecordHandler` 仅负责 `POST /charge_record`

## 最终方案
- Domain:
  - `domain/charge_customer.go` 新增仓储接口 `FindByCode`。
  - `domain/charge_record.go` 删除 `GetAvailableChargeCustomers`。
- Repository:
  - `repository/charge_customer.go` 新增 `FindByCode` 实现。
- UseCase:
  - `usecase/chargerecord/charge_record.go` 改为调用 `ChargeCustomerRepo.FindByCode`。
  - 删除 `findChargeCustomerByCode` 辅助函数与客户列表方法。
- API (POS):
  - 新增 `api/pos/handler/charge_customer.go`。
  - 新增 `api/pos/types/charge_customer.go`。
  - `api/pos/handler/charge_record.go` 删除 available customers 路由与逻辑。
  - `api/pos/posfx/posfx.go` 注册 `NewChargeCustomerHandler`。

## 踩坑与偏差
- 重构时误删了 `usecase/chargerecord/charge_record.go` 中 `upagination` 导入，导致编译失败；已修复并重新验证。

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
