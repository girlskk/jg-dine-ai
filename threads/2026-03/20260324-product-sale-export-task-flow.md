# Thread: 商品销售报表导出任务链路与前置文件名约束

> 日期: 2026-03-24
> 标签: #report #taskcenter #backend #i18n #download #excel

## Context

backend 已有 `ProductSaleDetail` 与 `ProductSaleSummary` 查询接口，但没有异步 Excel 导出。仓库里已有一条可复用的下载任务链路：backend 创建任务 -> taskcenter 回调业务 usecase -> scheduler 将下载结果回填到 task。

用户新增了两个明确约束：

1. 商品销售明细表和汇总表都要通过 task 模块做异步 Excel 导出。
2. 下载任务的文件名不能再等任务处理完成后才写入，而要在创建任务前生成，并随 payload 一起透传给 task 模块。

另外，导出表头必须支持多语言，中文截图只是示例，不应把中文表头硬编码死在导出逻辑中。

## 关键决策

1. 为 `ProductSaleDetail` 和 `ProductSaleSummary` 各自定义独立 export payload，而不是复用一个宽泛的 `sales` payload。
2. 将 `locale` 与 `file_name` 一起放进 payload；taskcenter 回调执行时使用 `i18n.WithLocalizer` 恢复语言环境。
3. backend 创建导出任务时，先生成翻译后的文件名，再通过 `CreateTaskReq.FileName` 和 payload 双写透传。
4. `task_event_type` 细分为 `product_sale_detail_export` 与 `product_sale_summary_export`，避免任务列表里两个导出都显示成同一种“sales”。
5. `DownloadTaskResult` 只回传 `file_key`，不再重复回传 `file_name`；文件名以建任务时写入的 `Task.FileName` 为准。
6. 商品销售明细与商品销售汇总必须使用两个独立的 PathTemplate，命名对齐 `tenant_report_daily` 风格：`tenant_report_product_sale_detail` 与 `tenant_report_product_sale_summary`。
7. 枚举翻译键不按报表字段名命名，而按 domain 原始枚举类型和枚举值命名，例如 `CHANNEL_POS`、`DINING_WAY_DINE_IN`、`PRODUCT_TYPE_SET_MEAL`，避免其他报表重复定义同义键。
8. `file_name` 仍然保留在 payload 中。这里的重复不是坏重复，而是异步任务契约所需的显式快照：task record 负责列表展示与追踪，payload 负责 callback 执行时自给自足。不要为了去掉一个字段，额外引入 header/context 透传这种隐式依赖链。
9. GET 列表接口复用的 DTO 必须保留 `form` tag；即使同一 DTO 也被 POST 导出接口复用，也不能为了 JSON 绑定删掉 `form`，否则 list `ShouldBindQuery` 会直接坏掉。
10. `Platform` 不能在 usecase 里写死成 `PlatformBackend`；应由调用方通过 payload 显式传入，backend 只是当前一个调用方，而不是唯一调用方。
11. dine table 现有下载任务同步改为前置文件名，避免同一仓库里下载任务约束不一致。

## 最终方案

- domain：新增商品销售明细/汇总 export payload，扩展 interactor 接口，新增 task callback path 与 task event type。
- backend：
  - `POST /data/product-sale-detail/export`
  - `POST /data/product-sale-summary/export`
  - 创建任务前按 locale 生成文件名，并将查询过滤条件转成 payload。
- taskcenter：
  - `POST /product-sale-detail/export`
  - `POST /product-sale-summary/export`
  - 回调中解析 payload，调用各自 interactor 的 `ProcessTask`。
- usecase：
  - 两个 interactor 新增 `Export` 和 `ProcessTask`。
  - `ProcessTask` 通过 repository 的 `List...` 接口直接拉全量报表数据，生成本地化表头和枚举值，再通过 `Storage.ExportExcel` 上传。
  - 商品销售明细与商品销售汇总分别写入各自的对象路径模板，而不是共用一个泛化模板。
- i18n：补齐报表导出的文件名、表头、枚举值翻译。

## 用户反馈后的修正

1. 去掉 `DownloadTaskResult.FileName`，避免和 `domain.NewTask(...).FileName` 形成双来源。
2. 去掉错误复用的日报表对象路径模板，改为商品销售明细/汇总各自独立模板。
3. 导出不再依赖列表页分页，而是在 usecase 中直接查询全量数据。
4. `buildProductSaleDetailFilter` / `buildProductSaleSummaryFilter` 收敛为只接收 `user` 和 `req`，日期解析内聚到 builder 内部。
5. language 文件移除 `(P1)` 标记，避免项目阶段信息泄露到正式导出文案。
6. `DINING_MODE` 这种按报表字段名派生的键名不再用于枚举值翻译；`DiningWay` 必须对应 `DINING_WAY_*` 公共键。
7. `DateTime` 这种函数名如果实际只保留到分钟精度，会造成误导；命名必须显式体现精度或格式。
8. 当用户反馈本身会把显式契约改成隐式链路时，不能机械执行，必须先指出问题并确认，否则只是在把复杂度藏起来。
9. `payload/file_name/platform required` 这类导出前置校验不应在 usecase 里散落字符串，应该在 domain 统一定义错误变量，避免后续同类导出继续复制粘贴。
10. repository 层的分页查询和全量查询必须拆成两个方法；导出走 `List...`，列表页走 `Get...`，不要再用 `pager=nil` 复用一个接口。
11. 之前把 grouped 分页改成 `Select().Modify(...)` 那套 helper 化实现是过度设计。这里直接用 ent query 链本身的 `Order(...).Limit(...).Offset(...).GroupBy(...).Aggregate(...).Scan(...)` 更直白，也更接近仓库原有写法。
12. `ProductSaleSummary` grouped 查询不需要单独定义 row struct，直接扫描到 `*ent.ProductSaleSummary` 即可；但 `ProductSaleDetail` 仍要保留自定义 row struct，因为 `attr/toppings` 是 JSON 字段，grouped 扫描阶段需要先接原始值，再由 repository 显式反序列化成 domain 切片。
13. 只有通用数值/日期字符串化职责的 helper，不应悬挂在 `pkg/reportexport` 这种业务感过强的位置；应收敛到 `pkg/util`，避免未来其他导出逻辑因为包名误导而重复造轮子。

## 验证

- `gofmt -w ...` 已执行，覆盖本次所有修改的 Go 文件。
- `go build ./cmd/backend ./cmd/taskcenter` 通过。

## 踩坑与偏差

1. 如果只把表头翻译掉，不处理 `sale_mode/channel/product_type` 这些枚举值，英文导出会变成半英文半代码值，这是典型的伪国际化。
2. 如果继续沿用“任务成功后再写文件名”的旧习惯，任务列表在处理中和失败重试场景下就拿不到稳定文件名，前端体验会持续不一致。
3. 导出全量数据不能直接依赖列表页分页参数；更直接的做法是让 repository 提供独立 `List...` 全量查询入口，而不是在 usecase 层循环翻页。
4. 路径模板如果偷懒做成一个通用 `product_sale_report_export`，后续对象目录、权限策略、生命周期策略都会被耦死，拆分要在一开始做，不要等对象堆积后再迁移。
5. 把分页和全量查询塞进同一个 repository 方法，会逼得 grouped 查询在分页场景下退化成“全量 scan + 内存切片”。这不是技巧问题，是接口语义设计错了。
6. 不是所有 grouped 查询都要强行抽一个 `xxxGroupRow`。如果聚合列和字段类型已经和 ent model 对齐，继续自定义 struct 只是在增加维护面；真正需要自定义 row 的场景，是像明细报表这种带 JSON 字段、需要额外反序列化的查询。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
