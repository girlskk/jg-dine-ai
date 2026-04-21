# 跨模块硬约定

> 索引：8 个小节

---

## 分层职责

### usecase 与 repository 职责边界

- UseCase 负责编排、事务、权限校验、多记录业务规则。Repository 只负责 CRUD 和错误映射。
- "启用互斥、禁用其他"这类跨记录规则必须在 useCase 事务编排；repository 不承载。
- UseCase 不直接依赖 `fx` 装配语言。当跨模块 usecase 复用时，依赖应通过参数注入。

### domain service 与业务写操作

- 当写操作需要 `DataStore` 和多个仓储调用时，应拆成 domain service（如 `ChargeAccount`）而非 usecase。
- Domain service 构造器吃 `ctx` + `DataStore` + 必要领域依赖（如 `DailySequence`）。
- 支付、退款、状态变迁这类多步操作落在 domain service 内聚为完整原子性。

### Repository 接口与查询细分

- 单条查询用 `FindByXxx → (*Entity, error)`；列表查询用 `GetXxx → (slice, total, error)` 或 `ListXxx → (slice, error)`。
- 仅提取特定字段的查询新增独立方法（如 `GetSimpleProducts`），不用参数 flag。
- 全量查询和分页查询拆分方法，不用 `pager=nil` 复用一个接口。

---

## 读模型

### StorageObject I/O 约束

- 写接口（DTO）继续接收 `string` key。
- 读模型（Domain）统一返回 `StorageObject` 结构体。
- Handler 在进入 usecase 前把 string key 转换为 `domain.NewStorageObjectFromKey(...)`。
- Repository 可空图片字段写库时先判有无 key 才执行 `Set/Clear`。

### 报表与订单快照字段

- 订单销售汇总 `Amount` 包含 `RoundingAmount`；不再冗余存储 `OrderSaleSummary.RoundingAmount`。
- 第三方拆分用独立 JSON 字段（如 `ThirdPartyPlatform`）而非堆标量列。
- 订单快照中 tax rate 需冗余存储 `tax_code_type` 固定目录代码；报表按代码分类而非按数值税率。
- 报表 Total 应按 Subtotal 重新计算而非信任历史快照；历史数据可能被污染。

---

## 列表查询与过滤

### Filter 与 Pager 签名

- 列表接口统一签名：`GetXxx(ctx, pager *Pagination, filter *XxxFilter) (slice, total, error)`。
- Handler 直接透传 `pager` 给 usecase；不拆解 `page/pageSize`。
- 当查询语义与现有 filter 差异大时，新建专用 filter（如 `StoreRankedFilter` 对应排名查询）。

### StoreID 与多门店

- API filter 用单值 `StoreID uuid.UUID`；repository 用 `StoreIDEQ` 而非 `StoreIDIn`（前端不会同时传多个）。
- 多门店订单的 parent 记录保持 `store_id=uuid.Nil`；child 按 `parent_order_id` 而非 `parent_uuid` 查关联。
- 查询 child 的退款/支付明细等关联数据时，统一基于 `parent_order_id` 的主单概念。

---

## 错误处理与 HTTP

### 错误映射一致性

- 资源不存在用 404；唯一性/状态冲突用 409；权限/状态阻断用 403；参数非法用 400。
- login 错误单独处理：认证失败（`UserNotFound/PasswordIncorrect`）→ 401；账号禁用/部门禁用/渠道禁用 → 403。
- 当相同 domain 在 admin/backend/store 多端并行时，`checkErr` 应抽到 domain 级 helper 复用。

### 深层调用链错误

- 若业务链路包含 `VerifyUserRoleCanLogin` 或 `UserRoleRepo.FindOneByUser`，必须把相关错误视为实际错误面。
- 不能只映射浅层 handler 调用的显式错误；要沿整个调用链扫描可能的业务错误。

---

## 快照与持久化

### 快照幂等与去重

- 报表类快照按 `business_date + storeID` 存在性校验；命中则跳过重新生成。
- 通过 repository `ExistsByBusinessDate` 做前置检查而不是先删后插。
- 批量操作前用 `Count...` 获取总数；不要用列表接口的 `total` 偷懒。

### 聚合态与明细表

- 支付/退款既保留聚合态（`refund_status/refunded_amount`）也拆出明细表；聚合态支撑列表过滤，明细表保存流水。
- 创建聚合时从明细取最新状态；后续更新也要同步两边；不允许单边更新造成不一致。

---

## 配置与多语言

### 配置共享与分离

- 跨服务用到的配置放在共享 `domain.AppConfig`；用默认值避免服务启动失败（如 `TableQRCodePagePath`）。
- 业务逻辑不要写进 `bootstrap` 装配层；`backendfx` 只负责 Fx wiring，不承载业务编排。
- 单个服务的配置收敛到该服务的 bootstrap；`eventcore/taskcenter` 如需共享 usecase 也要补齐所需 bootstrap 导出（如 `Auth`）。

### 导出多语言与前置文件名

- 导出 payload 包含 `locale` 和 `file_name`；前端在创建任务前生成本地化文件名，不等任务完成才生成。
- 枚举翻译键按 domain 原始类型命名（如 `CHANNEL_POS`、`DINING_WAY_DINE_IN`）而非按报表字段。
- `i18n.Translate` 保持 message ID 回退；短信等渠道不能依赖某个特定 key 存在。

---

## API 层分层

### 文件导出与异步任务

- 同步/异步导出用 300 条阈值分流；仅 `OrderSaleSummary/ShiftRecord/DineTable` 走分流，`ProductSaleDetail/Summary` 保持纯异步。
- 直出结果也要落表记录（`run_mode=sync_direct`）；不能只返回文件导致列表追踪缺失。
- 任务 callback 执行时按 locale 恢复 i18n context；taskcenter 启动补齐 `i18nfx.Module`。

### 域基础设施服务中心化

- RM client 等基础设施 provider 在 `adapter` 层实现，通过 `adapterfx` 注入。
- Provider 只接收显式凭据，不假设配置来源；调用方负责解析自己的配置。
- Token 缓存按配置指纹隔离，支持凭据轮换后自动过期。
- 短信/支付等调用方先从 `ThirdAccountRepo` 查自己的配置，再组装 DTO 传给 provider。

---

## 业务约束

### 税费与支付

- 税费按品牌固定四类（零税/免税/6%/8%）；门店不单独配置；新建品牌自动初始化四条。
- 订单支付快照包含完整来源数据（包括非落库的 account 类）；落库仍保留 `cash/bank_card` 限制。
- 支付/退款快照覆盖时按多个 `paymentType` 一次批量删除；不要循环删单条。

### 订单编号与多门店

- 多门店 parent 订单生成 `order_no` 时用第一个 child 的 `StoreID` + `DailySequence`；不用 `uuid.Nil`。
- 订单 `parent_order_no` 作为持久化快照字段；child 的导出显示 combined order number 不再做运行时 parent 查询。

### 成员登录与身份

- customer guest token 改为标准 `AuthToken{ID}`；auth 器先查 member 再查 Redis guest 快照。
- 订单统一按 token 中 `user_id` 查询，不区分成员类型；成员类型差异由鉴权中间件和路由权限级别提现。
- 游客操作（如修改支付密码验证码）从 `CustomerUserContext` 取当前用户信息，不再信任客户端入参。
