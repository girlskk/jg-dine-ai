# Thread: 短信模板规则收敛与分层纠偏

> 日期: 2026-03-10
> 标签: #sms #template #usecase #repository #refactor #workflow

## Context
短信模板规则调整需求：
1) `SMSType` 暂时固定为 `SMSTypeNotify`。
2) 模板不再走审核流，`status` 固定为 `SMSTemplateAuditStatusApproved`。
3) 同一 `biz_type` 仅允许一条启用模板，启用 A 时禁用同 `biz_type` 其他模板。

执行过程中出现一次分层偏差：最初把“启用 A 禁用其他”的编排写到了 `repository`，随后按反馈回收至 `usecase`。

## 关键决策
1. 固定字段值采用双层兜底：
   usecase 写入时固定值，repository 写入时再兜底，避免绕过 usecase 的路径造成脏数据。
2. 启用互斥规则放在 usecase 事务编排：
   repository 保持 CRUD 和错误映射，不承载跨记录业务规则。
3. 保留审核相关类型定义但停止生效：
   避免一次性删除影响兼容性，后续再做字段与文档清理。

## 最终方案
- UseCase 层
  - `usecase/smstemplate/sms_template_create.go`: 创建时固定 `notify + approved`；若 `enabled=true`，禁用同 `biz_type` 其他启用模板。
  - `usecase/smstemplate/sms_template_update.go`: 更新时固定 `notify + approved`；若 `enabled=true`，禁用同 `biz_type` 其他启用模板。
  - `usecase/smstemplate/sms_template_simple_update.go`: 忽略 `status` 变更；启用时执行同 `biz_type` 互斥。
  - `usecase/smstemplate/sms_template.go`: 新增 `disableOtherEnabledTemplates` 编排辅助函数。
- Repository 层
  - `repository/sms_template.go`: 仅保留数据写入和映射；移除启用互斥业务编排函数。
  - 创建/更新持久化时固定写入 `notify + approved` 作为兜底。
- Ent Schema
  - `ent/schema/smstemplate.go`: `status` 默认值调整为 `approved`。

## 踩坑与偏差
1. 偏差：把“启用互斥”先写进了 `repository`，违反“UseCase 负责编排，Repository 负责持久化”的分层约束。
2. 修正：将互斥逻辑迁移到 `usecase` 事务中，repository 回归纯数据访问。

---

> 可复用模式与反思已提取至 [knowledge/sms.md](../knowledge/sms.md)，按需查阅。
