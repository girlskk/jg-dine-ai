# Thread: eventcore 本地启动失败定位到短信模板唯一索引迁移冲突

> 日期: 2026-03-26
> 标签: #eventcore #docker-compose #migration #sms-template #dapr #local #debugging

## Context
本地通过 Docker Compose 启动 `eventcore` 时，服务持续重启。表面现象是应用反复报 `dapr: failed to create client: error creating connection to '127.0.0.1:50001': context deadline exceeded`，容易误判为 sidecar 启动顺序问题。

实际需要确认的是第一次导致 `eventcore` 退出的错误，因为容器开启 `restart: always` 后，后续失败日志会被 Dapr 连接错误覆盖。

## 关键决策
1. 不看 `docker compose logs --tail` 的尾部噪音，直接查完整容器日志。
   通过 `docker logs <eventcore-container-id> | rg 'auto migration failed|start failed|OnStart hook failed'` 抓第一次失败，避免被后续重启日志误导。
2. 先确认数据库迁移入口，再判断错误发生阶段。
   `eventcore` 的自动迁移发生在 `bootstrap/db.NewClient` 的 `OnStart` hook；Compose 为 `eventcore` 设置了 `CONFIGOR_DATABASE_AUTOMIGRATE=true`，所以启动时一定会先跑 Ent migration。
3. 先修数据，不改代码。
   首次失败是旧数据不满足新唯一索引，不是迁移代码本身坏掉。本地库里只有一组冲突数据，直接软删除旧的禁用模板即可恢复启动。

## 最终方案
- 用完整容器日志确认首次失败为：
  `auto migration failed: sql/schema: modify "sms_templates" table: Error 1062 (23000): Duplicate entry '4a2cf54f-5439-4cd2-8eec-06b09a88412d-member_login-0' for key 'sms_templates.smstemplate_merchant_id_biz_type_deleted_at'`
- 定位到 `sms_templates` 本地旧表数据中，同一 `merchant_id + biz_type + deleted_at=0` 有两条记录；其中旧记录已禁用。
- 在本地 MySQL 里将旧禁用记录 `5a076878-351a-4972-80c8-3b537c7e241f` 软删除：`deleted_at = UNIX_TIMESTAMP()`。
- 重新执行 `docker compose up -d --force-recreate eventcore eventcore-dapr` 后，`eventcore` 迁移通过，HTTP 服务监听 `8080`，Dapr sidecar 发现应用并进入 `Running`。

## 踩坑与偏差
1. `docker compose logs --tail=... eventcore` 默认只看到最近几轮重启日志，容易只看到 Dapr 连接超时，看不到第一次迁移失败。
2. `eventcore` 与 `eventcore-dapr` 一起启动时，后续 `127.0.0.1:50001` 超时不一定是根因；它可能只是首次失败后重启链路里的次生现象。
3. `sms_templates` 本地表还是旧结构，只有 `smstemplate_name_deleted_at` 唯一索引；新 schema 要求 `merchant_id + biz_type + deleted_at` 唯一，因此历史脏数据会在 migration 阶段直接炸掉。

---

> 可复用模式与反思已提取至 [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
