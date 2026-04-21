# 认证与权限知识

> 来源 threads: auth-skipper-fullpath-dynamic-routes, customer-remark-anonymous-merchant-context, rolemenu-loginchannel-store-pos

## Auth Skipper

- 优先使用 `c.FullPath()` 做白名单匹配，不直接用 `c.Request.URL.Path` 去匹配带 `:param` 的模板
- 当 `FullPath()` 为空时回退到 `c.Request.URL.Path`
- 问题根因：`AllowPathPrefixSkipper` 用实际请求路径（如 `/table/guest/123`）匹配 `NoAuths()` 声明的 Gin 路由模板（`/table/guest/:id`），动态段天然不等

## RoleMenu LoginChannel

- admin/backend 使用服务侧常量固定渠道，不允许客户端覆盖
- store 端 `SetMenus` 与 `RoleMenuList` 显式接收 `login_channel`。仅允许 `store/pos` 两个渠道（`binding:"required,oneof=store pos"`），其他值返回 400
- 渠道归属拆两层：服务身份层（固定常量，不信任客户端）vs 业务配置层（store 管理多终端，显式接收并白名单校验）

## Customer 匿名接口

- 匿名接口（如 `/remark`）如果业务需要商户维度，必须走显式请求参数（如 query `merchant_id`），不能偷用 backend/member 登录态上下文
- handler 的鉴权语义、请求契约和数据来源必须一致：`NoAuths()` 接口不能把关键过滤条件绑在 `MemberContext` 上
