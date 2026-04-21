# Thread: 门店排名签名对齐 — pager 约定 + 专用 filter + 轻量查询

> 日期: 2026-03-19
> 标签: #store-rank #convention #pager #filter #simple-query #customer

## Context

门店排名功能连续两轮反馈暴露三个问题：

1. **签名不规范**：`GetRankedStores` 使用 `(merchantID, page, pageSize int)` + 包装返回 `*StoreRankResult`，与项目列表接口 `(pager, filter) → (slice, total, err)` 约定不一致。
2. **错误复用 filter**：第一轮修复复用了 `StoreFilter`，但 `StoreFilter` 有 15+ 个字段（MerchantName, MerchantCode, Province 等），排名接口根本不支持这些查询维度。查询语义不同时，不应强行复用。
3. **查询过重**：`BuildStoreRank` 用 `ListBySearch` 加载完整 `*Store`（30+ 字段 + WithMerchant），但只用到 ID、MerchantID、CreatedAt。

## 关键决策

1. **pager 直接透传**（第一轮）：handler 不解构 `pager.Page/Size` 再传 int，直接传 `*upagination.Pagination`。usecase 用 `pager.Offset()`/`pager.Size` 计算 Redis range。
2. **移除 `StoreRankResult` 包装**（第一轮）：列表接口返回 `(slice, total, err)` 扁平元组，handler 层用 `StoreListResp` 包装响应。
3. **新建 `StoreRankedFilter`**（第二轮纠偏）：排名接口只需 MerchantID + StoreName + Status + BusinessTypeCode 四个字段。查询语义与 `StoreFilter` 差异大，不应复用。fallback 路径内部转换为 `StoreFilter` 调用 `GetStores`。
4. **新建 `GetSimpleStores` + `StoreSimpleFilter`**（第二轮）：`StoreSimple` 加入 MerchantID 字段；repo 层 `GetSimpleStores` 只 Select ID/MerchantID/StoreName/CreatedAt。`BuildStoreRank` 改用此方法。

## 最终方案

| 文件                                | 变更                                                                                                                                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `domain/store.go`                   | 删除 `StoreRankResult`；新增 `StoreSimpleFilter`、`StoreRankedFilter`；`StoreSimple` 加 `MerchantID`；`StoreRepository` 加 `GetSimpleStores`；`GetRankedStores` 改用 `StoreRankedFilter` |
| `repository/store.go`               | 实现 `GetSimpleStores`：Select 仅 4 字段                                                                                                                                                 |
| `usecase/store/store_rank_build.go` | `BuildStoreRank` 改用 `GetSimpleStores`；内部方法参数从 `*Store` 改为 `StoreSimple`                                                                                                      |
| `usecase/store/store_rank.go`       | `GetRankedStores` 改用 `StoreRankedFilter`；`fallbackGetStores` 内部转换为 `StoreFilter`                                                                                                 |
| `api/customer/handler/store.go`     | 构建 `StoreRankedFilter`                                                                                                                                                                 |
| `api/customer/types/store.go`       | 新增 `StoreListResp`                                                                                                                                                                     |

## 踩坑与偏差

- **第一轮复用 StoreFilter 是错误的**。StoreFilter 有 15+ 字段（含 Province、MerchantName、MerchantCode、CreatedAtGte/Lte 等），排名接口无法支持也不需要。查询语义不同时必须新建 filter。
- **第一轮遗漏了 BuildStoreRank 的过重查询问题**。应与读路径一起审查写路径。

---

> 可复用模式与反思已提取至 [knowledge/store.md](../knowledge/store.md)，按需查阅。
