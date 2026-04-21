# Thread: RM Client Provider Centralization

> 日期: 2026-03-31
> 标签: #rm #sms #third-account #adapter #usecase #reflect

## Context

支付、短信、会员等模块都需要调用 RevenueMonster，但现状是每个 usecase 自己查配置、自己解密私钥、自己构造 `rmsdk.Client`、自己拉 token。

这导致三个问题：

1. RM client 初始化逻辑散落在业务层，重复且难以纠错。
2. token 获取逻辑和缓存策略无法统一，已有 `util.RefreshRMToken` 也不可靠。
3. 短信 provider 根本没有 merchant 维度配置输入，实际上不可能按品牌正确调用 RM。

本次用户明确要求：

- 不动现有支付模块实现。
- 基于 `ThirdAccountRepo` 的 `merchantId + thirdAccountType` 唯一配置做新封装。
- 调用方对 refresh/access token 无感知，直接拿可用 client。
- 在 domain 抽象接口，在正确层实现，并先接到短信调用链上。

## 关键决策

1. 新能力定义为 `domain.RMClientProvider`，而不是 repo 或 util。
原因：它既依赖 repo 读取品牌配置，也依赖 Redis 做 token 缓存，还要落到 RM SDK，属于典型基础设施服务，不该继续散在 usecase。

2. 实现在 `adapter/rmclient`，并通过 `adapterfx` 注入。
原因：这样 usecase 和短信 provider 只依赖 domain 接口，不直接掌握解密、缓存、refresh grant、client credentials grant 细节。

3. token 策略改为“先 access token 缓存，miss 后尝试 refresh token，再失败回退 client credentials”。
原因：相比直接照搬旧逻辑，这个顺序对调用方无感知，同时对失效 refresh token 更稳健。

4. `RevenueMonsterClientProvider` 应依赖 `domain.DataCache`，而不是直接依赖底层 `redis.UniversalClient`。
原因：RM client provider 只需要缓存抽象，不需要绑定具体 Redis 客户端实现；依赖 `DataCache` 更符合分层，也更利于测试替换。

5. 短信 provider 请求增加 `merchant_id`，RM 短信 provider 改为真实调用 RM SDK。
原因：没有 merchant 维度就无法从 `ThirdAccountRepo` 取品牌配置；之前 provider 只是伪造成功响应，不是真实集成。

## 最终方案

核心变更：

- `domain/rm_client.go`
  - 新增 `RMClientProvider` 接口。
  - 定义 `ThirdAccountTypeSMS = "sms"` 常量。

- `adapter/rmclient/client.go`
  - 新增 `RevenueMonsterClientProvider`。
  - 通过 `ThirdAccountRepo.FindOneByMerchantIDAndType` 获取品牌账号。
  - 用 `AuthConfig.MK` 解密 RM 私钥。
  - 构造 `rmsdk.Client` 并自动补齐 `AccessToken`。
  - 依赖 `domain.DataCache` 缓存 access token / refresh token，并在 refresh 失败时回退 client credentials。
  - 当 SDK 预留 60 秒安全窗口后 TTL 非正数时，回退使用真实 `ExpiresIn` 秒数；如果仍非正数则直接报错，不再盲目缓存 1 分钟。

- `domain/sms.go` + `usecase/sms/process_sms.go`
  - `SMSProviderReq` 保留 `merchant_id`，因为短信 provider 实际需要它来选择品牌维度 RM 账号。
  - `SMSProvider.Send` 维持 `Send(ctx, req)` 单参数形式，避免把同一个上下文从 DTO 中拆出来再作为并列参数重复透传。
  - 短信处理链把品牌 merchant 填入 provider 请求，由 provider 内部完成账号选择。

- `adapter/sms/rm/sms.go`
  - RM 短信 provider 注入 `domain.RMClientProvider`。
  - 发送前按 `merchantId + sms` 获取 ready-to-use RM client。
  - 改为真实调用 `SendSms`，不再伪造成功响应。

- `adapter/adapterfx/adapterfx.go`
  - 注入 `domain.RMClientProvider` 的实现。

- `adapter/rmclient/client_test.go`
  - 补充单测，覆盖 access token 命中缓存和 refresh 失败回退 client credentials 两条关键路径。

## 踩坑与偏差

1. 首轮测试失败不是实现逻辑问题，而是测试里用了非法长度的 AES key。
修正为 16 字节测试密钥后通过。

2. 一开始短信 provider 文件路径读错了一次，暴露出当前 adapter/sms/rm 目录命名不够直观，但不影响本次实现。

3. 这次严格按用户要求没有回头改支付 usecase，避免把“先搭中心化能力”变成“大面积替换支付链路”的额外风险。

## Verify

已执行：

- `gofmt -w domain/rm_client.go domain/sms.go usecase/sms/process_sms.go adapter/rmclient/client.go adapter/rmclient/client_test.go adapter/sms/rm/sms.go adapter/adapterfx/adapterfx.go`
- `go test ./adapter/rmclient ./adapter/sms/rm`
- `go test ./adapter/... ./usecase/sms`

结果：全部通过。

---

> 可复用模式与反思已提取至 [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
