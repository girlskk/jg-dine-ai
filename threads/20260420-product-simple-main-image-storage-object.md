# Thread: ProductSimple 主图输出收敛为 StorageObject

> 日期: 2026-04-20
> 标签: #product #storage #repository #domain #reflect

## Context
`domain.ProductSimple.MainImage` 仍然是 `string`，与 `domain.Product.MainImage`、`domain.OrderProduct.MainImage` 等读模型不一致。仓储 `GetSimpleProducts` / `GetSimpleProductsWithSKU` 也直接把数据库里的 `main_image` key 透传出去，导致商品简要读模型对外暴露的是原始 key，而不是统一的 `{key,url}` 结构。

## 关键决策
1. 写接口边界不动，商品创建/更新请求继续接收 string key。
2. 读模型边界收敛，`ProductSimple.MainImage` 改为 `domain.StorageObject`。
3. 仓储简要查询返回时统一用 `domain.NewStorageObjectFromKey(...)` 包装数据库里的图片 key。

## 变更结果
- `domain/product.go`：`ProductSimple.MainImage` 从 `string` 改为 `StorageObject`。
- `repository/product.go`：`GetSimpleProducts` 和 `GetSimpleProductsWithSKU` 的 `main_image` 返回值统一包装为 `StorageObject`。

## Verify
- `gofmt -w domain/product.go repository/product.go`
- `go test ./domain ./repository ./usecase/store -run '^$'` ✅
- 额外运行过 `go test ./domain ./repository ./usecase/store`，其中 `repository` 包存在与本次改动无关的既有失败，不能作为本次字段修正的回归依据。

## Reflect
- 这类问题的根因不是数据库字段类型，而是读写边界混淆。持久化层当然可以继续存 string key，但领域读模型如果已经统一用 `StorageObject`，简要查询就不该再偷懒退回 string。
- 验证也不能偷懒跑“相关大包全量测试”就下结论；仓库里已有红测时，应该补一个 compile-only 的最小验证，先证明本次改动没有引入新的类型错误。