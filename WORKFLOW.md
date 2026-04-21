# Workflow Protocol v2

> 仓库 = 代码 + 思维 + 决策。
> 每完成一个单位的工作，积累一个单位的经验。

---

## 为什么

效率天花板 = 每件事从零思考。
突破方式 = **模块化决策系统**：统一结构 × 标准流水线 × 经验复用。

人的决策链路：观察 → 解释 → 决策 → 操作 → 验证 → 归档 → 复盘。
本协议将其工程化为可执行的流水线，让人与 AI agent 共同执行、共同积累。

---

## Step 1 — 统一任务结构

**所有任务都是结构化事件。** 不是一句话需求，而是四个字段：

| 字段                | 回答的问题                   | 示例                                      |
| ------------------- | ---------------------------- | ----------------------------------------- |
| **context**         | 为什么要做？当前状态是什么？ | "商户要批量导出桌台二维码，当前无此功能"  |
| **constraints**     | 不能做什么？必须满足什么？   | "走 task center 异步链路；遵循分层架构"   |
| **expected_output** | 做完长什么样？               | "新增 handler + usecase + repo，通过联调" |
| **checkpoints**     | 怎么证明做对了？             | "编译通过 / 触发成功 / 状态流转正确"      |

模板 → [templates/task.md](templates/task.md)

**规则**：接到任务后，先填满这四个字段再动手。填不满说明需求不清晰，回到 Clarify。

---

## Step 2 — 六步流水线

非平凡任务必须按此流水线执行。每一步都有明确的输入、动作和输出。

```
Clarify → Plan → Solve → Verify → Integrate → Reflect
```

### ① Clarify — 澄清

**输入**：原始需求
**动作**：
- 填充任务四字段（context / constraints / expected_output / checkpoints）
- 识别隐含假设，主动暴露
- 查阅 `threads/_index.md` 看是否有相似历史任务
- 如有歧义，向用户确认

**输出**：确认后的完整任务结构
**退出条件**：四个字段填满 + 用户确认（或自信无歧义）

### ② Plan — 拆解

**输入**：确认后的任务结构
**动作**：
- 将任务拆成有序、可跟踪的步骤
- 标注每步涉及的文件、层级、依赖
- 查阅 `threads/_index.md` + `decisions/_index.md` + `knowledge/`（按需读取对应领域文件），引用可复用的历史经验
- 识别风险、阻塞项

**输出**：TODO 列表 + 风险清单 + 引用的历史 thread/decision
**退出条件**：步骤可执行、风险已标注

### ③ Solve — 执行

**输入**：Plan 的 TODO 列表
**动作**：
- 按计划逐步实现，每完成一步标记 checkpoint
- 遇到偏差立即记录（不隐藏、不跳过）
- 遇到 Plan 外的发现，追加到记录中

**输出**：代码变更 + 产出物 + 偏差记录
**退出条件**：所有 TODO 项完成或明确标注阻塞

### ④ Verify — 验证

**输入**：Solve 的产出 + checkpoints 清单
**动作**：
- 逐条验证 checkpoints（编译、lint、测试、手动确认）
- 对照 constraints 确认无违反
- 标记每个 checkpoint 的通过/失败状态

**输出**：✅ / ❌ 清单（失败项附原因）
**退出条件**：全部 ✅ 或失败项已有解决方案

### ⑤ Integrate — 落库

**输入**：验证通过的产出
**动作**（按需执行）：

| 条件                 | 动作           | 目标位置                        |
| -------------------- | -------------- | ------------------------------- |
| 产生新认知           | 写 repo memory | Copilot memory                  |
| 有复用价值的完整任务 | 写 thread      | `threads/` + 更新 `_index.md`   |
| 涉及架构方向决策     | 写 decision    | `decisions/` + 更新 `_index.md` |

**输出**：更新后的索引
**退出条件**：所有该落库的都落了

### ⑥ Reflect — 复盘

**输入**：整个流水线的执行记录
**动作**：
- 对比 Plan vs 实际执行的偏差
- 提炼哪些模式可复用（thread-worthy）
- 识别需要更新的约束文档
- 从这次偏差中提取改进项

**输出**：偏差摘要 + 可复用模式 + 改进项
**退出条件**：偏差已记录、改进已标注

---

## Step 3 — Thread / Decision 复用

### Thread = 执行轨迹

一次有决策含量的任务的完整记录。存储在 `threads/`。

**写 Thread 的判据**：

| 写 ✅                     | 不写 ❌                     |
| ------------------------ | -------------------------- |
| 涉及新架构模式或复杂逻辑 | 纯机械修改（typo、格式化） |
| 走了弯路，踩了坑         | 重复性 CRUD                |
| 产生了可复用的知识       | 无决策含量的简单 bug fix   |
| 跨层联调、集成新组件     |                            |

**文件格式**：`YYYYMMDD-<slug>.md`（slug 小写英文短横线）
**模板** → [templates/thread.md](templates/thread.md)
**索引** → [threads/_index.md](threads/_index.md)

### Decision = 架构约束

影响项目方向的关键决策。Thread 记录过程，Decision 记录结论。

**写 Decision 的判据**：

| 写 Decision ✅            | Thread 就够  |
| ------------------------ | ------------ |
| 新增/变更分层或模块      | 新增单个 API |
| 技术选型（框架、中间件） | 具体实现细节 |
| 变更全局约定             | 局部重构     |
| 定义新的领域概念         | 修复逻辑错误 |

**文件格式**：`NNN-<slug>.md`（NNN 三位序号）
**状态**：`proposed` → `accepted` → `superseded` | `deprecated`
**模板** → [templates/decision.md](templates/decision.md)
**索引** → [decisions/_index.md](decisions/_index.md)

### 复用流程

```
新任务进入
  ↓
Clarify 阶段 → 搜索 threads/_index.md（摘要 + 标签）
  ↓
找到相似 thread？ → 读取 → 提取可复用的决策和模式
  ↓
按任务涉及领域 → 读取 knowledge/<domain>.md（编码约定 + 领域知识）
  ↓
Plan 阶段注明引用来源："参考 thread: YYYYMMDD-xxx" 或 "参考 knowledge/xxx.md"
```

---

## 文件结构

```
.github/
├── WORKFLOW.md                  ← 本文件：协议定义
├── copilot-instructions.md      ← AI 入口：编码约定 + 协议引用
├── templates/
│   ├── task.md                  ← 任务模板
│   ├── thread.md                ← Thread 模板
│   └── decision.md              ← Decision 模板
├── threads/
│   ├── _index.md                ← Thread 索引（按领域分组）
│   └── YYYYMMDD-<slug>.md      ← 各 thread（执行轨迹，可复用模式已提取至 knowledge/）
├── decisions/
│   ├── _index.md                ← Decision 索引（编号序）
│   └── NNN-<slug>.md           ← 各 decision
├── knowledge/                   ← 领域知识库（定期从 thread 手动提炼，非日常写入目标）
│   ├── conventions.md           ← 跨模块编码/架构约定
│   ├── charge.md                ← 挂账模块
│   ├── report.md                ← 报表与导出
│   ├── operate-log.md           ← 操作日志
│   ├── sms.md                   ← 短信模板
│   ├── dine-table.md            ← 桌台
│   ├── auth.md                  ← 认证与权限
│   ├── store.md                 ← 门店与排名
│   └── infrastructure.md        ← 基础设施（Docker/Dapr/MinIO/RM/测试）
```

---

## Agent 执行规则

1. **进入仓库** → 读取本协议 + `copilot-instructions.md`
2. **接收任务** → 用 task 模板填充四字段，不完整则 Clarify
3. **Plan 前必查** → `threads/_index.md` + `decisions/_index.md` + `knowledge/`（按任务涉及领域选读）
4. **每步输出前** → 对照 constraints 做 sanity check
5. **不可跳过后两步** → Integrate 和 Reflect 是强制步骤
6. **偏差零容忍** → 遇到偏差立即记录，不隐藏不跳过

### 优先级

```
用户当次指令 > WORKFLOW.md > copilot-instructions.md > 通用规则
```

冲突时，范围更小、场景更明确的约束优先。
