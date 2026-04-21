# Thread: Admin Merchant Simple List

> 日期: 2026-04-01
> 标签: #admin #merchant #simple-list #api #usecase #repository #reflect

## Context

admin 侧已有门店轻量列表 `GET /merchant/store/simple-list`，但商户侧只有分页列表，没有对应的轻量查询接口。

用户要求参考 store 的 `SimpleList`，在 `api/admin` 下为 merchant 提供一个 `SimpleMerchantList`。

## 关键决策

1. 不把分页列表改造成“带开关的轻量模式”，而是新增独立 `simple-list` 路由。
原因：store 已经证明轻量查询应该有独立契约；把两种语义塞进一个接口只会让 handler、usecase、repo 的职责变脏。

2. merchant 轻量列表按当前最小需求只返回 `ID / MerchantName`，不额外引入搜索条件。
原因：domain 已经存在 `MerchantSimple` 结果模型，但没有 filter/repo/usecase 契约；这次先把缺失链路补齐，避免过度设计。

3. 一次性把 domain interface、usecase、repository、admin handler/types、gomock 全部补齐。
原因：只补 handler 会留下半成品接口，后续编译和测试替身都会断。

## 最终方案

核心变更：

- `domain/merchant.go`
  - 为 `MerchantRepository` 和 `MerchantInteractor` 增加 `GetSimpleMerchants`。
  - 新增 `MerchantSimpleFilter`，与 store 的轻量查询模式对齐。

- `usecase/merchant/merchant.go`
  - 新增 `MerchantInteractor.GetSimpleMerchants`，直接透传到 repo，并补 span。

- `repository/merchant.go`
  - 新增 `GetSimpleMerchants`，只查询 `id` 和 `merchant_name`，按 `created_at desc` 返回。

- `api/admin/types/merchant.go`
  - 新增 `SimpleMerchantListReq`。

- `api/admin/handler/merchant.go`
  - 新增 `GET /merchant/merchant/simple-list`。
  - 新增 `SimpleMerchantList()` handler，绑定 query 后调用 interactor 返回 `[]domain.MerchantSimple`。

- `domain/mock/merchant_interactor.go`
- `domain/mock/merchant_repository.go`
  - 补齐新的 gomock 方法，保证相关包可编译。

## 踩坑与偏差

1. `MerchantSimple` 结果结构早就存在，但没有配套 filter/repo/usecase 方法，这说明之前的实现只做了一半。
2. 这类“照着另一个模块抄一个接口”的任务，如果只盯着 handler，会直接漏掉 interface，最后在编译期爆炸。

## Verify

已执行：

- `gofmt -w domain/merchant.go usecase/merchant/merchant.go repository/merchant.go api/admin/types/merchant.go api/admin/handler/merchant.go domain/mock/merchant_interactor.go domain/mock/merchant_repository.go`
- `go test ./api/admin/... ./usecase/merchant ./repository ./domain/mock -run TestDoesNotExist`

结果：通过。

---

> 可复用模式与反思已提取至 [knowledge/conventions.md](../knowledge/conventions.md)，按需查阅。
