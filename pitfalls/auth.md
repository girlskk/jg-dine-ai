# 鉴权与上下文

> 索引：3 条 pitfall

---

## 店端权限必须带 login_channel 维度

**何时撞见**：同一个门店账号在 store/POS 两个端看到同一套菜单。
**为什么**：store 与 POS 共用角色体系，但权限菜单是渠道维度；只按角色查会把两个端混在一起。
**怎么办**：角色菜单读写接口显式传 `login_channel`；store 侧只允许 `store/pos`。新增权限接口时先 grep `LoginChannel`，不要默认单渠道。

---

## 动态路由白名单按 Gin 模板匹配

**何时撞见**：声明了动态路径白名单，真实请求仍被鉴权拦截。
**为什么**：白名单声明的是 Gin 模板（如 `/table/guest/:id`），请求 URL 是真实路径；直接比 `c.Request.URL.Path` 会天然不相等。
**怎么办**：白名单匹配优先用 `c.FullPath()`；为空时再回退真实 URL。新增 skipper 时不要绕过共享的 `currentPath(c)`。

---

## customer 路由按匿名 / guest / member 三档建模

**何时撞见**：接口既要支持游客身份又不能放成真正匿名，或匿名接口误读登录上下文。
**为什么**：`NoAuths()` 只表示真正匿名；guest/member 都是有身份 token 的 customer 用户，不能用“未登录分支”建模。
**怎么办**：路由分三档：`NoAuths()`（真正匿名）、`GuestAuths()`（guest/member 都可）、默认（member-only）。游客登录也返回标准 `AuthToken{ID}`，认证器最终都注入 `CustomerUserContext`；匿名接口所需商户信息从参数解析。
