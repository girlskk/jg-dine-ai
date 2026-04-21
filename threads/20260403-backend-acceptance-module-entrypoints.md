# Thread: backend 验收模块化入口整理

> 日期: 2026-04-03
> 标签: #backend #acceptance #modules #shell #reflect

## Context

在 backend 验收脚本已经跑通之后，用户追加要求把测试入口按模块整理，方便按业务域调用，而不是继续面对 `.github/acceptance/backend/` 下的一堆平铺脚本名。

这里的关键不是“挪文件”，而是要在不破坏既有脚本路径和调用方式的前提下，新增一层按模块组织的调用面。

## 关键决策

1. 不直接搬迁现有脚本文件。现有平铺脚本继续作为真实实现，避免破坏已有路径、helper 相对引用和外部使用习惯。
2. 在 `.github/acceptance/backend/modules/` 下新增模块入口脚本，把“调用组织”与“脚本实现”分离。
3. 模块入口统一复用 `modules/common.sh` 的 dispatch helper，支持 `all` 和单脚本两种调用模式。
4. 模块 runner 必须在执行后生成汇总报告，输出成功/失败数量、失败接口、SKIP 明细和日志路径；不能只把原始 curl 输出甩给调用方。
5. 在 root 增加 `_all.sh` 与 `README.md`，分别承接“全量跑一遍 + 聚合报告”和“查模块映射/调用命令”两类需求。
6. 终端尾部只保留一段简短统计，详细失败明细统一落到 `summary.md`，避免人在终端里继续翻长日志。

## 最终方案

新增目录与入口：

- `modules/common.sh`：统一 dispatch helper
- `modules/auth.sh`
- `modules/logs.sh`
- `modules/finance.sh`
- `modules/merchant.sh`
- `modules/report.sh`
- `modules/message.sh`
- `_all.sh`
- `README.md`

报告输出：

- 模块报告：`tmp/backend-acceptance-reports/<run-label>/<module>-<target>/summary.md`
- 模块日志：`tmp/backend-acceptance-reports/<run-label>/<module>-<target>/logs/*.log`
- 全量聚合报告：`tmp/backend-acceptance-reports/<run-label>/all-modules/summary.md`

模块划分：

- `auth`: `role`, `user`
- `logs`: `logs`, `login_log`, `operate_log`, `sms`
- `finance`: `additional_fee`, `charge_customer`, `charge_record`, `charge_repayment`, `ledger_account_type`, `ledger_account`, `tax_fee`
- `merchant`: `merchant`, `store`, `department`, `device`, `dine_table`, `stall`, `remark`
- `report`: `order_sale_summary`, `product_sale_detail`, `product_sale_summary`, `shift_record`, `task`
- `message`: `sms_template`

调用方式：

- `bash .github/acceptance/backend/_all.sh`
- `bash .github/acceptance/backend/modules/report.sh`
- `bash .github/acceptance/backend/modules/report.sh product_sale_detail`
- `bash .github/acceptance/backend/modules/logs.sh logs`

## 验证

已完成：

- `bash -n .github/acceptance/backend/_all.sh .github/acceptance/backend/modules/*.sh`
- `bash .github/acceptance/backend/modules/report.sh product_sale_detail`
- `bash .github/acceptance/backend/modules/logs.sh logs`
- `bash .github/acceptance/backend/modules/report.sh task`
- `bash .github/acceptance/backend/_all.sh`

最终聚合结果：

- 模块总数 `6`，模块成功 `6`
- 脚本总数 `26`，脚本成功 `26`
- HTTP 总数 `231`，HTTP `200` 数 `231`
- `SKIP=0`

上述入口在执行后都会打印终端汇总，并在 `tmp/backend-acceptance-reports/` 下落报告文件。

上述两个实际入口调用均返回 shell exit `0`。

## 踩坑与偏差

- 直接物理搬迁现有脚本看起来更“整齐”，但代价是会打断现有路径引用、helper source 关系和用户已有调用习惯。这种整齐是表面整齐，不是工程整齐。
- `sms.sh` 名字上容易被误归到短信模板，但它本质是短信日志列表验收，所以被划入 `logs` 而非 `message`。
- 聚合报告第一次实跑时暴露出 `task.sh` 的 full retry 取样缺口：脚本只准备了一条 retry seed source，在失败任务池被前序运行耗尽时会重新出现 `SKIP`。最终改成从 success download tasks 里解析两条独立 seed source，分别喂给 minimal/full retry，恢复全量 `SKIP=0`。

## 可复用模式

- shell 验收文件需要模块化时，优先新增“模块调度层”，不要先动真实脚本位置。
- 模块入口如果不附带汇总报告，就仍然是在逼人读原始日志，调用体验并没有真正改善。
- 终端如果继续打印详细失败列表，只是把“读报告”退化成“读终端尾巴”，并没有把输出层级分清楚。
- 入口组织与脚本实现分层后，后续新增脚本只需补模块映射，不需要反复搬目录。