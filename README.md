# jellyfin-cix — CIX VPU 硬件加速版 Jellyfin

独立发布项目：submodule 跟踪上游 Jellyfin + CIX 代码补丁 + CIX 专有二进制 deb，
构建带 VPU 硬件加速的 Docker 镜像。

## 镜像源映射（USE_MIRROR=true 时）

| 用途 | 直连（默认） | 镜像（USE_MIRROR=true） |
|---|---|---|
| apt | deb.debian.org | repo.huaweicloud.com |
| NuGet | api.nuget.org | repo.huaweicloud.com |
| .NET SDK | mcr.microsoft.com/dotnet/sdk | 内网 registry（变量 `SDK_IMAGE_REPO`，arm64） |
| jellyfin base | docker.io/jellyfin/jellyfin（多架构） | docker.m.daocloud.io/jellyfin/jellyfin（多架构，自动选 arm64） |

## 版本策略（全自动）

- **上游版本**：`update.yml` 每天定时检查 mirror 最新稳定 tag，自动 bump submodule 并 push，
  由此触发 Build。升级 Jellyfin 无需任何手工操作。
- **镜像 tag**：`<上游版本>-cix`（如 `12.2-cix`）+ `latest`，两者都推送。
- **SDK 版本**：CI 从 `jellyfin/global.json` 推导（如 `10.0` → `mcr.microsoft.com/dotnet/sdk:10.0`），
  不需要维护。
- **基础镜像**：`BASE_IMAGE` 只填 repo（不含 tag），CI 自动拼接当前上游版本。

## 环境变量（Forgejo Settings → Actions → Variables）

| 变量 | 用途 | 示例值 |
|---|---|---|
| `BASE_IMAGE` | jellyfin 基础镜像 repo（**不含 registry/tag**，CI 按 USE_MIRROR 拼前缀 + 版本） | `jellyfin/jellyfin` |
| `NUGET_SOURCE` | NuGet 包源 | `https://repo.huaweicloud.com/repository/nuget/v3/index.json` |
| `JELLYFIN_MIRROR_URL` | submodule 源（内网 git 镜像，覆盖 .gitmodules 默认的 GitHub 上游） | `https://<内网git-host>/mirrors/jellyfin.git` |
| `SDK_IMAGE_REPO` | USE_MIRROR=true 时的内网 arm64 SDK 镜像 repo（**不含 tag**，CI 自动拼 SDK 版本） | `<registry-host>/<repo>/dotnet-sdk` |
| `REGISTRY_IMAGE` | 内网推送目标完整镜像路径（**不含 tag**；不设置则默认 `<GITHUB_SERVER_URL>/<GITHUB_REPOSITORY>`） | `<registry-host>/<owner>/jellyfin-cix` |
| `USE_MIRROR` | 统一镜像源开关：apt/SDK/base 镜像全部走镜像（默认 `false` 官方源） | `true` |

git 访问用户名与推送目标 owner 均从 `GITHUB_REPOSITORY` 运行时推导，无需配置。

另需 **Secrets**：
- `JELLYFIN_MIRROR_TOKEN` — Forgejo 个人 token（clone submodule / registry 推送 / 登录）

## 结构

```
├── jellyfin/           # submodule → 上游 jellyfin/jellyfin (自动跟踪最新稳定版)
├── patches/            # CIX 代码增量（git am 应用到上游 tag）
├── debs/               # CIX 专有二进制 deb + SHA256SUMS
├── Dockerfile          # 运行时组装（无编译阶段）
├── build.sh            # 本地构建入口
├── sync-from-fork.sh   # 从开发 fork 同步补丁
└── .github/workflows/
    ├── build.yml       # push/tag → 编译 + 构建镜像 + 推送 (ghcr.io / 内网 registry 自适应)
    └── update.yml      # 每日检查上游, 自动 bump submodule
```

## 发布流程

```bash
# 1. 开发 fork（cix-vpu 分支）coding → 单测 → tag
# 2. 本仓库同步:
./sync-from-fork.sh ../jellyfin v12.2
# 3. 提交并 push → CI 自动构建镜像
git add -A && git commit -m "release 12.2" && git push
```
