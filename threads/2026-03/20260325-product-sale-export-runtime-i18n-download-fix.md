# Thread: 商品销售导出接口整链路调试复盘

> 日期: 2026-03-25
> 标签: #report #taskcenter #backend #scheduler #dapr #i18n #download #minio #docker-compose #runtime #reflect

## Context
这两个导出接口的调试不是一次性修完的，而是经历了多轮跨层排障：

1. 先补齐 backend 创建任务、scheduler 扫描任务、taskcenter 回调处理、backend 提供下载对象查询的异步链路。
2. 随后在真实联调里暴露出多类运行态问题，范围横跨 scheduler、taskcenter、中间件、blob 配置、MinIO 初始化和 i18n 启动。
3. 用户多次明确反馈了几条不能回退的约束：
   - scheduler 下的 task 不要直接依赖 `fx`
   - `DownloadTaskResult` 继续使用 `FileKey`
   - scheduler 必须通过 Dapr 调 taskcenter，而不是直连 HTTP
   - 总结必须覆盖这两个导出接口整个调试过程中踩过的坑，而不是只记录最后一次问答

最终目标不是“接口返回 200”，而是整条链路真实可用：任务创建、scheduler 调度、taskcenter 执行、文件上传、backend 返回下载对象、真实下载 xlsx、表头与枚举值符合 locale。

## 关键决策
1. 把“实现导出功能”和“跑通异步链路”分开处理。
   功能代码先落地，但是否真可用必须由本地 compose 联调验证，而不是靠编译通过自我安慰。
2. scheduler 调 taskcenter 的路径坚持走 Dapr service invocation。
   即使直连 HTTP 更快看到结果，也不能为了临时联调破坏用户明确要求的运行方式。
3. scheduler task handler 不直接依赖 `fx` 注入细节。
   调整 wiring 时要把 Dapr client 通过模块参数注入到 handler，而不是把 task 目录变成启动层的延伸。
4. 下载任务结果只回填 `FileKey`，文件名以前置生成的 `Task.FileName` 为准。
   用户已经明确纠正过这一点，继续引入第二个文件名来源只会把任务契约重新搞乱。
5. taskcenter 的错误处理中间件必须真的加入执行链。
   仅仅 provide 了 `ErrorHandling` 还不够，如果 middleware order 没挂进去，callback 失败时仍可能表现成空 `200`。
6. 不从日志猜导出内容是否翻译，直接检查真实 xlsx 的 `xl/sharedStrings.xml`。
   这样能精确区分“locale 传递了但 bundle 没初始化”和“表头/枚举翻译代码没写”两类问题。
7. taskcenter 必须显式加载 `i18nfx.Module`。
   导出 usecase 虽然会用 `payload.Locale` 恢复 context，但如果进程级 bundle 没初始化，`i18n.Translate` 仍会退化为 message ID。
8. `CONFIGOR_BLOB_ACCESSDOMAIN` 只表示访问域名本身，不承担 bucket 语义。
   bucket 是否出现在 URL 路径里，应由 `bootstrap/blob` 按 `UsePathStyle` 在代码层决定；把 `/dine` 硬塞进 `AccessDomain` 是对配置含义的污染。
9. 本地 MinIO 初始化脚本不能写内联 shell 注释。
   compose 的 `#` 会吞掉后续命令，导致 bucket 和匿名下载策略“看起来配了，实际上没执行”。

## 最终方案
1. backend 暴露两个导出接口，创建 download task，并在建任务前生成本地化文件名写入 `Task.FileName` 与 payload。
2. scheduler 使用 Dapr client 调 taskcenter callback，不回退到直连 HTTP，同时保持 task handler 不直接依赖 `fx`。
3. taskcenter 注册商品销售明细/汇总 callback handler，并把 `ErrorHandling` middleware 真正挂进执行链，避免内部报错被伪装成空 `200`。
4. taskcenter 启动 wiring 中增加 `i18nfx.Module`，修复导出表头和枚举值只输出 message ID 的问题。
5. local compose 中修正 blob 相关配置与 MinIO 初始化：
   - 统一使用 `CONFIGOR_BLOB_ACCESSKEYSECRET`
   - `minio-init` 显式执行 `mc alias set`、`mc mb --ignore-existing`、`mc anonymous set download`
   - `CONFIGOR_BLOB_ACCESSDOMAIN` 保持为纯 domain：`http://localhost:9000`
6. `bootstrap/blob` 在生成 `accessPrefix` 时按 `UsePathStyle` 决定是否自动把 bucket 拼入 URL 路径：
   - path-style：`AccessDomain + Bucket + BucketPrefix + key`
   - non-path-style：`AccessDomain + BucketPrefix + key`
7. 在最终配置下重新创建并验证 fresh 任务：
   - 中文明细：`05ba080d-ef98-4ef9-9b83-21e74cbca79c`
   - 英文汇总：`6c803249-93f1-478c-9aff-f01ee12fce6e`
8. 验证标准不是单点接口，而是整链路：
   - task 终态为 `success`
   - backend `/common/task/{id}/download-url` 返回可直接下载的对象 URL
   - 真实下载的 xlsx 中 sharedStrings 不含原始 message ID

## 踩坑与偏差
1. 第一阶段最容易自欺的点，是把“代码写完并编译通过”误当成“导出链路可用”。真实问题都出在运行态联调里。
2. scheduler 调用 taskcenter 时，如果为了省事改成直连 HTTP，短期看是提速，长期看是在绕开用户已经点名要求保留的真实架构。
3. scheduler/task 目录一旦直接吃 `fx` 依赖，会把调度逻辑和启动层粘死；这类方便是假的方便。
4. `DownloadTaskResult` 一旦重新引入 `FileName`，任务记录和 callback 结果就会形成双来源，后面一定有人不知道该信哪个。
5. taskcenter callback 里 provider 虽然有 `ErrorHandling`，但 middleware order 没挂上时，内部失败仍可能返回空 `200`，这类假成功比显式失败更难排查。
6. blob 凭据环境变量写成错误名字时，表现不是“明显启动失败”，而是导出到上传阶段才报错，排障路径会被拉得很长。
7. 只看 backend 返回的 `download-url` JSON 会误判为“下载正常”；必须直接 `curl` 这个 URL，才能发现它可能只是结构正确、实际 `403`。
8. 先把 `/dine` 硬塞进 `CONFIGOR_BLOB_ACCESSDOMAIN` 虽然能把本地验证先跑通，但语义是错的。真正的修复应该在 URL 组装逻辑里按 path-style 自动补 bucket，而不是污染配置名。
9. 直接从 MinIO 数据目录看对象会被底层布局误导，验证导出内容时应该优先走真实对象下载，再解压 xlsx 检查 sharedStrings。
10. 本地 compose 的 shell entrypoint 里写注释是高风险操作，命令很容易表面存在、实际全被注释吞掉。

---

> 可复用模式与反思已提取至 [knowledge/report.md](../knowledge/report.md)，按需查阅。
