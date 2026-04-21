# Decision 001: 编码规范与分层约束

> 状态: accepted
> 日期: 2026-03-05

## 背景

项目由人 + AI agent 协作开发，需要统一的编码规范避免风格不一致。

## 结论

### 代码格式
- Go 1.26，`gofmt` 格式化
- 单行超过 120 字符时，参数各占一行，返回值独占一行缩进对齐

### Domain 层接口规范
- Repository：`FindByID`（单表）/ `GetDetail`（含关联）/ `Create` / `Update` / `Delete` / `GetXxx`（分页）/ `Exists` / `ListByIDs` / `ListBySearch` / `IdsByFilter`
- UseCase：`Create` / `Update` / `Delete` / `GetXxx`（详情+分页）/ `SimpleUpdate` / `ListBySearch`
- UseCase 方法签名含 `User` 参数，Repository 不含

### Repository 层
- `convertXxxToDomain` — ent → domain 转换
- `buildFilterQuery` — 构建查询条件
- `orderBy` — 构建排序

### UseCase 层
- UseCase 之间不可互相调用
- UseCase 不可引入 fx 包
- 读方法 + New 放一个文件，写方法按用途拆文件

### API 层服务划分
- admin（运营后台）/ backend（品牌后台）/ store（门店后台）/ eventcore（Dapr 事件订阅）/ frontend（local server 调用）/ taskcenter（任务中心）/ customer（扫码点餐 H5）

## 后果

- 所有新代码必须遵循上述规范
- AI agent 生成代码时以此为约束
