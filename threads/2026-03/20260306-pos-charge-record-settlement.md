# Thread: POS 挂账接口落地（并入 chargerecord）

> 日期: 2026-03-06
> 标签: #pos #charge #chargerecord #ent #api

## Context
POS 端需要新增两个挂账接口：查询门店可挂账客户列表、结算时创建挂账消费记录。用户明确要求挂账写操作必须并入 `chargerecord` 现有模块，不能新增独立操作模块；同时需要把收银员信息（ID、名称）落库到 `charge_record`。

## 关键决策
1. 将“完成挂账”能力扩展到 `domain.ChargeRecordInteractor` / `usecase/chargerecord`，不新增独立 `chargeoperation` 领域。
2. 在 `ent/schema/chargerecord.go` 增加 `cashier_id`、`cashier_name` 字段，并在 repository create/convert 路径完整透传。
3. POS handler 仅依赖收银员 token 鉴权，从 token 提取 `merchant_id`、`store_id`、`cashier(id/name)`，不对挂账客户做登录态校验。
4. 写操作在事务内完成：订单存在性校验、挂账客户可用门店校验、额度校验、创建消费记录、累加已用额度。

## 最终方案
- API 层新增 `GET /charge_record/available_customers` 与 `POST /charge_record`，并在 `api/pos/posfx/posfx.go` 注册 handler。
- Domain 层在 `domain/charge_record.go` 新增创建参数结构、错误定义、interactor 方法，并扩展 `ChargeRecord` 实体收银员字段。
- UseCase 层在 `usecase/chargerecord/charge_record.go` 增加可挂账客户查询和创建挂账逻辑。
- Repository 层在 `repository/charge_record.go` 增加 cashier 字段写入与回填。
- Ent 层更新 `chargerecord` schema 和对应生成代码（字段、mutation、migrate schema、runtime validator）。

## 踩坑与偏差
- 早期实现曾新增 `chargeoperation` 模块，偏离用户“不要新加模块”的约束，随后回收并迁回 `chargerecord`。
- 初次 ent 生成带出了大量无关文件差异，后续将改动收敛到 `chargerecord` 相关最小生成文件集，降低回归风险。

---

> 可复用模式与反思已提取至 [knowledge/charge.md](../knowledge/charge.md)，按需查阅。
