# Thread: customer 游客 token 与统一身份上下文

> 日期: 2026-04-02
> 标签: #customer #auth #guest #member #token #reflect

## Context

customer H5 原本只有会员登录态概念，但订单与支付接口又通过 `NoAuths()` 实际走匿名放行，导致“未登录用户也能下单”这件事没有真正的身份模型，只有绕过鉴权。与此同时，用户已经在 `domain/customer_user.go` 和 `domain/guest_user.go` 开始收敛 customer / guest 的领域表达，customer 下几个 public handler 也因为 `NewGuestUser` 签名变化进入编译失败状态。

这次目标不是再补一个孤立的游客接口，而是让 customer 模块拥有统一的 `CustomerUser` 上下文：

- 会员 token 仍然能工作；
- 新增游客 token，可静默获取并进入同一套 customer 鉴权；
- order / payment 这类 customer 会话接口不再靠匿名放行，而是明确依赖 member 或 guest token。

## 关键决策

1. 不强行重做现有 member login 接口和 token 签发链路，而是在 `usecase/userauth/customer` 下新增统一 customer 认证器聚合 member 与 guest：
  - 会员 token 与游客 token 都统一使用 `userauth.AuthToken{ID}`，不再引入 customer 专用 claim。
  - `Authenticate` 始终按这个 `id` 先查 member 表，miss 后再查 Redis guest 会话。
  - 两者最终都只注入 `CustomerUserContext`；customer handler 不再保留第二套 `MemberContext` 入口。

   原因：现有 member 登录链路本身没有 `merchant_id` 入参，`Login` 仍按手机号全局查会员并在新建会员时缺少明确商户归属。如果这一轮顺手把 member token 也强改成 merchant-aware，只会把一个更深层的建模问题和 guest token 任务绑死在一起。

2. 订单归属统一按 token 中的 `user_id` 收口，不区分 member / guest 类型；不新增字段，直接复用订单现有 `member_id` 保存当前 customer user ID。

  原因：用户要求“订单信息不用关注用户类型，统一根据 token 中的 userId 查询”，并进一步明确“不需要添加字段，直接使用 MemberID”。这意味着统一 customer 身份必须落到现有 `member_id` 持久化字段和 repo 查询条件里，而不是继续新增一个独立 ownership 列。

3. 把 `orders`、`payment/pay_h5`、以及 customer 下依赖当前用户 merchant 语义的读取接口都收回到鉴权中间件，游客要先拿 token 再访问。

   原因：如果这些接口继续留在 `NoAuths()`，那游客 token 没有任何实际意义，customer 也仍然没有统一的身份边界。

4. 游客登录签发 token 的同时，把 guest 快照存到 Redis 30 天；`Authenticate` 不再依赖 guest token 自带资料做无状态鉴权，而是以 Redis 为准恢复 guest 身份。

5. 不改 member 侧现有 `merchant_id` 建模；customer 只在进入 customer 模块时抽象成统一 `CustomerUser`。

  原因：用户明确要求“会员那边的 merchantId 不要动”。这一轮只解决 customer 统一身份和订单归属，不把 member 登录链路的历史问题混进来。

6. customer handler 禁止借用 `FrontendUser`、`NewGuestUser` 或额外 helper 文件拼装当前用户；一律通过 `FromCustomerUserContext` 读取。

  原因：`FrontendUser` 属于 frontend 服务语义，不该污染 customer；而 helper 包装会继续制造多个“当前用户来源”，破坏统一身份上下文的边界。

## 最终方案

新增统一 customer 身份模型：

- `domain/customer_user.go`
  - 定义 `CustomerUser`，实现 `domain.User`。
  - 定义 `CustomerUserInteractor`（仅 guest login）、`CustomerAuthInteractor`、统一 context helper。
  - 会员进入 customer 模块时，统一转换为 `CustomerUser`。

- `usecase/customeruser/customer_user.go`
  - 仅负责游客登录。
  - 签发游客 token 前校验商户状态，并循环生成 UUID 直到确认不与 member 表主键冲突。
  - token 签发改为和其他模块一致的 `userauth.AuthToken{ID}`。
  - 把 guest 用户快照写入 Redis，TTL 为 30 天。
  - 使用 locale 生成 `游客XXXXXX` / `Guest XXXXXX` 形式的 `real_name`。

- `usecase/userauth/customer/customer.go`
  - 新增统一 customer 认证器。
  - 解析 token 时与其他模块保持一致，统一使用 `jwt.ParseWithClaims(..., &userauth.AuthToken{})`。
  - 认证顺序固定为：先按 token id 查 member 表，未命中再查 Redis guest 快照，否则返回 `ErrTokenInvalid`。

customer API 接线与中间件：

- `usecase/usecasefx/usecasefx.go`
  - 注册 `CustomerUserInteractor`。

- `api/customer/customerfx/customerfx.go`
  - 补上 `Locale` 中间件。
  - 注册新的 `CustomerHandler`。

- `api/customer/app.go`
  - customer 中间件顺序补齐 `Locale`，其余保持与现有 customer/store 模式一致，避免无关中间件顺序漂移。

- `api/customer/middleware/auth.go`
  - 不再在 middleware 自己维护“guest 后 member”的双分支。
  - 改为统一调用 `CustomerAuthInteractor.Authenticate`。
  - 成功后只注入 `CustomerUserContext`。

新增游客登录接口：

- `api/customer/handler/customer.go`
  - 新增 `POST /api/v1/customer/guest/login`。
  - 返回统一的 `domain.LoginResult`，不再单独定义 customer 专用登录响应 DTO。

- `api/customer/types/customer.go`
  - 定义 `GuestLoginReq/Resp`。

order / payment 改造：

- `api/customer/handler/order.go`
  - 移除 `NoAuths()`。
  - 创建 / 预下单时直接从 `FromCustomerUserContext` 读取当前用户，并把 token `user_id` 写入订单现有 `member_id`。
  - 列表统一按 `OrderListParams.MemberID` 查询。
  - 详情 / 取消 / 删除先读取订单，再校验 `order.MemberID == token.UserID`。
  - 会员券仍然只允许 member token。

- `api/customer/handler/payment.go`
  - 仅保留第三方回调为匿名。
  - `pay_h5` 直接用 `FromCustomerUserContext` 读取 `CustomerUser.UserID` 作为 `OperationBy`，支持 guest / member 共用。

订单持久化补强：

- `domain/order.go`
  - 不新增 `Order` 持久化字段；`OrderListParams` 增加 `MemberID` 过滤条件，用于 customer 查单。

- `ent/schema/order.go`
  - 不新增字段，保留现有 `member_id`；注释中明确 customer 游客单会复用该字段保存 token `user_id`。

- `repository/order.go`
  - `Create` / `CreateBulk` 继续复用 `member_id` 落库，`List` 按 `member_id` 过滤，`convertOrderToDomain` 直接返回现有 `MemberID`。

- `usecase/order/order_create.go`
- `usecase/order/order_preview.go`
  - 多门店主单/子单创建时继续透传统一的 `member_id` 归属。

- `usecase/order/order.go`
  - `OrderInteractor.Get` 增加 `user domain.User` 参数。
  - 当调用方是 customer / guest 用户时，在 usecase 层校验 `order.member_id == token user id`，不一致直接返回 `ErrOrderNotExist`。

顺手修复 customer 当前编译问题：

- `api/customer/handler/merchant.go`
- `api/customer/handler/store.go`
- `api/customer/handler/dine_table.go`
  - 去掉 `FrontendUser` / `NewGuestUser` 的误用，统一从 `FromCustomerUserContext` 读取用户。

- `api/customer/handler/auth_helper.go`
  - 删除该临时 helper，避免产生第二套当前用户获取路径。

- `api/customer/handler/*.go`
  - 对已受 customer 鉴权中间件保护的路由，不重复判空 `FromCustomerUserContext(ctx)`；认证失败已经在中间件阶段拦截。

验证：

- `.github/acceptance/` 目前只有 `backend/`，没有 customer 验收脚本可运行。
- 运行：`go generate ./ent`
- 运行：`go test ./repository -run 'TestOrderTestSuite'`
- 运行：`go test ./api/customer/... ./usecase/customeruser ./usecase/order ./usecase/userauth/... ./usecase/member ./usecase/usecasefx ./ent/...`

## 踩坑与偏差

1. 第一轮把 customer 认证拆成 middleware 里的“先 guest 再 member”双分支，表面能跑，但职责是错的。用户要的不是 middleware 拼接两个认证器，而是 `userauth/customer` 成为唯一 customer 鉴权入口。

2. 第一轮 guest token 只靠 JWT 自带资料做无状态恢复，而且还单独造了 `CustomerAuthToken`。这同时违背了“guest 信息存 Redis 30 天”和“token 结构和其他模块保持一致”两个目标。guest 身份要可失效、可回收、可在认证时统一读取，就必须让 Redis 成为事实来源，让 token 只保存一个 `id`。

3. `FrontendUser` / `NewGuestUser` 这种“临时拼一个 user 传下去”的方式会继续污染 customer 边界。真正的修复不是再包一层 helper，而是只保留 `FromCustomerUserContext` 这一条入口。

## 可复用模式

1. customer 侧出现“会员和游客都要访问同一批接口”时，不要在 handler 到处 `FromMemberContext` / `NewGuestUser` / `FrontendUser` 打补丁。先抽统一的 `CustomerUserContext`，确实需要 member 明细时再显式查询，不要靠第二套上下文偷偷透传。

2. 当 customer 同时接受 member token 和 guest token 时，middleware 不应自己维护多路认证分支。应该在 `usecase/userauth/customer` 聚合成单一 `Authenticate`，并与其他模块复用同一种 `AuthToken` 结构，把“先查 member 还是查 guest cache”的分支收进一个用例。

3. guest 登录虽然不落数据库，但也不能只发一个纯无状态 token 就结束。凡是后续 `Authenticate` 要区分“token 仍然有效”与“guest 会话已不存在”的场景，都应该把会话快照放到缓存并由认证器回查。

4. 如果 customer 要支持“查看自己的订单”，就必须把统一身份落到订单可查询的持久化字段里，并在 repo 层直接过滤。当前按用户要求复用 `member_id`；只在 handler 里分支 member / guest 无法提供真实隔离。

5. 对已经受 auth 中间件保护的 customer 路由，不要在 handler 里重复写一层 `CustomerUserContext` 判空。那只会把中间件契约打散成多处重复防御。

6. 订单 owner 校验不要停留在 customer handler。像 `OrderInteractor.Get` 这种读取入口，应该直接接收当前 `user` 并在 usecase 层校验 `member_id` 与 token user id 是否一致；不一致时统一返回“订单不存在”，避免把鉴权细节泄漏到 API 层分支里。