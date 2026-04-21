# Thread: 报表模块实现 — 编码规范收敛

> 日期: 2026-03-16（最后更新: 2026-03-16）
> 标签: #report #convention #orderby #usecase #api #ent #swagger #date #time

## Context

新增三张报表（商品销售明细表、商品销售汇总表、订单销售汇总表），跨 domain → ent schema → repository → usecase → handler → fx wiring 全层实现。首次实现后经过三轮 code review 反馈，逐步将代码收敛到与既有模块（Store 为参考）一致的风格。

## 关键决策

1. **报表 ent schema 不建 edge**：事实表冗余字段（merchant_id, store_id, store_name 等），不需要关联查询，`Edges()` 返回空。
2. **OrderBy 用 struct 而非 string 常量**：与 Store 模块对齐，使用 `XxxOrderByType int` + `XxxOrderBy struct { OrderBy XxxOrderByType; Desc bool }` + 构造函数模式。
3. **UseCase 直接返回 repo 调用结果**：当 usecase 不做额外编排时（如列表查询），直接 `return interactor.DataStore.XxxRepo().GetXxx(ctx, ...)` 而非用中间变量 + 错误包装。
4. **API 层 StoreID 用单值而非切片**：前端不会同时传多个 StoreID，filter 使用 `StoreID uuid.UUID`（单值）+ repo 用 `StoreIDEQ` 而非 `StoreIDIn`。

## 最终方案

### 涉及文件

- `domain/product_sale_detail.go`, `domain/product_sale_summary.go`, `domain/order_sale_summary.go`
- `ent/schema/productsaledetail.go`, `ent/schema/productsalesummary.go`, `ent/schema/ordersalesummary.go`
- `repository/product_sale_detail.go`, `repository/product_sale_summary.go`, `repository/order_sale_summary.go`
- `usecase/productsaledetail/`, `usecase/productsalesummary/`, `usecase/ordersalesummary/`
- `api/backend/handler/product_sale_detail.go`, `api/backend/handler/product_sale_summary.go`, `api/backend/handler/order_sale_summary.go`
- `api/backend/types/product_sale_detail.go`, `api/backend/types/product_sale_summary.go`, `api/backend/types/order_sale_summary.go`
- `api/backend/backendfx/backendfx.go`, `cmd/backend/main.go`

## 踩坑与偏差

1. **首版 OrderBy 用了 `type XxxOrderBy string` + 字符串常量**：与 Store 模式不一致，改为 `int` + struct + 构造函数。
2. **首版 UseCase 包装了 repo 返回的 error**：对于纯查询场景，不需要额外 `fmt.Errorf("failed to get xxx: %w", err)`，直接返回即可。
3. **首版 handler 有 `parseStoreIDs` 辅助函数**：前端实际只传单个 `store_id`，改为 `uuid.Parse(req.StoreID)` 直接解析。
4. **路由不够 RESTful**：首版用 `productSaleDetail` 驼峰，改为 `/data/product-sale-detail` 连字符。
5. **Swagger 注解写了多行 @Param**：应使用单行 `@Param data query types.XxxReq true "desc"` 绑定整个结构体。
6. **ent schema 首版加了 merchant / store edge**：事实表不需要 edge，字段冗余即可。
7. **Domain 接口签名首版多行**：应保持单行，与项目中其他接口风格一致。
8. **ent schema `business_date` 用了 `field.Time` 不带 `SchemaType`**：生成 MySQL `timestamp` 列而非 `date`。营业日是纯日期概念，必须使用 `SchemaType(map[string]string{dialect.MySQL: "DATE", dialect.SQLite: "DATE"})`，与 `DailyRevenueFact` 一致。
9. **Handler 对 DATE 列使用了 `DayEnd`**：`DayEnd` 仅适用于 DATETIME 列（如 `created_at`）。DATE 列没有时间分量，`GTE/LTE` 直接用日期即可，不需要扩展到 23:59:59。
10. **Handler 日期解析用了 `time.Parse` 而非 `util.ParseDateOnly`**：`time.Parse` 使用 UTC，`util.ParseDateOnly` 使用 `time.Local`，且与项目统一约定一致。错误码应使用 `errcode.TimeFormatInvalid` 而非 `errcode.InvalidParams`。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md), [knowledge/conventions.md](../knowledge/conventions.md)，按需查阅。
