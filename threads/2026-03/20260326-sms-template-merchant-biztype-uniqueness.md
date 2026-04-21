# Thread: 短信模板收敛为商户内业务类型唯一

> 日期: 2026-03-26
> 标签: #sms #template #backend #repository #domain #workflow

## Context
短信模板原先还保留了三套旧语义：
1. 发送时按 store -> brand -> system 回退查模板。
2. 业务规则是“同 biz_type 只能启用一条”，因此 usecase 在启用时会禁用其他模板。
3. 创建/更新冲突校验仍然按模板名称而不是按商户 + biz_type。

这和当前需求冲突。现在模板来源只有品牌模板，没有 system 默认模板，也没有 store 模板；每个 merchant 下每个 biz_type 只能保留一条记录，不再依赖“启用互斥”来近似表达唯一性。

## 关键决策
1. 唯一性收敛到 merchant + biz_type。
   create/update 改为校验同一商户下同 biz_type 是否已存在，并保留数据库唯一索引与 repository 约束错误兜底，避免并发下出现双写。
2. 名称唯一性也限定在 merchant 作用域内。
  同一商户下模板名称也必须唯一，但这条约束只在代码层校验，不下沉数据库唯一索引；名称重复不会破坏发送主链路，不值得为此增加数据库约束复杂度。
3. 更新时禁止修改 `biz_type`。
  `biz_type` 属于模板身份的一部分，不允许在编辑时变更；如果前端传了不同值，直接按参数错误返回。
4. 发送查找走 repository 直查品牌模板。
   在 domain `FindTemplateForSend` 中直接调用 `FindByMerchantAndBizType`，不再做 store/system fallback，也不再依赖 status。
5. 启用/禁用只改当前记录。
   由于同一商户同一 biz_type 现在只允许一条记录，`SimpleUpdate` 不再做“启用一个、禁用其他”的 usecase 编排。
6. API 显式暴露 enable/disable。
   backend 新增 `/sms/template/{id}/enable` 与 `/sms/template/{id}/disable`，统一走 `SimpleUpdate`。

## 最终方案
- Domain
  - `domain/sms_template.go` 新增 `ErrSMSTemplateBizTypeExists`、`ErrSMSTemplateDisabled` 和 `FindByMerchantAndBizType` 仓储接口。
  - `domain/sms.go` 的发送逻辑改为要求 `MerchantID`，并在查模板时只按 merchant + biz_type 获取；模板不存在和模板禁用分开报错。
- Repository
  - `repository/sms_template.go` 新增 `FindByMerchantAndBizType`。
  - `Create` / `Update` 对数据库唯一约束冲突映射为 `ErrSMSTemplateBizTypeExists`。
- UseCase
  - `usecase/smstemplate/*.go` 去掉“禁用其他启用模板”的旧编排，改为校验商户下 biz_type 唯一和 name 唯一。
  - `Update` 明确禁止修改 `biz_type`。
  - `SimpleUpdate` 仅修改当前模板的 enabled 状态。
- Ent Schema
  - 仅保留 `merchant_id + biz_type + deleted_at` 唯一索引；`name` 唯一性不落数据库。
- Domain
  - `FindTemplateForSend` 现在只返回“可使用模板”，模板不存在、模板禁用、模板内容为空都在函数内部判定，外层不再重复判断可用性。
- Backend API
  - `api/backend/handler/sms_template.go` 新增 enable/disable 接口，并把 create/update 的冲突错误改成 biz_type 维度。

## 踩坑与偏差
1. 仓库中还有其他未提交改动和若干无关 repository 失败测试，不能拿整包运行时测试结果判断这次改动是否正确。
2. 为避免测试噪音，最终用 `go test ... -run TestDoesNotExist` 做编译级验证，只确认受影响包可编译。
3. 名称唯一是否需要数据库兜底后来被否决。用户明确指出名称重复对主链路影响有限，代码层校验已经够用，继续加索引是在抬高维护成本而不是提升关键可靠性。

---

> 可复用模式与反思已提取至 [knowledge/sms.md](../knowledge/sms.md)，按需查阅。
