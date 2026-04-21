# Thread: customer 路由鉴权分层收口

> 日期: 2026-04-02
> 标签: #customer #auth #guest #member #middleware #reflect

## Context

customer 侧此前只有两档路由语义：`NoAuths()` 直接跳过鉴权，其他路由只要 token 合法就放行。这样会导致 guest token 和 member token 在中间件层没有能力差异，结果是 C 类“必须会员”的接口只能在 handler 内部零散地 `user.IsGuest()` 补洞；一旦漏判就是权限 bug。

这次目标是把 customer 路由明确拆成三档：

- A：真正匿名接口，无 token 可访问；
- B：必须带合法 customer token，但 guest/member 都可访问；
- C：必须带 member token，guest 一律禁止。

同时顺手修掉两个明显越权点：`/payment` 之前整组都在 `NoAuths()` 下，`/refund/refund` 也被声明成匿名。

## 关键决策

1. 不继续复用 `NoAuths()` 混装 A 和 B。`NoAuths()` 只保留真正匿名的 A 类路由，新增 `GuestAuths()` 用于声明 guest/member 都可访问的 B 类路由；其余未声明路由默认全部按 C 处理。

   原因：默认收紧比默认放开安全得多。以后即便漏标，结果也是功能收紧，而不是 guest 穿透 member-only 接口。

2. customer 鉴权中间件继续保持和其他服务一致的 `AllowPathPrefixSkipper` 形态，不额外引入 customer 专属 route table 类型。

  原因：用户明确要求 customer 的 auth 实现风格和 backend/store 保持一致。为了不再出现整组放开的老问题，customer 侧不再声明 `/payment` 这类组路径，而是只声明叶子路径，例如 `/payment/third_pay/notify`、`/payment/pay_h5`。

3. guest/member 差异必须在中间件统一拦截，handler 内零散的 `user.IsGuest()` 只保留业务特例，不再承担基础访问控制职责。

   原因：像会员充值、消费、退款这种接口，只要靠 handler 人工补判，迟早会漏。访问级别本质属于路由契约，应该集中在中间件执行。

4. 先显式标注已经确认的 B 类 customer 会话接口：merchant、store、dine table、remark、order、payment 查询/发起支付；把 `refund/refund` 收回默认 C。

   原因：这些接口当前已经依赖 customer token 上下文或明确面向 guest/member 共用流程；先把现有高风险链路收口，再逐步补充其他 B 类接口，不一次性扩散猜测范围。

## 最终方案

改动集中在以下位置：

- `api/customer/middleware/auth.go`
  - 收敛为两个 prefix skipper：`publicSkipper`（A）和 `guestAllowedSkipper`（B）。
  - 鉴权流程改为：
    - A：直接放行；
    - 非 A：必须有 Bearer token；
    - token 合法后，如果是 guest 且路由不在 B，则直接 `403`；
    - 通过后再注入 `CustomerUserContext`。

- `api/customer/handler/order.go`
  - 订单创建、预下单、列表、详情、取消统一声明为 `GuestAuths()`；不再通过 `NoAuths()` 匿名放行列表/详情。

- `api/customer/handler/payment.go`
  - `NoAuths()` 只保留第三方支付回调 `/payment/third_pay/notify`。
  - `pay_h5` 与 `info_list` 改为 `GuestAuths()`，要求必须有合法 guest/member token。

- `api/customer/handler/merchant.go`
- `api/customer/handler/store.go`
- `api/customer/handler/dine_table.go`
- `api/customer/handler/remark.go`
  - 这些 customer 会话读取接口都显式声明为 `GuestAuths()`。

- `api/customer/handler/refund.go`
  - 去掉匿名 `NoAuths()`，回归默认 member-only。

- `api/customer/middleware/auth_test.go`
  - 新增中间件回归测试，覆盖：匿名路由放行、B 类路由无 token 返回 `401`、B 类路由 guest token 放行、C 类路由 guest token 返回 `403`、C 类路由 member token 放行、动态路由模板匹配正常。

验证：

- `go test ./api/customer/...` ✅
- `.github/acceptance/` 当前没有 customer 验收脚本，无法补跑 curl 验收。

## 踩坑与偏差

1. 第一版容易沿着现有 `NoAuths()` 继续做“多一层 if guest then forbid”的补丁，但那只是把 bug 继续分散到各个 handler。真正要修的是路由契约表达能力不够。

2. 这次最终还是按用户要求回到 `AllowPathPrefixSkipper`。代价是 customer 以后如果继续声明组级前缀（如 `/payment`、`/merchant`），或者在已有叶子路径下继续扩子路由，就有机会把权限顺带继承出去；这个风险不会因为实现一致就自动消失。

3. customer 里还有一些历史接口没有显式归档到 A/B/C，例如电子发票、部分登录前辅助查询。这次只先修高风险链路，不假装已经把全量 customer 路由完全梳理干净。

## 可复用模式

1. 当一个服务同时存在 public、guest/member 共用、member-only 三档接口时，绝不能只保留“匿名/非匿名”两档中间件语义。至少要再有一档显式的 guest-allowed 元数据。

2. 对安全边界而言，默认策略应该是“未声明则收紧”，而不是“未声明则放开”。这样漏标注会造成可见的功能问题，而不是静默越权。

3. 当团队要求所有 auth middleware 统一用 `AllowPathPrefixSkipper` 时，customer 侧就必须把声明粒度收缩到叶子路径，不能再用 `/payment`、`/merchant` 这种组级路径偷懒；否则一致性会直接变成越权入口。