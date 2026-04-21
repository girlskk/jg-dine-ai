#!/usr/bin/env bash
# 主仓 pre-push hook：拦截任何带 .github/ 路径的推送到 gitlab
# 安装方式：cp this file to .git/hooks/pre-push && chmod +x

set -e

remote="$1"
url="$2"

# 仅对 gitlab 远程拦截
if [[ "$url" != *gitlab* ]]; then
  exit 0
fi

while read -r local_ref local_sha remote_ref remote_sha; do
  # 删除分支场景：local_sha 全 0
  if [[ "$local_sha" == "0000000000000000000000000000000000000000" ]]; then
    continue
  fi

  # 新分支场景：remote_sha 全 0，对比所有提交
  if [[ "$remote_sha" == "0000000000000000000000000000000000000000" ]]; then
    range="$local_sha"
    files=$(git diff-tree --no-commit-id --name-only -r "$range" 2>/dev/null || true)
  else
    range="${remote_sha}..${local_sha}"
    files=$(git diff --name-only "$range" 2>/dev/null || true)
  fi

  if echo "$files" | grep -qE '^\.github(/|$)'; then
    echo "❌ 拒绝推送：本次 push 包含 .github/ 路径变更，禁止推到 gitlab。"
    echo "   涉及文件："
    echo "$files" | grep -E '^\.github(/|$)' | sed 's/^/     /'
    echo ""
    echo "   .github/ 应通过其内部独立仓库推送到私人 GitHub。"
    exit 1
  fi
done

exit 0
