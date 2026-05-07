---
description: "提交当前改动，按逻辑变更拆分 commit"
agent: "agent"
---
帮我提交当前改动。只做 commit，不要 push、不要 amend 已推送的 commit、不要加 `--no-verify`、不要跑测试、不要改代码。

跑 `git status` 和 `git diff`（含 staged 和 unstaged）了解改动；按"一个逻辑变更 = 一个 commit"拆分，跨主题分多次提交；用 `git add -p` 精确暂存，不要 `git add .` 带入无关文件。

Commit message 首行祈使句、无句号、目标 ≤ 20 个字；超出时通过精炼措辞、合并同义词、去掉冗余主语等方式**压缩**表达，而不是粗暴截断丢信息。如有必要，空一行后用正文补充原因、影响或反转理由。

提交完跑 `git log -1 --stat` 给我看结果。如果发现调试代码、`tmp/` 产物、与任务无关的格式化改动混入，停下来问我。
