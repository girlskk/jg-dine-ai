# 读模型边界

> 索引：5 条 pitfall

---

## 订单退款详情从子单汇聚需看主单

**何时撞见**：多门店子单详情永远查不到对应的退款单。
**为什么**：子单查询键用 `order.ID`；实际退款单记录主单 `id/order_no`。
**怎么办**：usecase 退款聚合按订单关系类型统一决定查询键；独立/主单查自身 ID；子单查 `parent_order_id`。`toOrderView` 显式透传 `order.OrderRefund`。

---


## 商品简要读模型主图应返回结构体

**何时撞见**：`ProductSimple` 返回 `string` key；其他读模型都返回 `StorageObject` 结构体。
**为什么**：仓储 `GetSimpleProducts` 直接透传数据库 key；写入边界没收敛。
**怎么办**：`ProductSimple.MainImage` 改为 `StorageObject`；仓储返回时用 `domain.NewStorageObjectFromKey(...)` 包装 key。写入边界保持 string，读出边界统一 `StorageObject`。
