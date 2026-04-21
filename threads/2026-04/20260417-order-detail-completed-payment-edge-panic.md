# Thread: 已完成订单详情因空第三方支付边缘切片触发 panic

> 日期: 2026-04-17
> 标签: #order #backend #payment #debugging #reflect

## Context

backend `GET /order/:id` 在查询已完成订单时返回 500，而未完成订单正常。差异点在于已完成订单会额外命中 payment 记录预加载，所以排查重点放在订单详情读取链路里的 payment 转换。

## 关键决策

1. 根因修复放在 `repository/order.go` 的 payment 转换函数。
   原因：已完成订单才会加载 payment 记录，原代码对 ent eager-load 的 `ThirdPayInfo` 空切片做 `[0]` 访问，属于仓储读取阶段的错误假设，应该在最靠近数据转换的位置修正。

2. 用仓储级回归测试锁定“completed 订单 + payment 记录 + 无 third_pay_info”场景。
   原因：仓库里没有现成 backend acceptance 脚本，且本地 compose 既缺可用 bundle 镜像，又在 builder 重建时持续 OOM；直接在 repository 层构造最小 completed 数据更稳定，也能精确复现 panic 条件。

3. 放弃支付快照兼容类型改造。
   原因：中途为了排除另一类 500 可能，临时验证了 legacy `order_payments` 数组 JSON 的兼容方案；用户随后明确说明“没有旧数据，不要改这个类型”，因此该分支全部撤回，不把未经证实的数据兼容复杂度带进主线。

## 最终方案

- 在 `repository/order.go` 的 `convertPaymentToDomain` 中，把 `ThirdPayInfo` 读取从“只判非 nil 就取 `[0]`”改为“`len(...) > 0` 才读取第一条”。
- 新增 `repository/order_test.go` 回归用例：创建一条 completed 订单、挂一条 payment 记录但不创建 third pay info，调用 `GetDetail`，断言返回正常且 `payment.ThirdPayInfo == nil`。
- 验证通过：`go test ./repository -run 'TestOrderTestSuite/TestOrder_GetDetail_WithPaymentWithoutThirdPayInfo$' -v`、`go test ./repository -run 'TestOrderTestSuite$'`、`go test ./usecase/order -run '^$'`、`go test ./api/backend/... -run '^$'`。

## 踩坑与偏差

- ent 在 `WithThirdPayInfo()` 预加载时，即使没有关联记录，也会把 `Edges.ThirdPayInfo` 初始化为 `[]*ThirdPayInfo{}`，不是 `nil`。只判非 nil 会误以为可安全取首元素。
- 本地运行态验证被环境阻塞：`docker compose up -d` 缺可用 `dine-bundle` 镜像，而 `docker compose build builder` 在 bundle 编译阶段持续报 `/usr/local/go/pkg/tool/linux_arm64/compile: signal: killed`，因此只能以代码级验证为准。
- 兼容旧 `order_payments` 数组快照的方案已验证可构造出同类 500，但因用户确认仓库无旧数据，最终未保留这条改动。

## 可复用模式

- 读取 ent 的 to-many eager-load 边时，不能用“非 nil”替代“有元素”；凡是要取 `[0]` 的地方，都必须先判 `len(slice) > 0`。
- 当运行态联调被环境资源阻塞时，优先补最小回归测试锁定根因，避免把“代码已修复”和“容器没资源编译”混成一个问题。