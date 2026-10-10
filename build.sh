#!/bin/bash
# jellyfin-cix 一键构建
# 用法: ./build.sh [--skip-pull] [--tag 10.11.11-cix.1]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SKIP_PULL=false
TAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-pull) SKIP_PULL=true ;;
        --tag) TAG="$2"; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

UPSTREAM_TAG=$(cd "$ROOT/jellyfin" && git describe --tags --abbrev=0)
[ -z "$TAG" ] && TAG="${UPSTREAM_TAG#v}-cix.1"

echo "=== 1/5 submodule ==="
if [ "$SKIP_PULL" = false ]; then
    git -C "$ROOT" submodule update --init --recursive 2>/dev/null \
        || git -C "$ROOT" -c protocol.file.allow=always submodule update --init --recursive
fi
cd "$ROOT/jellyfin"
git checkout -q "$UPSTREAM_TAG"
git reset -q --hard
git clean -qfd

echo "=== 2/5 应用 CIX 补丁 ==="
cd "$ROOT/jellyfin"
for p in "$ROOT"/patches/*.patch; do
    [ -f "$p" ] || { echo "无补丁文件"; exit 1; }
    git am --committer-date-is-author-date "$p" \
        || { echo "补丁应用失败: $p"; git am --abort 2>/dev/null; exit 1; }
done

echo "=== 3/5 dotnet publish ==="
if ! command -v dotnet >/dev/null; then
    export PATH="$HOME/.dotnet:$PATH"
fi
cd "$ROOT"
dotnet publish jellyfin/Jellyfin.Server/Jellyfin.Server.csproj \
    -c Release -o "$ROOT/publish" 2>&1 | tail -2

echo "=== 4/5 构建镜像 ==="
export PATH="/usr/local/bin:$PATH"
command -v podman >/dev/null || { echo "需要 podman"; exit 1; }
podman build --layers=false -t "jellyfin-cix:$TAG" "$ROOT"

echo "=== 5/5 完成 ==="
podman images | grep "jellyfin-cix" | head -3
echo "镜像: jellyfin-cix:$TAG"
