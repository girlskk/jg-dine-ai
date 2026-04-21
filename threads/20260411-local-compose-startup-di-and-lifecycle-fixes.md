# Thread: 本地 compose 启动失败定位到 eventcore/taskcenter Auth 装配缺口与 backend invoke 误用

> 日期: 2026-04-11
> 标签: #docker-compose #local #debugging #eventcore #taskcenter #backend #fx #startup #config

## Context
本地按完整流程执行 `docker compose up -d` 时，栈无法稳定启动，而这个仓库又存在明显的依赖链：`backend/store/pos/customer/frontend/admin` 都依赖 `eventcore`，部分服务不能拆开单独验证。

第一次复现时，表面现象是 `eventcore` 启动异常、`taskcenter-dapr` 创建失败；继续整栈验证后，`backend` 又进入 restart loop。任务目标不是“让某一个容器暂时变绿”，而是把完整 bundle 镜像重建后整栈真正拉起来，并确认 HTTP 服务可用。

## 关键决策
1. 按整栈排查，不走单服务捷径。
   本地验证遵循 `deploy/overlays/local` 的完整流程：`docker compose down` → `docker compose build builder` → `docker compose up -d`。这能避免因为共享 `dine-bundle` 镜像未重建而继续使用旧二进制。
2. 先抓第一次 fatal，不盯 restart 噪音。
   通过 `docker logs <container>` 定位首个 `invoke failed/start failed`，而不是只看 `docker compose up -d` 的摘要输出或重启后的 sidecar 噪音。
3. 遵循用户约束，不改 member 相关代码。
  既然共享 `usecasefx` 仍然要求 `domain.AuthConfig`，就不要去改 `MemberTransactionInteractor`；直接把 `eventcore/taskcenter` 的 bootstrap 配置出口补齐，让现有依赖关系能被正常装配。
4. backend 的默认会员卡初始化不在本次继续改代码。
  当前 working tree 已将 `cmd/backend/main.go` 里的 `fx.Invoke(bootstrap.InitDefaultMemberCardPlan)` 注释掉。用户明确要求保留这种处理方式，并在此基础上继续排查是否还有其他启动问题。

## 最终方案
- `bootstrap/eventcore.go`
  为 `EventCoreConfig` 补齐 `Auth domain.AuthConfig`，让 `eventcore` 在复用共享 `usecasefx` 时能从现有 `etc/eventcore.toml` 的 `[Auth]` 段装配出 `AuthConfig`。
- `bootstrap/taskcenter.go`
  为 `TaskCenterConfig` 补齐 `Auth domain.AuthConfig`，让 `taskcenter` 同样满足共享 member 相关 usecase 的依赖要求。
- `cmd/backend/main.go`
  保持 working tree 中现有的 `// fx.Invoke(bootstrap.InitDefaultMemberCardPlan),` 注释状态，不继续改 member card plan 初始化逻辑。
- 验证结果：
  完整执行 `docker compose down && docker compose build builder && docker compose up -d` 后，`docker compose ps -a` 显示所有服务 `Up`；`curl http://127.0.0.1:8092/api` 与 `curl http://127.0.0.1:8095/api` 都返回 build 信息 JSON。

## 踩坑与偏差
1. 第一次修完 `eventcore/taskcenter` 后如果就停手，会误以为问题结束，实际 `backend` 的启动问题只有在第二轮整栈验证里才暴露出来。
2. 早期用 `Secret` 去 grep 配置文件时，先命中了 `Alert.Secret`，不是 `Auth.Secret`。如果不回到配置结构本身确认，就会基于错误前提修问题。
3. `docker compose up -d` 的“Started”并不等于稳定启动，必须再看一次 `docker compose ps -a`，否则很容易漏掉刚启动几秒后进入 `Restarting` 的容器。

## 可复用模式
- 这个仓库的本地启动排查要按“完整栈 + 完整镜像”处理，先修第一个失败点，再重跑整栈，继续找新的首个失败点，直到 `ps -a` 全绿。
- `eventcore/taskcenter` 这类复用共享 `usecasefx` 的服务，即使自己不直接暴露鉴权接口，也可能因为共享 usecase 依赖 `domain.AuthConfig` 而要求 bootstrap 配置导出 `Auth`。
- 当用户明确禁止改动某个业务模块时，优先修服务装配、配置出口和入口 wiring，而不是逆着约束去重构共享业务代码。