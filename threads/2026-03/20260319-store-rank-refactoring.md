# Thread: 门店排名重构 — 命名收敛、N+1 修复、逻辑简化

> 日期: 2026-03-19
> 标签: #store-rank #refactor #naming #n-plus-1 #redis #customer

## Context

首轮实现了基于 Redis ZSet 的门店排名功能（按月订单量排序，附带 top8 商品）。
用户 review 后给出 5 条反馈，核心问题：命名过于场景化（Customer-前缀）、架构过度拆分（独立 Interactor）、存在 N+1 查询、日期逻辑可简化。

## 关键决策

1. **命名由 `CustomerStoreRank*` 收敛为 `StoreRank*`**：排名是门店的通用能力，不应绑定到 Customer 场景。scheduler task/periodic/config 全部同步重命名。
2. **移除独立 `CustomerStoreRankInteractor`，方法归入 `StoreInteractor`**：排名只是 Store 的一个查询维度，不需要独立接口。`usecase/store/store_rank.go`（读）+ `store_rank_build.go`（写）按 "读写文件拆分" 惯例放置。
3. **`StoreInteractor` 新增 `DataCache` 依赖**：`NewStoreInteractor` 签名增加 `cache domain.DataCache` 参数，用于排名读写。
4. **使用已有 `ProductSimple` 结构**：domain 已定义 `ProductSimple`（ID/ProductName/MainImage/BasePrice），直接复用而非新建。新增 `GetSimpleProducts` 方法到 `ProductRepository`，实现 `Select(id, name, main_image)` 轻量查询。
5. **批量获取商品修复 N+1**：主路径中，先收集所有门店的 top 商品 ID（从 Redis），然后一次 `GetSimpleProducts` 批量查询，再按门店分发。
6. **`rankMonthKey` 简化**：`yesterday := now.AddDate(0, 0, -1); return yesterday.Format("200601")`。无需 day==1 特判，昨天所在月份天然满足需求。

## 最终方案

### 文件变更清单

| 操作 | 文件                                        | 说明                                                                                                        |
| ---- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 改   | `domain/store.go`                           | `StoreInteractor` 接口增加 `BuildStoreRank` + `GetRankedStores`；新增 `StoreRankResult`、`RankedStore` 类型 |
| 改   | `domain/product.go`                         | `ProductRepository` 增加 `GetSimpleProducts` 方法                                                           |
| 删   | `domain/customer_store_rank.go`             | 移除 `CustomerStoreRankInteractor` / `CustomerStoreRankResult`                                              |
| 新   | `usecase/store/store_rank.go`               | 读路径：`GetRankedStores`、`fallbackGetStores`、工具函数                                                    |
| 新   | `usecase/store/store_rank_build.go`         | 写路径：`BuildStoreRank`、`buildMerchantStoreRank`、`buildStoreProductRank`                                 |
| 改   | `usecase/store/store.go`                    | `StoreInteractor` 结构体增加 `DataCache` 字段，`NewStoreInteractor` 签名增加 `cache` 参数                   |
| 删   | `usecase/customerstorerank/`                | 整个包删除                                                                                                  |
| 改   | `usecase/usecasefx/usecasefx.go`            | 移除 `customerstorerank.New` 注册                                                                           |
| 改   | `repository/product.go`                     | 实现 `GetSimpleProducts`                                                                                    |
| 改   | `scheduler/task/customer_store_rank.go`     | `CustomerStoreRankHandler` → `StoreRankHandler`，依赖改为 `StoreInteractor`                                 |
| 改   | `scheduler/periodic/customer_store_rank.go` | `CustomerStoreRankTaskConfig/Task` → `StoreRankTaskConfig/Task`                                             |
| 改   | `scheduler/schedulerfx/schedulerfx.go`      | 更新为 `NewStoreRankHandler` / `NewStoreRankTask`                                                           |
| 改   | `bootstrap/scheduler.go`                    | `CustomerStoreRankTask` → `StoreRankTask`                                                                   |
| 改   | `etc/scheduler.toml`                        | `[CustomerStoreRankTask]` → `[StoreRankTask]`                                                               |
| 改   | `api/customer/handler/store.go`             | 移除 `CustomerStoreRankInteractor` 依赖，直接用 `StoreInteractor.GetRankedStores`                           |
| 改   | `api/customer/types/store.go`               | 移除 `StoreListResp`，handler 直接返回 `*domain.StoreRankResult`                                            |

### Redis key 前缀变更

- `customer:store_rank:` → `store:rank:`
- `customer:product_rank:` → `store:product_rank:`

## 踩坑与偏差

1. **`ProductSimple` 重复声明**：domain/product.go 已有 `ProductSimple`（含 `ProductName` 字段名而非 `Name`），首次在 `ProductRepository` 接口旁新增了重复定义导致编译失败，发现后删除重复定义并适配已有结构字段名。
2. **独立 Interactor 的过度设计**：首轮为排名功能单独创建了 interface + usecase package + FX 注册，增加了不必要的复杂度。排名本质上是 Store 的一个查询能力，直接扩展 StoreInteractor 更符合架构。

---

> 可复用模式与反思已提取至 [knowledge/store.md](../knowledge/store.md)，按需查阅。
