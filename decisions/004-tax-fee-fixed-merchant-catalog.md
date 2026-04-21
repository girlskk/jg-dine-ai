# Decision 004: 税费固定为品牌维度四类目录

> 状态: accepted
> 日期: 2026-04-10
> 关联 Thread: [20260410-tax-fee-fixed-catalog](../threads/20260410-tax-fee-fixed-catalog.md)

## 背景
旧税费模型允许品牌和门店分别维护任意税费记录，并暴露完整 CRUD/启用禁用接口。这导致税费既不是稳定的国家税制目录，也不是清晰的品牌配置：
- 门店维度会复制出大量重复税费数据
- 历史自定义税费会破坏商品、报表、导入模板等依赖点的一致性
- API 语义和真实业务约束不一致

业务最终确认：当前税费只有四类固定类型，且门店不单独配置。

## 选项
### A. 保留税费 CRUD，只在前端限制创建和编辑
- 优点: 改动小，接口兼容成本低
- 缺点: 旧 repository/schema 仍允许写脏数据；门店维度和自定义税费不会真正消失

### B. 保留品牌固定目录，但允许门店 override
- 优点: 兼顾统一目录和局部灵活性
- 缺点: 继续保留 `store_id` 维度和复制数据问题；依赖模块仍要处理两层来源

### C. 税费收敛为品牌维度固定四类目录，门店仅复用
- 优点: 领域边界清晰；商品/分类/口味/报表统一只认一套税费；能彻底删除旧 store 维度配置和自定义 CRUD 语义
- 缺点: 影响面跨 domain/repository/usecase/api/eventcore，订单快照也要一起补字段

## 结论
选择 C。

税费定义为品牌维度固定目录，只允许以下四个 code：
- `ZRL`：名称 `SST_S0`
- `ZRE`：名称 `SST_Exempt`
- `SR6`：名称 `SST_S6`
- `SR8`：名称 `SST_S8`

新建品牌默认初始化四条；门店不单独配置；对外 API 仅保留 list；依赖方统一按品牌税费引用；订单税率快照必须落 `tax_code_type`。默认税费初始化发现已有数据缺项或脏数据时，由 usecase 先删除该 merchant 的全部税费，再批量重建四条默认记录。

## 后果
- `tax_fees` 表删除旧的 `store_id`、启用禁用和旧类型字段，保留固定目录所需列，其中 `name` 需要持久化入库。
- `tax_fees` 继续复用共享时间 mixin；为保证四条默认税费按 `created_at` 稳定排序，批量写入时必须显式写入递增的秒级时间值，不能指望默认时间戳恰好给出正确顺序。
- 所有 handler 路由统一改为 `/tax-fee`，取消 create/update/delete/detail/enable/disable。
- `tax_fees` 表字段统一为 `tax_code_type`，移除 `tax_code` 和 `TaxRateType`。
- 开发阶段旧 `tax_fees` 数据直接清空，不保留运行时历史迁移逻辑。
- 后续任何新增需求如果试图恢复“自定义税费”或“门店 tax fee override”，都应先显式更新本 decision，而不是绕过现有模型偷偷加字段或接口。