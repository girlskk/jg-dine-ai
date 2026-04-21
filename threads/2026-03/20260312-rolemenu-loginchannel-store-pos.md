# Thread: RoleMenu LoginChannel Store/Pos 收敛

> 日期: 2026-03-12
> 标签: #rolemenu #loginchannel #store #pos #api #reflect

## Context
RoleMenu 增加 `login_channel` 维度后，`admin/backend` 已固定渠道常量，但 `store` 场景存在额外约束：`LoginChannelStore` 与 `LoginChannelPos` 属于同一角色体系，且均由 store 端维护权限。因此 store 端必须支持按渠道分别配置与查询菜单权限。

## 关键决策
1. `admin/backend` 继续使用服务侧常量，不允许客户端覆盖渠道。
2. `store` 端的 `SetMenus` 与 `RoleMenuList` 都显式接收 `login_channel`。
3. `store` 端仅允许 `store/pos` 两个渠道，其他值直接返回 `400 InvalidParams`。

## 最终方案
- 修改 `api/store/handler/role.go`:
  - `SetMenus` 通过 `ShouldBind(&req)` 获取 `login_channel`，并下传 usecase。
  - `RoleMenuList` 不再使用 `c.Query("login_channel")`，改为 `types.RoleMenuListReq` + `ShouldBind(&req)`。
  - 渠道合法性使用 `types` 层 binding 规则（`oneof=store pos`）保证。
- 修改 `api/store/types/role.go`:
  - `SetMenusReq.LoginChannel` 增加 `binding:"required,oneof=store pos"`。
  - 新增 `RoleMenuListReq` 作为列表查询入参结构。
- 编译验证：`go build ./api/store/... ./usecase/... ./repository/... ./domain/...` 通过。

## 踩坑与偏差
- 上一轮将 store 的 `RoleMenuList` 固定为 `LoginChannelStore`，导致无法查询同角色下的 POS 权限。
- 偏差根因：把“服务身份固定”与“store 端配置多渠道权限”混为一谈。

---

> 可复用模式与反思已提取至 [knowledge/auth.md](../knowledge/auth.md)，按需查阅。
