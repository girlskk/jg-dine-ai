# Thread: backend handler curl 验收脚本扩展

> 日期: 2026-04-01
> 标签: #backend #curl #acceptance #handler #testdata #reflect

## Context

在完成 `sms`、`login_log`、`operate_log` 三个 backend 日志接口的 curl 验收脚本后，用户继续要求把更多 `api/backend/handler` 下的模块补齐到 `testdata/test/api/backend/handler/`，并保持和 handler 文件名一致。

这不是简单复制三份脚本，而是要把不同类型的列表接口统一收敛成同一套执行模式：每个脚本都必须包含一个最小参数请求和一个尽量完整的参数请求，且运行时打印真实 curl。与此同时，`merchant` 并不是列表接口，而是 `GET /merchant` 详情接口，不能继续硬套分页列表模式。

## 关键决策

1. 继续沿用 `common.sh` 作为 shared helper，避免每个脚本都重复实现登录、query 拼接和 curl 打印。
2. 所有新增脚本统一保持“两次请求”结构：最小参数请求 + 完整参数请求。
3. 仅对真正的列表接口默认追加 `page/size`；为 `merchant` 这类非列表 GET 补一个无分页 helper，避免 detail 验收也被污染成伪列表请求。
4. 本轮优先保证脚本覆盖面、命名一致性和 dry-run 可用性，不把“脚本已生成”伪装成“所有接口已真实联调通过”。

## 最终方案

新增以下脚本到 `testdata/test/api/backend/handler/`：

- `additional_fee.sh`
- `tax_fee.sh`
- `charge_customer.sh`
- `charge_record.sh`
- `charge_repayment.sh`
- `department.sh`
- `device.sh`
- `dine_table.sh`
- `ledger_account_type.sh`
- `ledger_account.sh`
- `merchant.sh`
- `order_sale_summary.sh`
- `product_sale_summary.sh`
- `product_sale_detail.sh`
- `remark.sh`
- `role.sh`
- `shift_record.sh`
- `sms_template.sh`
- `stall.sh`
- `store.sh`
- `task.sh`
- `user.sh`

同时扩展 `common.sh`：

- 保留原有 `run_get_request` 处理分页列表请求。
- 新增 `run_get_request_no_pager` 用于 `merchant` 这类非列表 GET。
- 新增 `run_json_request` / `run_public_json_request`，统一承接 `POST` / `PUT` JSON 请求打印与执行。
- 新增 `LAST_RESPONSE` 与 ID 提取 helper，尝试从响应 JSON 中恢复资源 ID，供后续 `get/update/enable/disable` 串联使用。
- 当 create 响应不回 ID 时，新增按唯一名称回查列表并提取首个资源 ID 的 fallback，避免真实联调卡死在 `create -> get/update` 之间。

参数策略：

- 最小请求默认不传筛选参数，只保留公共分页参数。
- 完整请求为每个 handler 填入一组可通过环境变量覆盖的默认筛选值，便于直接执行或局部定制。
- 对依赖前置资源的写接口（如 `device`、`ledger_account`、`user`、`charge_repayment`），脚本会要求通过环境变量提供必要 ID；缺失时明确 `SKIP`，不伪造通过。

非 GET 覆盖策略：

- 在同一个 handler 脚本里补齐除 `export` / `delete` 之外的其他接口。
- 低复杂度资源直接补 `create/get/update/enable/disable` 或等价动作。
- `user.sh` 额外覆盖 `login`、`info`、`logout`、`reset_password`。
- `task.sh` 补齐 `retry` 与 `download-url`。
- `merchant.sh` 仅保留当前登录品牌的详情 GET，因为该 handler 本身就没有列表/写接口。
- 所有非 `export`、非 `delete` 接口统一提升为双用例：至少一条最小参数请求和一条最全参数请求。对于 `enable/disable`、`get/detail`、`simple-list` 这类无额外参数的接口，最小/最全会重复同一路由请求，以保持验收结构一致。

## 验证

已完成：

- 对 `testdata/test/api/backend/handler/*.sh` 做全量 `bash -n` 语法校验。
- 抽样 dry-run `additional_fee.sh`，确认新增脚本已接上 shared helper 并能打印可执行 curl。
- 抽样 dry-run `product_sale_detail.sh`，确认多参数报表接口的 query 串拼接正常。
- 抽样 dry-run `merchant.sh`，确认详情接口已不再带 `page/size`。
- 抽样 dry-run `user.sh`、`store.sh`、`order_sale_summary.sh`，确认混合 `GET/POST/PUT`、大 JSON body、报表最小合法查询三类场景都能打印正确请求。
- 真实运行 `tax_fee.sh`，确认 `POST /tax_fee` 与列表接口都可返回 `HTTP_STATUS:200`。
- 将此前剩余的复杂脚本 `charge_customer`、`charge_repayment`、`device`、`ledger_account`、`role`、`store`、`task`、`user` 也补齐到双用例结构，并再次通过全量 `bash -n` 校验。
- 真实运行并验证 `tax_fee.sh`、`department.sh`、`stall.sh`、`dine_table.sh`：在 create 响应不回 ID 的情况下，通过 fallback 列表回查拿到新资源 ID，随后 `get/update/enable/disable` 或 `get/update` 均成功返回 `HTTP_STATUS:200`。
- 真实运行并验证 `device.sh`：使用已知本地 `store_id` 后，`create -> lookup -> get -> update -> enable -> disable` 全链路返回 `HTTP_STATUS:200`。
- 真实运行并验证 `role.sh`：修正 `set menus` 默认请求体为 `{"role_menus":[]}` 后，`create -> lookup -> get -> update -> enable -> disable -> set menus -> get menus` 全链路返回 `HTTP_STATUS:200`。
- 真实运行并验证 `user.sh`：补齐 `department_id` 写入、创建后按 `real_name` 回查 ID、并让 update 始终针对 full create 的同一用户后，使用本地已启用 seed role + 有效 department 可打通 `create -> lookup -> get -> update -> enable -> disable -> reset_password -> logout` 全链路。
- 真实运行并验证 `ledger_account_type.sh` 与 `ledger_account.sh`：为 `ledger_account_type` 增加 create 后按名称回查 ID 后，可继续打通 `ledger_account_type create/get/update` 与依赖该 type 的 `ledger_account create -> lookup -> get -> update` 全链路。
- 真实运行并验证 `store.sh`：增加 create 后按 `store_name` 回查 ID，并把 create/update 默认 JSON body 从脆弱的内联转义串改为 here-doc 后，成功打通 `create -> lookup -> list -> simple-list -> get -> update -> enable -> disable` 全链路。
- 真实运行并验证 `charge_repayment.sh`：为 minimal/full create 拆分独立 `charge_record_id` 输入，并在 create 后按 `charge_customer_id + repayment_date` 回查 ID 后，成功打通 `create -> lookup -> list -> get` 全链路。
- 真实运行并验证 `charge_customer.sh`：增加 create 后按名称回查 ID 后，成功打通 `create -> lookup -> list -> get -> update` 全链路。
- 已将联调注意事项同步写回对应脚本：`user.sh`、`store.sh`、`charge_customer.sh`、`charge_repayment.sh`，明确记录真实运行中暴露出的依赖前置条件、create 不返 ID 的回查策略，以及 minimal/full 不能复用同一前置资源的约束。

未在本轮完成：

- 未对这 22 个新增脚本逐一做真实 HTTP 联调验收。
- 真实 HTTP 200 验证目前已覆盖 `sms`、`login_log`、`operate_log`、`tax_fee`、`department`、`stall`、`dine_table`、`device`、`role`、`user`、`ledger_account_type`、`ledger_account`，其余脚本仍停留在 dry-run / 语法通过层面。
- `tax_fee` 的 create 响应只返回 `{"code":"SUCCESS"}`，未直接返回新建资源 ID，说明“create 后自动串 get/update/enable-disable”不能假设所有接口都支持，需要额外通过列表筛选或显式环境变量补 ID。
- 剩余未做真实联调的复杂脚本已进一步缩小；`charge_repayment` 已验证通过，但这类脚本仍高度依赖本地有效 seed 数据。

---

> 可复用模式与反思已提取至 [knowledge/infrastructure.md](../knowledge/infrastructure.md)，按需查阅。
