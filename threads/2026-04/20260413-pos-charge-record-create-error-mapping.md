# Thread: POS 挂账创建错误映射补全

> 日期: 2026-04-13
> 标签: #pos #charge #error-handling #reflect

## Context

POS `POST /charge-record` 通过 `domain.CreateChargeRecord` 创建挂账记录，但 handler 的 `checkErr` 只覆盖了部分显式错误。实际调用链里还会经过 `UserRoleRepo.FindOneByUser` 与 `VerifyUserRoleCanLogin`，因此可能返回 `ErrUserRoleNotExists`、`ErrRoleNotExists`、`ErrRoleDisabled`、`ErrLoginChannelNotAllowed`、`ErrUserDisabled` 等自定义业务错误。未显式映射时，这些错误会退化为通用分支，无法满足“CreateChargeRecord 返回的自定义 error 都要在 checkErr 中处理”的要求。

## 关键决策

1. 先沿 `CreateChargeRecord -> ChargeAccount.Pay -> VerifyUserRoleCanLogin` 全链路梳理错误来源，而不是只看 `charg_pay.go` 表层分支。
2. 只修改 `api/pos/handler/charge_record.go` 的错误映射，复用现有 `errcode`，不改 domain 逻辑与 API 契约。
3. HTTP 状态码按 REST 语义重新分层：资源不存在用 `404`，主体/权限问题用 `403`，资源状态冲突用 `409`，参数非法用 `400`；`errcode` 继续复用现有业务码。

## 最终方案

- 在 `api/pos/handler/charge_record.go` 的 `checkErr` 中新增以下显式映射：
  - `ErrUserRoleNotExists -> 403 USER_ROLE_NOT_EXISTS`
  - `ErrRoleNotExists -> 403 ROLE_NOT_EXISTS`
  - `ErrRoleDisabled -> 403 ROLE_DISABLED`
  - `ErrUserDisabled -> 403 USER_DISABLED`
  - `ErrLoginChannelNotAllowed -> 403 LOGIN_CHANNEL_NOT_ALLOWED`
- 同时按 REST 语义调整已有映射：
  - `ErrChargeCustomerNotExists -> 404`
  - `ErrStoreNotExists -> 404`
  - `ErrChargeAccountCreditInsufficient -> 409`
  - `ErrChargeCustomerNotInStore -> 409`
  - `ErrChargeAmountInvalid -> 400`
  - `ErrCashierUserNotExists -> 403`
  - `ErrOperationNotAllowed -> 403`

## 踩坑与偏差

- 表面看 `CreateChargeRecord` 只依赖挂账客户、门店、收银员和额度校验，实际还隐含角色装配与登录渠道校验。只看当前函数体会漏掉深层业务错误。
- 当前工作区存在其他未提交修改，与本次任务无关，未做回退或整理。

## 可复用模式

- 只要 handler 入口调用的 domain/service 内部会走 `VerifyUserRoleCanLogin` 或 `UserRoleRepo.FindOneByUser`，就必须把 `ErrUserRoleNotExists`、`ErrRoleNotExists`、`ErrRoleDisabled`、`ErrLoginChannelNotAllowed` 视为这条业务链的实际错误面，而不是依赖通用 `IsNotFound` / `IsParamsError` 兜底。
- 对已有 `errcode` 的业务错误，优先返回专用错误码，不要退化成通用 `FORBIDDEN` 或 `INVALID_PARAMS`。