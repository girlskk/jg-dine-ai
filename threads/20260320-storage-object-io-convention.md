# Thread: StorageObject 输入输出约束与可空持久化

> 日期: 2026-03-20
> 标签: #storage #repository #api #convention #merchant #store

## Context
本次将 Merchant / Store 的图片字段从数据库直出 string 收敛为 domain `StorageObject` 时，第一轮实现把写接口 DTO 也改成了 `StorageObject`，并在 repository 写库时直接取 `.Key`。用户随后明确两点约束：

1. 写接口前端仍然传 string key，不要把 Create/Update 请求体改成 `StorageObject`。
2. repository 持久化图片 key 时，不能裸取 `.Key`，因为图片字段是非必填，空对象必须被安全处理。

这次问题的边界只落在 merchant/store：它们的图片字段是非必填，repository 持久化时必须先判断是否有 key。product 的图片字段由前置校验保障，不在本次修复范围内；“参考 product”仅表示参考它的整体输入输出模式，不代表可以顺手改 product 模块。

## 关键决策
1. 输入输出分离：写接口 DTO 保持 string key，查询返回值使用 `StorageObject`。
2. domain 层继续统一使用 `StorageObject`，handler 负责把请求中的 string key 转成 `domain.NewStorageObjectFromKey(...)`。
3. repository 写库遵循“可空图片字段先判断再落库”规则：
   - create 场景：有 key 才 `Set...`。
   - update 场景：有 key 则 `Set...`，无 key 且 schema 支持 clear 时显式 `Clear...`。

## 最终方案
- 请求 DTO 保持 string key：
  - `api/admin/types/merchant.go`
  - `api/backend/types/store.go`
  - `api/store/types/store.go`
- handler 在进入 usecase/domain 前执行 string -> `StorageObject` 转换：
  - `api/admin/handler/merchant.go`
  - `api/backend/handler/store.go`
  - `api/store/handler/store.go`
- 查询返回值继续使用 `StorageObject`：
  - `domain/merchant.go`
  - `domain/store.go`
  - `api/customer/types/merchant.go`
- repository 写库改为安全提取：
  - `repository/merchant.go`
  - `repository/store.go`

## 踩坑与偏差
- 第一轮把 Create/Update DTO 也改成了 `StorageObject`。这会把内部模型泄漏到前端协议，增加请求复杂度，还顺手破坏了原有 string 长度校验。这是错误抽象，不该为了内部一致性牺牲外部接口稳定性。
- 第二轮错误地把 product 也纳入了修复范围。用户随后明确 product 不在本次边界内，因为它的图片字段由前置校验兜底；这里暴露出我把“参考现有模块”误解成了“顺手统一现有模块”。
- `runTests` 工具没有识别这几个 Go 测试文件，验证阶段改用 `go test ./domain ./repository -run 'TestStorageObject|TestMerchantRepositoryTestSuite|TestStoreRepositoryTestSuite'` 补跑。

---

> 可复用模式与反思已提取至 [knowledge/conventions.md](../knowledge/conventions.md)，按需查阅。
