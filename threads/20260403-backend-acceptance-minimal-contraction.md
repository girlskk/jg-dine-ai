# Thread: backend 验收脚本 minimal 收敛

> 日期: 2026-04-03
> 标签: #backend #acceptance #curl #minimal #reflect

## Context

用户指出 `.github/acceptance/backend/` 下的脚本存在一个系统性偏差：很多标成 `minimal` 的列表验收实际上仍然通过共享 helper 默认附带 `page/size`，少数报表脚本还在 minimal 默认里塞了伪造 `store_ids`。这会把“最小合法请求”污染成“轻量筛选请求”，使脚本无法准确表达接口最小契约。

本次目标不是扩展覆盖面，而是把每个 backend 验收文件里的 minimal 收敛到真正的 minimal，同时保留 full 用例继续承载可选筛选与分页行为。

## 关键决策

1. 列表接口的 minimal 与 full 明确分工：minimal 不再自动附带 `page/size`，full 继续保留分页与扩展筛选。
2. 不为每个脚本重复实现“无 pager 的 minimal GET”，而是在 `common.sh` 新增统一 helper `run_get_request_minimal`，直接复用 `run_get_request_no_pager` 的 query 组装逻辑。
3. 报表类 minimal 仅保留 DTO 中真实必填的日期区间参数；像 `product_sale_detail` / `product_sale_summary` 这类脚本，把原先默认的伪造 `store_ids` 收回为空，避免 minimal 带入非必填过滤条件。

## 最终方案

修改 `.github/acceptance/backend/common.sh`：

- 新增 `run_get_request_minimal` helper，专门用于“无 pager 的 minimal GET”。

批量调整 backend 验收脚本：

- 所有列表类 minimal GET 全部切换为 `run_get_request_minimal`。
- `order_sale_summary.sh` 的 minimal 只保留 `business_date_start` / `business_date_end`。
- `product_sale_summary.sh` 与 `product_sale_detail.sh` 的 minimal 去掉默认伪造 `store_ids`，保留真实必填日期区间；其余可选筛选只在显式覆盖时才会带入。
- `merchant.sh` 这类本来就走无分页详情 GET 的脚本不做多余改动。
- 追加第二轮 acceptance 修补：
	- `additional_fee.sh`、`remark.sh`、`sms_template.sh` 在 create 后按名称回查 ID，避免 create 不回 ID 时直接跳过后续 get/update。
	- `device.sh`、`ledger_account.sh`、`user.sh` 在构造 write body 前，先自动从现有列表里补齐 prerequisite ID（store / ledger account type / enabled role / enabled department）。
	- `shift_record.sh`、`task.sh`、`charge_repayment.sh` 会从 minimal 列表响应里自动提取现有详情 ID，尽量把只读详情路径跑起来。
	- `task.sh` 将 `retry` 与 `download-url` 的 ID 源拆开，避免强行用同一个任务 ID 同时覆盖“失败任务重试”和“成功任务下载”两种互斥状态。
	- `sms_template.sh` 的 create 默认 `biz_type` 改为 `member_recharge` / `device_offline`，避开本地已有 `member_login` / `member_register` seed 冲突。
	- 最终收口：
		- `charge_repayment.sh` 自动从 `charge-record?status=unpaid` 中为同一客户挑两条未还款记录，直接打通 create。
		- `task.sh` 改为为 minimal/full 分别使用独立 failed task，必要时再用现成 success download task 临时转 fail 作为补样本，避免“第一下 retry 成功后第二下必然 400”。
		- `sms_template.sh` 改为运行时选择当前未占用的非 seed biz type，并在脚本尾部删除本次创建的两条模板，保证可重复执行而不持续占满唯一 biz type 槽位。

覆盖的脚本包括：

- 日志与任务：`sms.sh`、`login_log.sh`、`operate_log.sh`、`task.sh`
- 报表：`order_sale_summary.sh`、`product_sale_summary.sh`、`product_sale_detail.sh`、`shift_record.sh`
- 资源列表：`additional_fee.sh`、`charge_customer.sh`、`charge_record.sh`、`charge_repayment.sh`、`department.sh`、`device.sh`、`dine_table.sh`、`ledger_account_type.sh`、`ledger_account.sh`、`remark.sh`、`role.sh`、`sms_template.sh`、`stall.sh`、`store.sh`、`tax_fee.sh`、`user.sh`

## 验证

已完成：

- `bash -n .github/acceptance/backend/*.sh`
- `cd deploy/overlays/local && docker compose build builder`
- `cd deploy/overlays/local && docker compose up -d && docker compose ps`
- 顺序执行 `.github/acceptance/backend/*.sh`（跳过 `common.sh`），完整日志落在 `tmp/backend-acceptance-20260403/`
- `DRY_RUN=1 bash .github/acceptance/backend/operate_log.sh`，确认 minimal curl 不再带 `page/size`
- `DRY_RUN=1 bash .github/acceptance/backend/product_sale_detail.sh`，确认 minimal curl 仅保留必填日期参数
- 遍历所有 backend 验收脚本的 dry-run 输出，筛查所有 `minimal` GET curl，确认无任何 `page=` 残留
- 真实运行统计：26 个脚本 shell 级全部退出 `0`，共记录 `152` 个 HTTP 响应，其中 `150` 个为 `200`，`2` 个为 `409`
- `2` 个非 `200` 都来自 `sms_template.sh` 的 create，用例默认 `biz_type=member_login/member_register` 与当前本地 seed 冲突，返回 `SMS_TEMPLATE_BIZ_TYPE_EXISTS`
- 本轮真实运行共有 `13` 个子步骤被 `SKIP`，主要是三类原因：脚本缺少 create 后按名称回查 ID、写接口依赖外部 ID 环境变量、或 `task/shift_record` 这类详情动作需要现成业务数据
- 第二轮修补后再次完整执行 `.github/acceptance/backend/*.sh`：26 个脚本 shell 级全部退出 `0`，共记录 `219` 个 HTTP 响应，全部为 `200`
- 第二轮仅剩 `2` 个 `SKIP`：
	- `task retry` 仍需要显式 `TASK_RETRY_ID`，因为当前本地数据中没有现成 failed task，不能伪造“可重试失败任务”
	- `charge_repayment create` 仍需要显式 `CHARGE_REPAYMENT_WRITE_CUSTOMER_ID` 与两条未还款 `charge_record_id`，这是业务前置数据依赖，不应在脚本里盲选现有记录硬凹通过
- 最终第三轮完整执行 `.github/acceptance/backend/*.sh`：26 个脚本 shell 级全部退出 `0`，共记录 `231` 个 HTTP 响应，全部为 `200`，`SKIP=0`
- `sms_template.sh` 日志确认 cleanup 两步均返回 `HTTP_STATUS:200`，脚本具备重复执行稳定性

未完成：

- 无

## 踩坑与偏差

- 一开始容易误判成“minimal 传了太多空筛选参数”，但 `build_query` 本身会自动丢弃空值。真正的系统性问题是共享 helper 无条件追加了 `page/size`。
- 仅替换 helper 还不够，因为 `product_sale_summary` / `product_sale_detail` 的 minimal 默认值里有非空 `store_ids`，这类历史兜底值必须单独收回。
- `.github/` 目录在当前仓库被忽略，常规 git diff / changed files 工具不能反映本次修改，所以只能靠文件读写、语法校验和 dry-run 输出来完成验证。
- backend 验收脚本当前并不会因为 `HTTP_STATUS:409/500` 自动退出；如果只看 shell exit code，会把 `sms_template.sh` 这类真实失败误判成通过。真实验收必须追加日志级状态码扫描。
- shell 脚本里凡是 body 默认值要插入动态 prerequisite ID，都必须先完成 ID lookup 再做 `VAR="${VAR:-...${ID}...}"` 赋值；否则空 ID 会在变量初始化阶段被提前固化进 JSON，后面补到的 ID 根本不会生效。
- 对有状态副作用的动作接口（如 `task retry`），minimal/full 不能复用同一资源样本，否则第一条请求会改变资源状态，让第二条请求天然失真。
- 对唯一资源槽位有限的接口（如 `sms_template` 的 biz_type 唯一约束），如果 acceptance 需要重复执行，就必须在脚本内部做“动态选槽 + 跑后清理”，否则脚本会把自己跑死。

## 可复用模式

- backend curl 验收的 minimal 规则应固定为：只发送接口真实必填参数，不发送 `page/size`，不发送为了“更容易命中数据”而伪造的可选筛选。
- 若一个脚本同时保留 minimal 与 full，两者职责必须稳定：minimal 证明最小契约可用，full 证明扩展筛选与分页契约可用。
- 当共享 helper 改写了请求形态时，验收收敛应优先在 helper 层统一，而不是在每个脚本里散改。
- 批量执行 acceptance 时，`PASS` 只代表脚本流程没崩，不代表 HTTP 成功；需要同时统计 `HTTP_STATUS` 与 `SKIP`，否则结果会失真。