# Thread: tax fee 重构为品牌固定四类目录

> 日期: 2026-04-10
> 标签: #tax-fee #backend #store #frontend #eventcore #ent #acceptance #reflect

## Context
旧税费模块允许品牌和门店分别做任意 CRUD，数据层还保留了 `store_id`、`name`、启用禁用等旧设计字段。这和实际业务约束冲突：商户所在国家的税费类型只有固定四类，且门店不应单独配置。

本次任务要求把税费收敛为品牌维度固定目录：零税、免税、6%税、8%税；API 只保留 list；路由统一改成 `/tax-fee`；新建品牌默认初始化四条；旧表无用字段删除。

## 关键决策
1. 不做“弱约束 CRUD”，直接改成固定目录模型。
   如果只是限制前端不让新增编辑，底层 repository/schema 仍然保留自定义税费和门店维度，后续任何入口都还能继续写脏数据，设计没有真正被修正。
2. 门店税费配置整体删除，所有消费端统一读取品牌税费。
   `store_id` 继续存在只会让历史歧义长期保留；应让商品、分类、口味、导入模板、报表等依赖点全部按 merchant tax fee 收口。
3. 品牌默认税费初始化放在 merchant created 事件上；开发阶段不保留历史兼容迁移逻辑。
   实际落地时，旧税费表的历史数据直接清空，避免在应用启动链路里长期背着一次性迁移代码。新表只保留固定目录必需字段，老别名和旧维度数据都不再兼容。
4. `OrderTaxRate` 需要持久化 `tax_code_type` 快照。
   只保存 `tax_rate_id` 和显示名不够稳，订单快照还要保留固定税种代码，避免后续报表和导出只能依赖外键回查或模糊字符串判断。

## 最终方案
- domain/repository/usecase：税费模型改为固定 `TaxCodeType` 目录，支持 `ZRL`、`ZRE`、`SR6`、`SR8`；税费名称固定为 `SST_S0`、`SST_Exempt`、`SST_S6`、`SST_S8`；`DisplayName` 和 `DecimalRate` 直接由 `TaxCodeType` 驱动；移除 `TaxRateType` 和旧别名兼容逻辑。
- ent schema：`tax_fees` 删除 `store_id`、旧类型字段和启用相关字段，保留品牌维度所需的 `created_at + updated_at + name + tax_code_type + tax_rate + merchant_id`，并将唯一性收敛到 `merchant_id + tax_code_type + deleted_at`。时间字段继续复用共享 `TimeMixin`，不在 tax fee schema 内单独定义。
- eventcore：品牌创建只执行 `EnsureMerchantDefaults`，门店创建不再初始化税费。`EnsureMerchantDefaults` 先按 merchant 查询现有税费；只要缺项或存在与固定目录不一致的数据，就由 usecase 统一删除该 merchant 的全部税费，再调用 repository 批量写回四条默认记录。
- backend/store/frontend：handler 和 types 全部收缩为 list-only，路由从 `/tax_fee` 统一切到 `/tax-fee`。
- 依赖模块：分类、商品、口味、导入模板、税费统计、订单创建、订单销售汇总改为按品牌税费读取和校验；订单税率快照新增 `tax_code_type`，6%/8% 汇总按 `TaxCodeType` 判断而不是按数值税率比较。
- 数据处理：开发阶段直接清空旧 `tax_fees` 历史数据，再用新 schema 和品牌初始化逻辑重建四条固定税费。
- 验证：`GET /api/v1/tax-fee` 返回四条固定税费，`total=4`，名称为 `SST_S0/SST_Exempt/SST_S6/SST_S8` 且按 `created_at` 稳定排序；新建品牌初始化四条；新建门店不再新增税费。

## 踩坑与偏差
1. 订单快照里不能只存展示名。
   名称已经被业务改成 `SST_S0/SST_Exempt/SST_S6/SST_S8`，如果没有 `tax_code_type`，后续报表只能拿字符串猜语义，脆弱而且难审计。
2. 开发期不要把一次性脏数据兼容沉淀成长期启动逻辑。
   这类迁移代码一旦进入 `bootstrap/db`，后面每次启动都要继续背负复杂分支，收益远低于直接清空旧表。
3. 本地 compose 日志容易误判根因。
   如果只看 `docker compose logs --tail`，看到的通常是重启后的 Dapr 连接超时，而不是第一次 schema 或数据错误。
4. “继续用共享时间 mixin”与“按 `created_at` 排序稳定”之间有直接冲突，不能装作没看见。
   `tax_fees.created_at` 沿用共享 mixin 时是秒级时间，若整批写入四条默认税费就会落成相同秒值。最终做法不是在 schema 上另开特例，而是在批量创建时显式给四条默认记录写入递增的秒级 `created_at/updated_at`，把顺序问题留在写入侧一次性解决，而不是读的时候再补救。

## 可复用模式
- 任何“旧门店维度配置收敛到品牌维度”的重构，都要同时覆盖 schema、事件初始化、依赖 usecase 和订单快照字段，缺一项都会留下半旧半新的状态。
- 开发期尚未上线的模型重构，优先删掉一次性兼容逻辑和旧数据，而不是把迁移补丁永久埋进启动流程。
- 本地 `eventcore` 重启问题，先用完整 `docker logs <container>` 搜 `OnStart hook failed|auto migration failed`，再决定是否真的是 Dapr 问题。