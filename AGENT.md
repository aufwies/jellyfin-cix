# AGENT.md

面向 CI / 发布流程 / 自动化代理的运维说明。面向使用者的介绍见 [README.md](README.md)。
平台背景与兄弟项目记忆：`cix-top/AGENT.md`（设备拓扑/指标采集）、
`immich-machine-learning-cix/AGENT.md`（NPU/NOE）。

## 平台事实（硬件/驱动，勿凭猜测）

- **VPU**：VeriSilicon MVX，内核驱动 `amvx`，V4L2 M2M。
  `/dev/video0=mvxdec`、`/dev/video1=mvxenc`（video2/3 是 jpeg，镜像无需挂载）。
- **GPU**：Arm Mali CSF，内核驱动 `panthor`；Mesa 无 VAAPI state tracker。
- **VAAPI 整条路线搁置**：缺 `libdrm_cix.so.1`（见 cix-top 记忆），
  因此一切依赖 VAAPI 的能力当前不可用。
- **AV1 硬解依赖 VAAPI → 当前不可用**。补丁里 av1→av1_v4l2m2m 的映射
  保留但实际不生效；待 VAAPI 就绪后再验证启用。
  （备注：真机 v4l2m2m 层面 AV01 小分辨率实测可解，生产可用性未验证，
  以 VAAPI 就绪为准。）
- VPU 会话给每个任务打 `can't initialize mutex` 警告（无 CME 守护进程时），
  非致命，不影响帧输出。
- 本地调试必须用 `/usr/share/cix/bin/ffmpeg`；宿主机 `/usr/local/bin/ffmpeg`
  是残缺副本会遮 PATH（容器内无此问题）。

## 铁律

- **内网地址（域名、registry、集群名、内网 URL）绝不写入仓库文件、提交信息或补丁**。
  运行时配置一律走 CI Variables（私有 Forgejo 实例）或 Secrets。
- GitHub 的 **Variables 对任何有读权限的用户可读**（公开仓库 = 任何登录用户），
  **只有 Secrets 是 write-only 安全的**。公开环境需要敏感值时必须用 Secrets。
- 本仓库历史已于 2026-11 做过全量 scrub + 重写（git-filter-repo + force push），
  不要把已清除的信息以任何形式重新引入。

## CI 变量（Forgejo Settings → Actions → Variables）

| 变量 | 用途 | 示例 |
|---|---|---|
| `BASE_IMAGE` | jellyfin 基础镜像 repo（不含 registry/tag，CI 按版本拼 tag） | `jellyfin/jellyfin` |
| `NUGET_SOURCE` | NuGet 包源（缺省 api.nuget.org） | `https://repo.huaweicloud.com/repository/nuget/v3/index.json` |
| `JELLYFIN_MIRROR_URL` | submodule 内网镜像源，覆盖 .gitmodules 默认的 GitHub 上游 | `https://<内网git>/mirrors/jellyfin.git` |
| `SDK_IMAGE_REPO` | USE_MIRROR=true 时的内网 arm64 SDK 镜像 repo（不含 tag；未设置则构建失败退出） | `<registry>/dotnet-sdk` |
| `REGISTRY_IMAGE` | 内网推送目标完整镜像路径（不含 tag；缺省 `<SERVER>/<REPOSITORY>`） | `<registry>/<owner>/jellyfin-cix` |
| `USE_MIRROR` | 镜像源开关（apt/SDK/base 全走镜像；默认 false 官方源） | `true` |

Secrets：`JELLYFIN_MIRROR_TOKEN`（Forgejo 个人 token：submodule clone / registry 登录推送）。
git 用户名与推送 owner 均从 `GITHUB_REPOSITORY` 运行时推导，无需配置。

**GitHub 侧零配置**：不设任何变量/Secret 即可构建（官方源 + GITHUB_TOKEN 推 ghcr.io）。

## 镜像源映射（USE_MIRROR=true 时）

| 用途 | 直连（默认） | 镜像 |
|---|---|---|
| apt | deb.debian.org | repo.huaweicloud.com |
| NuGet | api.nuget.org | repo.huaweicloud.com |
| .NET SDK | mcr.microsoft.com/dotnet/sdk | 内网 registry（变量 `SDK_IMAGE_REPO`，arm64） |
| jellyfin base | docker.io/jellyfin/jellyfin | docker.m.daocloud.io/jellyfin/jellyfin |

## 版本策略（全自动，无需人工）

- `update.yml` 每日 03:00 UTC 检查上游最新稳定 tag（排除 rc/beta），自动 bump submodule
  并 push，随后显式 dispatch Build（Forgejo/GitHub 的 Actions push 均不级联触发）
- 镜像 tag：push 触发 = `<上游版本>-cix` + `latest`；`v*` tag 触发 = tag 名
- SDK 版本从 `jellyfin/global.json` 推导（如 `10.0` → `sdk:10.0`）
- base 镜像 tag = 当前上游版本

## 发布流程

```bash
# 1. 开发 fork（cix-vpu 分支）coding → 单测 → tag
# 2. 本仓库同步补丁:
./sync-from-fork.sh ../jellyfin v12.4
# 3. 提交并 push → CI 自动构建镜像
git add -A && git commit -m "release 12.4" && git push
```

## 本地构建

```bash
./build.sh [--skip-pull] [--tag 12.4-cix.1]   # 需要 podman + dotnet SDK
```

注意：`.gitmodules` 默认 submodule URL 为 GitHub 上游。内网环境拉不动 GitHub 时，
先本地覆盖（不提交）：

```bash
git config submodule.jellyfin.url <内网镜像地址>
```

## 已知平台差异

- **GitHub**：`GITHUB_TOKEN` 触发的事件不级联——`update.yml` 每日 bump 推送后**不会**
  自动触发 Build，需手动 dispatch 或配置 PAT secret 代替 dispatch 用的 token。
  Forgejo 无此问题（workflow 已显式 dispatch）。
- 推送目标自适应：GitHub → `ghcr.io/<owner>/jellyfin-cix`；Forgejo → `REGISTRY_IMAGE`。

## 安全备忘

- `debs/SHA256SUMS` 用于校验专有二进制完整性。
- 本地 `.git/config`、`.git/modules/*` 含内网 remote 属正常本地状态，不会随 push 泄露。
