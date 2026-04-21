# 短信模块知识

> 来源 threads: sms-template-rule-refactor, sms-template-merchant-biztype-uniqueness, eventcore-local-startup-migration-debug

## 模板唯一性

- 唯一性收敛到 `merchant_id + biz_type`（数据库唯一索引 + repository 约束错误兜底）
- 同一商户下模板名称也必须唯一，但只在代码层校验，不下沉数据库唯一索引
- 更新时禁止修改 `biz_type`。如果前端传了不同值直接返回参数错误
- 每个 merchant 下每个 biz_type 只能保留一条记录，不再依赖"启用互斥"

## 固定字段

- `SMSType` 固定为 `SMSTypeNotify`，`status` 固定为 `SMSTemplateAuditStatusApproved`
- usecase 写入时固定值，repository 写入时再兜底

## 发送查找

- 发送查找直接按 `merchant_id + biz_type` 获取品牌模板，不做 store/system fallback
- 模板不存在 / 模板禁用 / 模板内容为空分开报错

## 启用/禁用

- 启用/禁用只改当前记录，不做"启用一个禁用其他"的编排
- backend 新增 `enable/disable` 接口走 `SimpleUpdate`

## 唯一索引迁移

- `merchant_id + biz_type + deleted_at` 唯一索引迁移时，本地旧数据必须先去重，否则自动迁移 1062 报错

## 设计教训

- 当"单启用"本质上是在模拟"唯一记录"时，应直接收敛为数据唯一约束
- 如果一个字段定义了模板身份或下游查找键（如 `biz_type`），编辑接口就不该允许修改
