# 通用编码与架构约束

> 从 threads 中提取的跨模块通用知识。领域专属知识见同目录下对应文件。

## 分层架构

- UseCase 负责编排，Repository 负责持久化。涉及多记录状态联动（如"启用一个禁用其他"）的逻辑统一放 usecase 事务编排，repository 不承载跨记录业务规则。（`20260310-sms-template-rule-refactor`）
- UseCase 之间不可互相调用；跨模块写操作走 `DataStore.XxxRepo()` 直接调用 Repo。（`20260305-charge-module`）
- UseCase 直接返回 repo 调用结果：纯查询场景直接 `return interactor.DataStore.XxxRepo().GetXxx(ctx, ...)`。（`20260316-report-tables-pattern-conventions`）
- UseCase 文件拆分：读方法 + `New` 放一个文件，不同写方法拆到不同文件。（`20260319-store-rank-refactoring`）
- handler 层职责：request binding → 专用 filter 构建 → 调用 usecase → response 包装。业务默认值和派生值由 usecase 负责。（`20260320-store-rank-pager-filter-convention`, `20260325-order-sale-summary-shift-record-export-corrections`）
- handler 不做业务补全：冗余展示字段由 domain/repository 负责回填。（`20260326-charge-account-domain-service-refactor`）
- backendfx / posfx 等 fx 模块只负责装配，不承载业务逻辑。（`20260401-backend-dine-table-qrcode-config-split`）
- scheduler/task 目录不直接依赖 `fx`。Dapr client 通过模块参数注入。（`20260325-product-sale-export-runtime-i18n-download-fix`）

## 错误处理

- 业务错误规范化链路：Domain 错误常量 → Handler errcode → i18n 文案。避免在 UseCase 拼接自然语言错误字符串。（`20260305-charge-module-repayment-hardening`）
- 单函数内错误变量优先统一 `err`，仅在并行多错误源且同一作用域必须共存时用语义化别名。（`20260306-chargerecord-err-naming`）
- 函数返回值超过 3 个就该用结构体。（`20260327-operate-log-module`）

## OrderBy 标准模板

- 所有新模块 OrderBy 用 `int` + struct + 构造函数模式：`type XxxOrderByType int` + `XxxOrderBy struct { OrderBy XxxOrderByType; Desc bool }` + `NewXxxOrderByField(desc bool)`。（`20260316-report-tables-pattern-conventions`）
- 默认排序链最后一级兜底用 `id`（唯一键），不用 `created_at`（重复会导致分页不稳定）。（`20260318-report-grouped-curl-verification`）

## Filter 约定

- filter 复用判据：只有新接口查询维度与已有 filter 完全一致或是其子集，且语义相同时才复用。差异大时新建专用 filter。（`20260320-store-rank-pager-filter-convention`）
- 列表接口统一签名：`(ctx, pager, filter, ...orderBy) → (slice, total, error)`。（`20260320-store-rank-pager-filter-convention`）
- 列表/导出筛选优先基于稳定标识（如 `storeIDs`），不把前端模糊搜索直接固化为后端过滤契约。（`20260325-order-sale-summary-shift-record-export-corrections`）
- 单值 vs 多值过滤字段：前端只传单个值用 `string` + `uuid.Parse` + `StoreIDEQ`；需要多选才用切片 + `StoreIDIn`。（`20260316-report-tables-pattern-conventions`）

## 轻量查询模式（SimpleList）

- `simple-list` 走独立契约：`SimpleFilter + GetSimple...`，不将分页列表改成多模式接口。（`20260401-admin-merchant-simple-list`）
- 只需少量字段时，新建 `XxxSimple` + `XxxSimpleFilter` + `GetSimpleXxx`，repo 用 `Select()` 限定字段。（`20260320-store-rank-pager-filter-convention`）
- 新增 DTO 前先 `grep` 现有 domain 类型，避免重复声明。（`20260319-store-rank-refactoring`）

## Ent Schema 约定

- 事实表 / 报表 schema 不建 edge：关联 ID 直接存 `field.UUID`，`Edges()` 返回空。（`20260316-report-tables-pattern-conventions`）
- 日期字段指定 SchemaType DATE：`field.Time("business_date").SchemaType(map[string]string{dialect.MySQL: "DATE", dialect.SQLite: "DATE"})`。ent 默认 `field.Time` 生成 `timestamp`。（`20260316-report-tables-pattern-conventions`）
- ent schema 字段多行展开 `.xxx()` 调用链，与项目风格一致。（`20260316-report-tables-pattern-conventions`）
- 新增唯一索引时，本地旧数据必须先去重，否则自动迁移直接失败。（`20260326-eventcore-local-startup-migration-debug`）
- action/service 类枚举 DB 用 `field.String()` 存储（扩展无需 migration），Go 代码用 named type 保持类型安全。（`20260327-operate-log-module`）
- err/message 等长度不可控字段用 `field.Text()` 而非 `field.String()`。（`20260327-operate-log-module`）

## 日期处理

- DATE 列直接 GTE / LTE，不用 `DayEnd`，用 `util.ParseDateOnly`。（`20260316-report-tables-pattern-conventions`）
- DATETIME 列结束日期需 `util.DayEnd(endTime)` 补全到 23:59:59。（`20260316-report-tables-pattern-conventions`）
- 日期解析统一用 `util.ParseDateOnly`（`time.Local`），不用 `time.Parse`（UTC）。错误码用 `errcode.TimeFormatInvalid`。（`20260316-report-tables-pattern-conventions`）

## Swagger 与路由

- Swagger 注解：一行 `@Param data query types.XxxListReq true "查询参数"` 绑定整个 request 结构体。（`20260316-report-tables-pattern-conventions`）
- API 路由用 kebab-case（`/data/product-sale-detail`）。（`20260316-report-tables-pattern-conventions`）

## StorageObject 约定

- 写接口 DTO 保持 string key；查询返回 `StorageObject`；domain 内部一律用 `StorageObject`。（`20260320-storage-object-io-convention`）
- 可空图片字段 repo 持久化前必须显式判断 `.Key` 非空再写入。create: 有 key 才 Set；update: 有 key 则 Set，无 key 且支持 clear 时显式 Clear。（`20260320-storage-object-io-convention`）
- update 时请求传空应显式清空数据库字段，不混淆"没图"和"旧图保留"。（`20260320-storage-object-io-convention`）

## Domain Service 模式

- 当领域动作需要"查多表 + 校验权限 + 生成编号 + 事务写库"时，直接建 domain service（持有 DataStore）。（`20260326-charge-account-domain-service-refactor`）
- 当领域动作包含"创建实体 + 初始化状态"时，优先提供函数式入口返回实体，而非让调用方先构造对象。（`20260325-charge-record-pay-refund-domain-entrypoints`）

## 唯一键查找

- 实体存在唯一业务键时（如 `customer_code`），应优先提供仓储级 `FindByXxx`。（`20260306-pos-charge-feedback-refactor`）

## 冗余字段与 JSON 列

- 只读历史属性（如消费时门店名）冗余存储优于 JOIN。历史数据不因源数据变更而改变。（`20260305-charge-module`）
- 关联只需整体读写且不需反查时，JSON 列 + `JSON_CONTAINS` 是 M2M 替代。配合枚举（all/partial）减少查询。（`20260305-charge-module`）

## Handler 按资源拆分

- API handler 按资源职责单一化，避免一个 handler 混合多实体读写逻辑。（`20260306-pos-charge-feedback-refactor`）

## 新增 API 服务

- 三件套复制策略：`api/<svc>` + `cmd/<svc>` + `bootstrap/<svc>.go`。克隆最相似的已有服务。（`20260306-pos-api-service`）
- 批量替换后必须执行一次最小编译检查（`go test ./cmd/<svc> ./api/<svc>/...`）。（`20260306-pos-api-service`）

## 命名规范

- 命名不绑定调用方场景：`StoreRank` 而非 `CustomerStoreRank`。（`20260319-store-rank-refactoring`）
- 新能力先考虑扩展现有 Interactor 而非新建。（`20260319-store-rank-refactoring`）
- 纯格式化 helper 放 `pkg/util`，只有承载独立业务语义时才值得单独挂包。（`20260324-product-sale-export-task-flow`）

## DTO 与字段约定

- 字段新增时优先放在语义相邻位置（如 `SuccessMessage` 与 `ErrorMessage` 相邻）。（`20260323-task-success-message-propagation`）
- 当 DTO 同时服务 GET query 和 POST JSON 时，同时保留 `form` 与 `json` tag。（`20260324-product-sale-export-task-flow`）
- 新增筛选字段时，Types/Handler/Domain/Repo 四层透传一致性必须核对。（`20260305-charge-module-repayment-hardening`）
- "domain 字段存在但响应恒为空"时先核对 schema、create path 和 filter path。（`20260331-charge-record-customer-type`）

## 并发安全

- 金额字段并发安全更新：优先使用 SQL 表达式原子更新（`AddUsedAmount`/`SubUsedAmount`），避免读改写竞争。（`20260305-charge-module-repayment-hardening`）

## 固定字段值双层兜底

- 关键枚举或状态可采用"usecase 业务约束 + repository 写入兜底"双保险。（`20260310-sms-template-rule-refactor`）

## 指针型过滤条件

- repo `buildFilterQuery` 中指针类型时间字段必须先 nil 判断再做零值检查：`if filter.StartTime != nil && !filter.StartTime.IsZero()`。（`20260401-backend-log-list-handler-tests`）

## 异步上下文

- 请求结束后异步做事的中间件/handler，不能直接把 `c.Request.Context()` 传进 goroutine。用 `context.WithoutCancel` 保留 trace/values 同时避免取消。（`20260330-operate-log-async-context-cancel`）
