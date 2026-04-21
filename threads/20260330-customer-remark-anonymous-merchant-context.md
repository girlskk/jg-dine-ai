# Thread: customer remark 匿名商户上下文修复

> 日期: 2026-03-30
> 标签: #customer #remark #auth #bugfix #panic #reflect

## Context

customer `/remark` 需要支持未登录用户下单场景，因此不能依赖会员登录态来提供商户信息。但 handler 内部却直接调用 `domain.FromBackendUserContext(ctx)` 读取品牌后台用户并取 `MerchantID`。在 customer 服务里，这个上下文根本不会被认证中间件注入；如果接口继续依赖登录态，未登录用户就无法正常获取备注列表，且错误上下文仍会导致 nil pointer panic。

## 关键决策

1. 不做表面判空后继续依赖错误上下文。根因不是“没判空”，而是 customer 匿名接口错误依赖了 backend 登录态。
2. 保持接口语义与业务一致：未登录用户也能调用，因此商户维度只能由前端显式传 `merchant_id`，不能依赖 `MemberContext`。
3. 路由恢复 `NoAuths()`，让鉴权和数据来源保持同一套匿名契约。

## 最终方案

修改 `api/customer/handler/remark.go`：

- 删除对 `FromBackendUserContext` 的错误依赖。
- 增加 `NoAuths()`，允许未登录用户访问 `/remark`。
- 改为从查询参数解析 `merchant_id`，并写入 `RemarkFilter.MerchantID`。
- Swagger 注释补充 `merchant_id` 参数说明。

修改 `api/customer/types/remark.go`：

- 为 `RemarkListReq` 增加必填 `merchant_id` 字段。

新增 `api/customer/handler/remark_test.go`：

- 通过 HTTP 级回归测试验证 handler 会把查询参数 `merchant_id` 透传给 `RemarkInteractor`。
- 覆盖缺少 `merchant_id` 时返回 `400` 的路径。

验证：`go test -count=1 ./api/customer/handler`

## 踩坑与偏差

- 一度把这个接口收敛成会员上下文语义，但那和“未登录用户也会下单”的业务事实冲突。真正要守住的是匿名前端契约，而不是为了省传参强行绑登录态。
- `go test` 第一次命中了缓存，没立刻暴露新测试文件里的机械错误；随后通过诊断和 `-count=1` 强制重跑纠正了这个验证偏差。

---

> 可复用模式与反思已提取至 [knowledge/auth.md](../knowledge/auth.md)，按需查阅。
