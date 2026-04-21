#!/usr/bin/env bash
# 笔记检索入口：grep .github/ 下所有 markdown
# 用法: ./find.sh <关键词>
#       ./find.sh extra_fee
#       ./find.sh "context cancel"

set -e
cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
  echo "用法: $0 <关键词>"
  exit 1
fi

kw="$*"

echo "=== conventions.md / local-dev.md / deploy.md ==="
rg -n --color=always "$kw" conventions.md local-dev.md deploy.md 2>/dev/null || true

echo ""
echo "=== pitfalls/ ==="
rg -ln --color=always "$kw" pitfalls/ 2>/dev/null || true

echo ""
echo "=== threads (按月，新到旧) ==="
for dir in $(ls -dr threads/*/  2>/dev/null); do
  hits=$(rg -l "$kw" "$dir" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "$hits"
  fi
done
