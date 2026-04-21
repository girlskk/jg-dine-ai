# 基础设施知识

> 来源 threads: eventcore-local-startup-migration-debug, scheduler-periodic-config-binding-root-cause, product-sale-export-runtime-i18n-download-fix, rm-client-provider-centralization, operate-log-async-context-cancel, backend-handler-curl-acceptance-expansion, backend-log-list-handler-tests, pos-api-service, storage-object-io-convention, shift-record-local-seed, order-sale-summary-curl-verification, dine-table-qrcode-h5-link

## Docker Compose 排查

- 容器配置了 `restart: always` 时排查启动失败，先查完整容器日志，不看 `--tail` 尾部噪音
- 排查顺序：先确认容器是否被重建过 → 查旧容器日志 → 看完整日志前 100~200 行 → 搜 `panic|fatal|start failed|OnStart hook failed` → 确认第一次错误后再看次生现象.docker logs $(docker compose ps -q eventcore) 2>&1 | rg -n 'panic|fatal|start failed|OnStart hook failed|auto migration failed|error' | head -n 200
- `127.0.0.1:50001` Dapr 超时可能只是 restart loop 后的次级症状，真正根因可能在首次启动的 migration 或配置绑定失败
- `eventcore` 数据库迁移入口在 `bootstrap/db.NewClient` 的 `OnStart` hook
- 临时关闭 `restart` 保留首次失败现场：改成 `restart: "no"` 或前台启动
- 纯查询接口联调不依赖上游服务时，可用 `--no-deps` 拉起目标服务
- 如果服务路由 404 先查 handler 是否注册进 fx module，别误判成鉴权或数据问题

## configor 绑定

- configor 嵌套 struct 字段名必须严格对齐 TOML section 名。字段名就是映射入口，不一致会导致整段配置不加载
- scheduler periodic 启动失败会放大成基础设施表象：注册阶段的 `Cron` 缺失让人误判为 Dapr/Docker/sidecar 问题

## Blob / MinIO

- `CONFIGOR_BLOB_ACCESSDOMAIN` 只表示访问域名，不承担 bucket 语义。bucket 是否出现在 URL 路径里由 `bootstrap/blob` 的 `UsePathStyle` 在代码层决定
- 本地 MinIO 初始化脚本不能写内联 shell 注释：compose 的 `#` 会吞掉后续命令
- 对象存储 key 与 URL 转换：domain 对象存 key，导出或 API 需要 URL 时通过 `Storage.GetURL` 显式转换

## Scheduler 与 Dapr

- scheduler 调 taskcenter 必须走 Dapr service invocation，不回退到直连 HTTP
- `DownloadTaskResult` 只回传 `FileKey`，文件名以建任务时写入的 `Task.FileName` 为准

## RM Client Provider

- `domain.RMClientProvider`：只负责基于调用方传入的 `RMClientReq` 构造 ready-to-use `rmsdk.Client`。不要在 provider 内部写死 `ThirdAccountRepo` 查询，因为不同调用方的 RM 配置来源可能不同
- 调用方负责解析自己的 RM 配置来源，并在需要时自行完成私钥解密后，再把显式凭据交给 provider
- `rmsdk.NewClient` 只是组装配置 struct，本身开销很小；没必要维护长期 `clientCache`
- token cache / token lock 必须按“配置指纹”隔离，而不是只按 `client.ID`。否则密钥轮换后可能误用旧 token
- token 策略：先 access token 缓存 → miss 后尝试 refresh token → 再失败回退 client credentials
- 依赖 `domain.DataCache`，不直接依赖底层 `redis.UniversalClient`
- 新的 RM 接入不要再复制 `StorePaymentAccountRepo + util.RefreshRMToken` 那套分散写法；应由调用方先定位配置，再把显式凭据交给 adapter 服务
- 外部 SDK token 生命周期处理应收敛在 adapter 服务里，调用方只拿 ready-to-use client

## curl 验收脚本

- `testdata/test/api/backend/handler/` 下的结构：`common.sh` 负责登录/query 组装/curl 打印/执行；每个 handler 对应独立 `.sh`
- 每个接口至少覆盖最小参数请求和完整参数请求
- 脚本内建四件事：登录拿 token、打印可复制 curl、允许环境变量覆盖筛选条件、直接输出 HTTP 状态
- 支持 `DRY_RUN=1` 只打印不执行
- create 响应不回 ID 时按唯一名称回查列表提取首个资源 ID
- 复杂 JSON body 用 here-doc，不堆在一行转义字符串里
- minimal/full 双用例不一定能复用同一份前置资源（如还款后同一条消费记录不能再还）

## 本地造数

- 造数前先查 live schema 和现有主数据，不凭 domain struct 猜表结构
- 用固定主键 + `ON DUPLICATE KEY UPDATE` 保持可重复
- JSON 字段填满，避免假数据（主表字段完整、详情字段空壳）
- 如果无法重新构建服务，明确标注验证的是"运行中容器行为"，不包装成"最新源码验证"

## 本地 migration

- 本地开发阶段不需要为每次 schema 调整补 migration。用户明确"上线前统一处理"。只有在当前必要场景才添加迁移文件
