# Thread: Backend Superadmin Update Validation Boundary

> 日期: 2026-04-16
> 标签: #backend #user #superadmin #validation #swagger #reflect

## Context

admin/backend/store 三套用户编辑超管时，前端都会提交空 `role_ids` 和零值 `department_id`。实际运行中接口会直接返回 `INVALID_PARAMS`，而不是按超管语义仅更新可编辑字段。

backend 的根因不是单点，而是两层一起拦截，而 admin/store 用的是同一套模式：

1. `api/backend/types.BackendUserUpdateReq` 把 `role_ids` 标成了 `binding:"required,min=1"`，空数组在 Gin 绑定层直接 400。
2. `BackendUserInteractor.Update` 在查出旧用户是否为超管之前，就先执行了统一的“部门必填、角色必填”校验。

## 关键决策

1. 只放宽 update 请求的 `role_ids` 绑定，不动 create 请求。普通用户创建和更新仍然必须在业务层拿到有效角色。
2. 超管特殊分支必须在读取旧用户后处理，而不是继续沿用前置通用校验。
3. 对超管不仅要“放行”，还要冻结 `department_id` 和 `role_ids`，避免把请求里的空值或脏值写回超管记录。
4. 既然请求契约变了，就必须同步 admin/backend/store 三端 swagger，而不能只改运行时代码。

## 最终方案

- `api/backend/types/user.go`
  - `BackendUserUpdateReq.RoleIDs` 从 `required,min=1` 改为 `omitempty`，允许超管更新请求携带空数组。

- `api/admin/types/user.go` + `api/store/types/user.go`
  - `AdminUserUpdateReq.RoleIDs` / `StoreUserUpdateReq.RoleIDs` 同步从 `required,min=1` 改为 `omitempty`。

- `usecase/userauth/backenduser/backend_user_update.go`
  - 先读取旧用户，再决定是否执行 `verifyBackendUserParams`。
  - 如果旧用户是超管，跳过角色/部门必填校验，并把 `username`、`enabled`、`department_id`、`role_ids` 固定为旧值。
  - 普通后台用户仍保留原有角色/部门必填约束。

- `usecase/userauth/adminuser/admin_user_update.go` + `usecase/userauth/storeuser/store_user_update.go`
  - 同步 backend 的超管分支处理时机和字段冻结逻辑。

- `api/admin/docs/*` + `api/backend/docs/*` + `api/store/docs/*`
  - 通过 `go generate` 重生成 swagger，移除对应 update 请求上对 `role_ids` 的 required/minItems 约束。

## 踩坑与偏差

1. 初看像是单纯的 binding tag 问题，但只改 DTO 不够；usecase 里仍然会在读旧用户前返回 `ErrUserDepartmentRequired` / `ErrUserRoleRequired`。
2. 只做“允许空 role_ids”也不够，因为当前 update 路径还会把请求里的 `department_id` 和 `role_ids` 回写到超管对象。超管分支必须显式冻结这两个字段。
3. 当前没有对应的 `.github/acceptance` 用户验收脚本，因此改为依赖本地验证。
4. backend 的 full compose 重建成功，并已用 curl 实测超管空角色更新返回 `SUCCESS`；admin/store 在同步改动后再次 full compose 重建时，builder 因 `ent` 编译触发 `cannot allocate memory` 失败，所以这两端只完成了编译与 swagger 契约校验，未包装成“已完成运行时验证”。

## 可复用模式

- 当 update 规则依赖“旧对象是否属于特殊类型”时，参数校验不能一律前置到查旧对象之前。
- 如果某类对象的部分字段在业务上不可编辑，修复时不要只放宽校验，还要在写入前冻结这些字段，避免把“允许请求通过”误做成“允许非法改写”。
- 改动请求绑定约束后，应同步更新 swagger 生成物，否则文档会继续诱导调用方按旧契约集成。
- 当相同用户模型在 admin/backend/store 多端并行存在时，这类超管边界修复必须成组同步，否则问题只会在另一个服务里复现。