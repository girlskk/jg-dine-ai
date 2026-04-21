# 读模型边界

> 索引：5 条 pitfall

---

## 订单销售汇总重复建模与金额分层

**何时撞见**：`OrderSaleSummary` 里有 `Amount` 又有 `RoundingAmount`；导出时金额字段混乱。
**为什么**：`Amount` 已包含 `RoundingAmount`；设计未分层金额语义。
**怎么办**：删除冗余 `RoundingAmount` 字段；导出改为读取 `Amount.RoundingAmount`；第三方平台拆分存独立 JSON 而不是堆标量列。
**历史**：threads/2026-03/20260325-order-sale-summary-shift-record-export-corrections.md

---

## 商品销售报表规格名套餐快照兜底

**何时撞见**：套餐商品的 `spec_name` 在报表里为空，单品有值。
**为什么**：套餐子项报表读取优先级只查 `groups.details[].spec_name`，不回退到同快照内 `groups.details[].sku.spec_name`。
**怎么办**：repository 读写时对套餐子项快照做归一化；当顶层 `spec_name` 为空时，用 `sku.spec_name` 回填。报表生成时再做一层兜底：先取 `spec_name`，为空时再取快照里的 `sku.spec_name`。
**历史**：threads/2026-04/20260413-product-sale-spec-name-hydration.md

---

## 订单退款详情从子单汇聚需看主单

**何时撞见**：多门店子单详情永远查不到对应的退款单。
**为什么**：子单查询键用 `order.ID`；实际退款单记录主单 `id/order_no`。
**怎么办**：usecase 退款聚合按订单关系类型统一决定查询键；独立/主单查自身 ID；子单查 `parent_order_id`。`toOrderView` 显式透传 `order.OrderRefund`。
**历史**：threads/2026-04/20260414-order-refund-refundorder-aggregation.md

---

## 订单已完成支付查询的空切片边缘 panic

**何时撞见**：backend `GET /order/:id` 返回 500；仅在已完成订单出现。
**为什么**：payment 预加载时 ent 初始化空 `ThirdPayInfo` 为 `[]*ThirdPayInfo{}`；代码判非 nil 就取 `[0]`。
**怎么办**：repository `convertPaymentToDomain` 改为先判 `len(slice) > 0` 再读取首元素。新增回归测试：completed 订单 + payment 记录 + 无 third_pay_info。
**历史**：threads/2026-04/20260417-order-detail-completed-payment-edge-panic.md

---

## 商品简要读模型主图应返回结构体

**何时撞见**：`ProductSimple` 返回 `string` key；其他读模型都返回 `StorageObject` 结构体。
**为什么**：仓储 `GetSimpleProducts` 直接透传数据库 key；写入边界没收敛。
**怎么办**：`ProductSimple.MainImage` 改为 `StorageObject`；仓储返回时用 `domain.NewStorageObjectFromKey(...)` 包装 key。写入边界保持 string，读出边界统一 `StorageObject`。
**历史**：threads/2026-04/20260420-product-simple-main-image-storage-object.md
