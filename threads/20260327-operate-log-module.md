# Thread: 操作日志模块全链路实现与五轮反馈收敛

> 日期: 2026-03-27 ~ 2026-03-30
> 标签: #operate-log #middleware #ent #i18n #domain #repository #api #backend #store #reflect

## Context

需求：为 backend / store 后台新增操作日志功能，记录管理后台用户的所有写操作（新增、编辑、删除、导出等），包括请求/响应数据、操作人信息、IP 地址等，供后台查询审计。

## 关键决策

### 第一轮 — 初始实现

1. **中间件架构**：采用三层中间件设计
   - `pkg/ugin/middleware/operate_logger.go`：核心共享逻辑（拦截请求/响应、提取数据、异步写库）
   - `api/backend/middleware/operate_logger.go`：backend 平台特化（提取 backend 用户信息）
   - `api/store/middleware/operate_logger.go`：store 平台特化（提取 store 用户信息）

2. **Handler 声明式注册**：通过 `OperateLogs() []OperateLogRoute` 接口让每个 handler 声明需要记录的路由，中间件启动时收集所有路由并构建 map

3. **完整分层**：domain（接口 + 模型）→ ent schema → repository → usecase → middleware → handler → fx wiring

### 第二轮 — 结构性修正（6 个问题）

1. **移除 path/method 查询过滤**：操作日志不需要按路径/方法筛选，前端不会用
2. **UserExtractor 返回值改为结构体**：原来返回多个值（userID, username, realName, merchantID, storeID, platform, loginChannel），参数过多。收敛为 `*domain.OperateLogUser` 结构体
3. **ResData 只存 data 部分**：响应体中 code/message/data 三层结构，ResData 只需存 `data` 字段（业务数据），不存完整响应
4. **response.Ok/OkWithCode 统一出口**：所有成功响应都经过 `response.Ok`，所以只需从 JSON 中提取 `data` 字段
5. **新增 action 和 service 枚举**：`OperateLogRoute` 增加 `Action`（create/update/delete/export/import/enable/disable）和 `Service`（merchant/store/product/user/role）字段，标识操作类型和业务模块
6. **不需要手动 migration**：ent auto-migrate 会自动处理 schema 变更

### 第三轮 — DB 类型 + 字段补全 + i18n（3 个问题）

1. **action/service 用 string 存储而非 enum**：ent schema 使用 `field.String().MaxLen(50)` 而非 `field.Enum()`，程序中仍用 Go 命名类型（`OperateLogAction`/`OperateLogService`），repository 做显式类型转换。原因：避免每次新增类型都要执行数据库迁移
2. **code/err/message 字段必须保留**：虽然 ResData 只存 data 部分，但响应的 code、err、message 仍需作为独立列存储，否则这些信息会丢失。`err` 和 `message` 使用 `field.Text()` 而非 `field.String()` 因为长度不可控
3. **API 响应需要 i18n 翻译**：action 和 service 返回给前端时需要翻译为对应语言的标签。创建 `OperateLogItem` 响应 DTO，增加 `ActionLabel` 和 `ServiceLabel` 字段

### 第四轮 — 枚举补全（本次）

根据产品需求表补全所有操作类型和业务模块：
- OperateLogAction：从 7 个扩展到 18 个（新增 enable_sale/disable_sale/create_subcategory/distribute/issue_coupon/view_data/set_default/change_password/configure_permission/download/retry）
- OperateLogService：从 5 个扩展到 49 个（覆盖商品管理、餐厅管理、数据分析、异常、基础管理、优惠券、财务等全部模块）

## 最终方案

### 文件清单

| 文件                                       | 职责                                                               |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `domain/operate_log.go`                    | 领域模型、枚举常量（18 个 Action + 49 个 Service）、接口定义       |
| `ent/schema/operatelog.go`                 | Ent schema，action/service 用 `field.String()` 存储                |
| `repository/operate_log.go`                | Ent 仓储实现，含 `string()` / `domain.OperateLogAction()` 类型转换 |
| `usecase/operatelog/operate_log.go`        | 用例层，透传读写                                                   |
| `pkg/ugin/middleware/operate_logger.go`    | 核心中间件：路由匹配、请求/响应拦截、异步写库                      |
| `api/backend/middleware/operate_logger.go` | Backend 用户提取器                                                 |
| `api/store/middleware/operate_logger.go`   | Store 用户提取器                                                   |
| `api/backend/handler/operate_log.go`       | Backend 列表 handler + `toOperateLogItem` 转换                     |
| `api/store/handler/operate_log.go`         | Store 列表 handler + `toOperateLogItem` 转换                       |
| `api/backend/types/operate_log.go`         | Backend 请求/响应类型（含 `OperateLogItem`）                       |
| `api/store/types/operate_log.go`           | Store 请求/响应类型（含 `OperateLogItem`）                         |
| `pkg/i18n/enum.go`                         | `OperateLogActionLabel` / `OperateLogServiceLabel` 翻译函数        |
| `etc/language/zh-CN.toml`                  | 中文翻译（18 个 Action + 49 个 Service）                           |
| `etc/language/en-US.toml`                  | 英文翻译（18 个 Action + 49 个 Service）                           |

### 核心机制

- **中间件拦截**：替换 `gin.ResponseWriter` 捕获响应体，从 JSON 中提取 `code`/`data`/`message`/`err`，`ResData` 只存 `data` 部分
- **异步写库**：`go func()` 异步写入，不阻塞请求响应
- **声明式路由**：handler 实现 `OperateLogs()` 接口声明需记录的路由
- **DB 扩展性**：action/service 在 DB 中为 string，Go 代码中为命名类型枚举，新增值无需 migration

## 踩坑与偏差

1. **UserExtractor 参数爆炸**：初版返回 7 个值，review 后收敛为结构体。教训：函数返回值超过 3 个就该用结构体
2. **ResData 全量存储 vs 只存 data**：初版存完整响应体，但 code/message 已有独立字段，data 才是业务审计关键。收敛后 ResData 只存 `data`，code/err/message 走独立列
3. **忘记恢复 code/err/message 字段**：在"ResData 只存 data"的修改中，误以为 code/message 不需要了，删除了这三个字段。用户指出后恢复
4. **ent Enum vs String 选择**：初版用 `field.Enum()` 存储 action/service，但每次新增枚举值都需要数据库迁移。改为 `field.String()` 后需要在 repository 层做显式类型转换
5. **err/message 长度问题**：初版用 `field.String()` 存储 err 和 message，但错误信息可能包含完整堆栈或大段文本，长度不可控。改为 `field.Text()` 无长度限制
6. **类型转换遗漏**：将 ent schema 从 Enum 改为 String 后，ent 生成的 `SetAction`/`SetService` 接受 `string` 类型，但 domain 模型用 `OperateLogAction`（named string type）。需要在 repository 中添加显式 `string()` 和 `domain.OperateLogAction()` 转换
7. **i18n user 翻译不准确**：zh-CN 中 USER 翻译为"用户"，但产品表中对应的是"人员"。已修正
8. **reset_password 用 Update 而非 ChangePassword**：密码重置不是编辑操作，应映射到专用 Action
9. **商品/套餐共用 Service → 无法区分**：同一 handler 操作不同实体时必须拆分 Service
10. **菜单/菜单组共用 Service → 无法区分**：同上
11. **口味做法子项共用 Service → 删除日志混淆**：操作对象层级不同应用不同 Service
12. **CreateSubcategory 作为 Action**：用动作表示对象差异是错误的设计，应通过 Service 区分

---

> 可复用模式与反思已提取至 [knowledge/operate-log.md](../knowledge/operate-log.md)，按需查阅。
