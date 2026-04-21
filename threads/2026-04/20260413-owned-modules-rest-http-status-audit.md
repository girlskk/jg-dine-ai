# Thread: 负责模块 REST HTTP 状态码审计

> 日期: 2026-04-13
> 标签: #rest #http-status #handlers #audit #reflect

## Context

用户要求对自己负责的模块逐个检查 handler 中是否存在不符合 REST 风格的 HTTP 状态码，并直接修正。范围覆盖 `additional_fee`、`charge_*`、`department`、`device`、`dine_table`、`ledger_account*`、`login_log`、`merchant`、`operate_log`、`order_sale_summary`、`product_sale_*`、`remark`、`role`、`shift_record`、`sms*`、`stall`、`store`、`task`、`tax_fee`、`user` 等模块的多服务 handler 变体。

## 关键决策

1. 先按模块而不是按服务扫描，避免只修 backend 而漏掉 customer/frontend/pos/store 的同名 handler。
2. 先处理“语义无争议”的映射：
   - 资源不存在 `*NotExists/*NotFound -> 404`
  - 唯一性/状态冲突 `*Exists/*Conflict/*Already/*Exceeded/*Lack -> 409`
  - 明确“不能删除 / 不能禁用 / 占用中不可删”语义的规则仍归为 `403`
3. `user` 模块单独处理登录上下文：
   - 认证失败 `UserNotFound / AccountOrPasswordIncorrect -> 401`
   - 账号、商户、渠道、部门、角色等状态阻断 `-> 403`
   - 资源不存在仍保留 `404`
4. 对 grep 扫描中命中的范围外模块（如 `member`、`refund`、`product_*`、`category` 等）不顺手扩散修改，保持本次任务边界可控。

## 最终方案

- 修正了 backend/store/admin/customer/frontend/pos 多个 handler 中的状态码映射，重点包括：
  - `additional_fee`、`charge_customer`、`charge_repayment`、`department`、`device`、`dine_table`、`ledger_account`、`ledger_account_type`、`remark`、`role`、`shift_record`、`stall`、`store`
  - `customer/sms`
  - `user` 模块的 admin/backend/store/pos handler 以及 `domain.CheckBackendUserErr`
- 登录分支显式调整为：
  - `UserNotFound -> 401`
  - `UserDisabled -> 403`
- 共享 helper / checkErr 中补齐：
  - `AccountOrPasswordIncorrect -> 401`
  - `MerchantExpired`、`MerchantDisabled`、`LoginChannelNotAllowed`、`DepartmentDisabled`、`RoleDisabled`、`StoreClosed -> 403`
  - `MerchantNotExists`、`StoreNotExists`、`UserNotExists -> 404`
  - `DepartmentHasUsersCannotDisable/Delete`、`RoleAssignedCannotDisable/Delete`、`StallInUseCannotDelete`、`LedgerAccountTypeHasLedger -> 403`

## Verify

- `go test ./api/backend/handler ./api/store/handler ./api/admin/handler ./api/customer/handler ./api/frontend/handler ./api/pos/handler ./domain` ✅
- 反查目标模块中“`400 + NotExists/Conflict/Forbidden-state`”的可疑命中已清空；剩余 grep 命中均在本次明确排除的非目标模块。 ✅

## 踩坑与偏差

- 第一轮只看 backend/store/admin 不够，实际同模块还存在 customer/frontend/pos 变体，不按模块全量扫就会留下明显不一致。
- `user` 模块不能机械替换：同一个错误在登录场景和 CRUD 场景的 HTTP 语义不同，需要把登录分支单独拎出来处理。
- 这次扫描顺带发现其他范围外模块也有类似历史遗留，但按用户指令未扩散修改。

## 可复用模式

- 批量审计 handler HTTP 状态码时，先按“模块名 across services”列出文件，再用命名规则筛查 `400` 命中，比逐文件人工翻更稳。
- 对共享 `checkErr` / domain helper，要先查调用面；如果同一 helper 同时服务登录和 CRUD，登录语义尽量在 handler 入口单独兜住，避免为了一个上下文把所有调用面都带偏。