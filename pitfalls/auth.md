# 鉴权与上下文

> 索引：5 条 pitfall

---

## 多渠道角色权限需按渠道分别配置

**何时撞见**：store 端查 POS 渠道权限仍返回 store 渠道菜单。
**为什么**：`RoleMenuList` 固定查询单一渠道，不接收动态渠道参数。
**怎么办**：`SetMenus` 和 `RoleMenuList` 都改为接收 `login_channel` 参数；store 端仅允许 `store/pos` 两个渠道。类型绑定规则约束：`binding:"required,oneof=store pos"`。

---

## 动态路由模板白名单按 Gin 路由匹配

**何时撞见**：`/table/guest/:id` 声明 `NoAuths()` 后仍然要求鉴权。
**为什么**：认证中间件对 `c.Request.URL.Path` 匹配白名单（实际 URL）；声明的是 Gin 模板（含动态段）；两者天然不等。
**怎么办**：共享中间件 `currentPath(c)` 优先返回 `c.FullPath()`（Gin 路由模板）；为空时回退 `c.Request.URL.Path`（实际请求 URL）。`AllowPathPrefixSkipper` 基于 `currentPath` 匹配。

---

## 匿名接口不能依赖登录上下文

**何时撞见**：customer `/remark` 返回 nil pointer panic；未登录用户无法调用。
**为什么**：接口声明 `NoAuths()` 但内部调用 `domain.FromBackendUserContext(ctx)`。
**怎么办**：恢复 `NoAuths()`；商户信息改为从查询参数解析；使用 `FromCustomerUserContext` 后不再依赖 backend 登录态。handler 补充 `merchant_id` 参数绑定与校验。

---

## 客户路由需按权限等级显式分类

**何时撞见**：guest token 无法和 member token 产生能力差异；某些 A 类接口被 guest 穿透。
**为什么**：`NoAuths()` 混装真正匿名和 guest/member 共用；漏标 handler 默认放开而不是默认收紧。
**怎么办**：路由分为三档：`NoAuths()`（真正匿名）、`GuestAuths()`（guest/member 都可）、默认（member-only）。鉴权中间件对 guest 路由外的 guest token 返回 403。支付、订单、会话读取声明为 `GuestAuths()`。

---

## 游客身份统一依赖 token 而非登录态分支

**何时撞见**：游客订单查询无法获取当前用户信息或需保留两套身份上下文。
**为什么**：只有会员登录态概念；游客通过 `NoAuths()` 匿名放行，没有真正身份模型。
**怎么办**：游客登录返回标准 `AuthToken{ID}`；认证器改为先查 member 表再查 Redis guest 快照；两者最终都注入 `CustomerUserContext`。订单统一按 token 中的 `user_id` 查询，不区分类型。客户删除第二套 `MemberContext` 入口。
