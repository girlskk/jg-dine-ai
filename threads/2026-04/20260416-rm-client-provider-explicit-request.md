# Thread: RM Client Provider Explicit Request

> 日期: 2026-04-16
> 标签: #rm #sms #adapter #refactor #reflect

## Context

`domain.RMClientProvider.GetClient` 原先直接收 `merchantID + accountType`，并在 provider 内部写死 `ThirdAccountRepo` 查询、状态校验和私钥解密。

这个设计把“RM client 构造”和“业务配置来源”错误地绑在一起了。用户明确指出：RM 配置不一定存放在 `third_accounts`，所以 provider 不应该擅自假设配置来源；真正知道配置放在哪里的，应该是调用方。

## 关键决策

1. 将 `RMClientProvider.GetClient` 改为接收 `RMClientReq`，只接受显式凭据，不再接受 `merchantID + accountType` 这种需要二次查询的参数。
2. `RMClientReq.ID` 改为 `string`。RM SDK 实际需要的是账号字符串，继续保留 `uuid.UUID` 只会让这个 DTO 无法承载真实配置。
3. 将短信链路中的 RM 配置解析责任下放到 `adapter/sms/rm`。当前短信仍然从 `ThirdAccountRepo` 读取配置，但这只是短信调用方当前的选择，不再是 RM provider 的全局假设。
4. RM provider 保留 token 缓存与刷新职责，不再碰业务仓储和解密逻辑。
5. `rmsdk.NewClient` 本身只是组装配置 struct，不值得为它单独维护长期 `clientCache`；真正需要绑定配置指纹的是 token cache 和并发锁。

## 最终方案

- `domain/rm_client.go`
  - `RMClientProvider.GetClient` 改为 `GetClient(ctx, *RMClientReq)`。
  - `RMClientReq.ID` 改为 `string`。

- `adapter/rmclient/client.go`
  - 移除 `DataStore` 和 `AuthConfig` 依赖。
  - 去掉 `ThirdAccountRepo` 查询、账号状态校验和私钥解密。
  - 只负责校验显式参数、构造 `rmsdk.Client`、补齐 access token。
  - `rmsdk.NewClient` 仍然按次构造，但 access/refresh token 与并发锁改为按 `RMClientReq + runMode` 的配置指纹隔离。

- `adapter/sms/rm/sms.go`
  - 短信 provider 注入 `DataStore` 和 `AuthConfig`。
  - 发送前自行查询短信类型的第三方账号、校验状态、解密私钥，并组装 `RMClientReq`。
  - 之后再调用 `RMClientProvider` 获取 ready-to-use client。

- `.github/knowledge/infrastructure.md`
  - 更新 RM provider 约束，明确 provider 只接显式凭据，配置来源解析留给调用方。

## 踩坑与偏差

1. 原来的 `RMClientReq` 虽然已经存在，但 `ID` 被定义成 `uuid.UUID`，和实际的 RM `account_id` 字符串不匹配。这个问题不修，接口改签名也接不起来。
2. 当前短信调用方仍然使用 `ThirdAccountRepo`，但这已经从“全局强约束”降成了“短信模块当前实现细节”。这正是本次改动要达到的边界收敛。
3. 如果 token cache 仍然只按 `client.ID` 存储，那么即使接口已经改成显式凭据，密钥轮换后也会继续沿用旧 token。这是第二层边界 bug，必须把 token namespace 改成按配置指纹隔离。

## 可复用模式

- 基础设施 provider 如果既负责 SDK client 生命周期，又在内部假设业务配置来源，通常就是边界放错了。
- 正确的拆分方式是：调用方解析自己的配置来源，provider 只消费显式凭据并处理外部 SDK 的连接、token、缓存等通用能力。
- 当外部凭据允许轮换时，token cache 和并发锁必须共享同一份配置版本键或配置指纹，不能继续只按 client ID。