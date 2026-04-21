# 部署

> 入口文件：[copilot-instructions.md](copilot-instructions.md)
> 本地启动/接口测试：[local-dev.md](local-dev.md)

---

## 目录结构

```
deploy/
├── base/                              Kustomize 基础层（所有环境共享）
│   ├── Dockerfile.bundle              多应用 bundle 镜像（遍历 cmd/ 构建所有服务）
│   ├── entrypoint.sh                  动态入口脚本，按参数启动对应服务
│   ├── kustomization.yaml
│   ├── dapr/subscriptions/            Dapr 声明式订阅
│   │   ├── device-order.yaml          MQTT 设备订单 → eventcore
│   │   └── service-merchant.yaml      Redis 商户事件 → eventcore
│   ├── argocd-image-updater-config.yaml
│   ├── dine-api-updater.yaml          ArgoCD Image Updater
│   ├── sealed-argocd-harbor.yaml      Harbor 拉取凭据 (SealedSecret)
│   ├── sealed-argocd-repo.yaml        Git 仓库凭据 (SealedSecret)
│   └── public-cert.pem                SealedSecrets 加密公钥
└── overlays/
    ├── local/                         本地 Docker Compose
    │   ├── compose.yaml
    │   └── dapr/components/           本地 Dapr 组件 (Redis / MQTT)
    └── dev/                           开发环境 K8s
        ├── kustomization.yaml         继承 base + patch namespace + configMapGenerator
        ├── config.env                 统一环境配置（阿里云 DB/Redis/OSS/Tracing）
        ├── sealedsecrets.yaml         加密敏感配置 (Bitnami SealedSecret)
        ├── argo-app.yaml              ArgoCD Application（监听 dev 分支自动同步）
        ├── namespace.yaml             dine-dev 命名空间
        ├── emqx.yaml                  EMQX 6.1.1
        ├── dapr/components/           dev 环境 Dapr 组件（阿里云 Redis / 集群内 MQTT）
        └── <service>.yaml             各服务 Deployment + Service
```

---

## Bundle 镜像

`deploy/base/Dockerfile.bundle` 一次构建所有服务，按 entrypoint 参数选择启动哪个 `cmd/<service>/main.go`。
**新增 API 服务必须**：补 `cmd/<service>/main.go` → 重建 bundle 镜像。

```bash
docker compose build builder    # 本地重建
```

---

## Dev 环境（K8s + ArgoCD GitOps）

push 到 `dev` 分支 → ArgoCD 自动同步到 `dine-dev` 命名空间。
镜像：`harbor.jiguang.dev/pos_dine_api/bundle:dev`，ArgoCD Image Updater 监听 digest 变化自动更新。

### 服务模板

**Dapr 服务**（带 `dapr.io/enabled` 注解）：

| 服务 | Dapr app-id | Dapr app-port | 备注 |
|------|------------|--------------|------|
| eventcore | eventcore | 8080 | `AUTOMIGRATE=true`，仅等 emqx |
| scheduler | scheduler | — | 无 Service、无探针，等 emqx + eventcore |
| taskcenter | taskcenter | 8080 | `REQUESTTIMEOUT=60`，等 emqx + eventcore |

**普通服务**（无 Dapr，等 emqx + eventcore）：

| 服务 | Service 类型 |
|------|--------------|
| admin / backend / store / pos / frontend / customer | NodePort |

所有服务通过 `envFrom` 引用：
- `dine-config` (ConfigMap，由 `config.env` 生成)
- `dine-secrets` (SealedSecret，含 DB/Redis 密码、阿里云 OSS 凭据)

### SealedSecrets

```bash
kubeseal --cert deploy/base/public-cert.pem --format yaml < secret.yaml > sealedsecret.yaml
```

### 新增服务到 dev

1. 创建 `deploy/overlays/dev/<service>.yaml`（Dapr 参考 `eventcore.yaml`，普通服务参考 `store.yaml`）
2. 加入 `deploy/overlays/dev/kustomization.yaml` 的 `resources` 列表
3. 确保 `cmd/<service>/main.go` 存在（bundle 镜像才会包含）
4. push 到 `dev` 分支 → ArgoCD 自动部署

---

## Dapr 配置三层分离

```
deploy/base/dapr/subscriptions/         声明式订阅（所有环境共享）
deploy/overlays/local/dapr/components/  本地 Dapr 组件
deploy/overlays/dev/dapr/components/    dev 环境 Dapr 组件
```

当前订阅：
- `sub-device-order`：MQTT `$share/eventcore/order/#` → eventcore（`order.report` / `order.close`）
- `sub-service-merchant`：Redis `merchant` → eventcore（`merchant.created` / `merchant.updated`）

更多通信细节见根目录 [pubsub.md](../pubsub.md)。
