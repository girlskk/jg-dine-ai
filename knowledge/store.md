# 门店与排名知识

> 来源 threads: store-rank-refactoring, store-rank-pager-filter-convention, admin-merchant-simple-list

## 排名架构

- 排名是 Store 的一个查询维度，不需要独立 Interactor。方法归入 `StoreInteractor`：`usecase/store/store_rank.go`（读）+ `store_rank_build.go`（写）
- `StoreInteractor` 新增 `DataCache` 依赖用于 Redis 排名读写
- Redis key：`store:rank:` / `store:product_rank:`
- `rankMonthKey` 简化：`yesterday := now.AddDate(0, 0, -1); return yesterday.Format("200601")`。无需 day==1 特判

## N+1 修复

- Redis 读路径三步走：(1) 从 Redis 收集所有 ID (2) 一次批量查 DB (3) 按 key 分发结果
- BuildStoreRank 改用 `GetSimpleStores`（只 Select ID/MerchantID/StoreName/CreatedAt），避免加载完整 `*Store`（30+ 字段）

## 排名签名

- `GetRankedStores` 使用 `StoreRankedFilter`（只有 MerchantID/StoreName/Status/BusinessTypeCode 四字段），不复用 `StoreFilter`（15+ 字段）。fallback 路径内部转换
- 使用 `*upagination.Pagination` 直接透传，usecase 用 `pager.Offset()/pager.Size` 计算 Redis range。不用 `StoreRankResult` 包装返回
