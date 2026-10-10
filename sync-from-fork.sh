#!/bin/bash
# 从 fork 仓库同步 CIX 代码补丁到本仓库
# 用法: ./sync-from-fork.sh <fork路径> <上游tag>
#   例: ./sync-from-fork.sh ../jellyfin v10.11.11
set -euo pipefail

FORK=${1:?用法: $0 <fork路径> <上游tag>}
UPSTREAM_TAG=${2:?用法: $0 <fork路径> <上游tag>}
ROOT=$(cd "$(dirname "$0")" && pwd)

echo "=== 从 $FORK 的 cix-vpu 分支生成补丁 ==="
cd "$FORK"
git checkout cix-vpu

# 清空旧补丁
rm -f "$ROOT"/patches/*.patch

# 生成新补丁
git format-patch "$UPSTREAM_TAG..cix-vpu" -o "$ROOT/patches/"

echo "=== 补丁列表 ==="
ls -la "$ROOT"/patches/*.patch

echo ""
echo "✅ 补丁已同步到 $ROOT/patches/"
echo "下一步: cd jellyfin && git checkout <新上游tag> && git add -A && git commit"
