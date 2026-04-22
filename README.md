# dine-api AI 工作笔记

> 这是个人 AI 工作笔记仓库（私人 GitHub `girlskk/jg-dine-ai`），通过嵌套 git 仓库挂在公司主仓 `dine-api/.github/` 路径下。
> 主仓 `.gitignore` 忽略 `.github/`，本仓库内容**不会**进公司 gitlab。
> 读者：未来的我自己 + 在此仓库工作的 AI agent。

---

## 1) 写入规矩（AI 与人都必须遵守）

> **强制规则的权威版本在 [copilot-instructions.md](copilot-instructions.md) "AI 文档维护契约"**。
> 本节是长版说明，便于人类阅读。两边冲突时以 `copilot-instructions.md` 为准。

### 1.1 两层文档定位（互斥，不允许重叠）

| 层              | 路径                       | 写什么                   | 不写什么                 |
| --------------- | -------------------------- | ------------------------ | ------------------------ |
| **conventions** | `conventions.md`（单文件） | 跨模块的硬约定           | 一次性实现细节、模块介绍 |
| **pitfalls**    | `pitfalls/<topic>.md`      | 反复踩、未来仍会再撞的坑 | 一次性 bug、配置错误     |

调试过程只进 commit message。不写 thread、不留历史日志。调不动的才翻 git log。

### 1.2 写入前 4 道 gate（任何一道答 No → 不写）

1. 这个结论 grep 现有 `.github/` 已经存在了吗？ → 是 → **不写**，更新原文档
2. 这是"三个月后我会再撞的坑"吗？ → 否 → **不写**，commit message 即可
3. 这条信息能用 1-2 行表达完吗？ → 否 → **拆**，每条 pitfall 单独写
4. 我能立刻指出"未来谁会查它"吗？ → 否 → **不写**，没读者的文档=垃圾

### 1.3 升级与删除门槛

- 同一个坑 commit message 出现 ≥ 2 次 → 升级到 `pitfalls/<topic>.md`
- pitfall 对应代码已重构 / 不复存在 → 直接删
- conventions 条目代码已不存在 → 直接删

### 1.4 体量硬上限（超限即拆/砍）

- 单个 pitfall 文件 > 200 行 → 必须拆
- `conventions.md` > 300 行 → 重审哪些条目可删
- `pitfalls/` 总文件数 > 15 → 触发合并 / 删除

### 1.5 禁止项

- ❌ 不写 repo memory（不跨机、不可读、人类视角不友好）
- ❌ 不写“模块介绍”性质的文档（代码即文档）
- ❌ 不建 thread / 模板 / 调试日志目录（这层已被删）
- ❌ 不为 acceptance/E2E 脚本建专门记录

---

## 2) 工作流（极简）

接到任务：

1. **先查**：`./find.sh <关键词>`，命中 conventions/pitfalls 必读
2. **再做**：复杂任务才拆步骤；简单任务直接动手
3. **完成后**：命中 1.2 全部 4 个 gate 才写入 conventions/pitfalls；其他只在 commit message 记清楚

完。**没有六步流水线、没有 thread、没有 task 模板**。

---

## 3) 目录说明

```
.github/
├── copilot-instructions.md  ← AI agent 入口，含必读顺序与服务总览
├── README.md                ← 本文件，写入规矩与工作流，<150 行
├── conventions.md           ← 跨模块编码硬约定，<300 行
├── local-dev.md             ← 代码生成、Compose 启动、接口测试 token
├── deploy.md                ← bundle 镜像、Kustomize、ArgoCD、SealedSecrets
├── pitfalls/                ← 按踩坑模式分类，总文件数 ≤ 15
├── find.sh                  ← 检索入口
├── install-main-repo-hook.sh  ← 主仓 pre-push hook 安装脚本
└── .gitignore
```

---

## 4) 跨机同步（公司 + 家里）

公司主仓在 gitlab，本笔记仓库在 github。两套 git，互不干扰。

每天开工：
```bash
cd .github && git pull
```

写完笔记：
```bash
cd .github && git add . && git commit -m "..." && git push
```

家里电脑首次：
```bash
git clone git@gitlab.jiguang.dev:pos-dine/dine-api.git
cd dine-api
git clone git@github.com:girlskk/jg-dine-ai.git .github
cp .github/install-main-repo-hook.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```

---

## 5) 项目编码约定（必读）

详见 [conventions.md](conventions.md)。

涵盖：
- 错误处理与领域错误
- 仓储/用例方法签名规范
- 读模型 vs 写模型边界
- StorageObject IO 约定
- 多门店 scope 规则
- HTTP 状态码映射
- API 服务分层

---

## 6) 项目部署与本地测试

- 本地启动 / 接口测试 token：[local-dev.md](local-dev.md)
- bundle 镜像 / K8s + ArgoCD / SealedSecrets：[deploy.md](deploy.md)

这两份文档是 AI agent 的操作手册，不是给团队 onboard 用的，所以放在 `.github/` 里和其他笔记同步管理。
