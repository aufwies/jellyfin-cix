# AGENT.md

面向 CI / 发布流程 / 自动化代理的运维说明。面向使用者的介绍见 [README.md](README.md)。
平台背景与兄弟项目记忆：`cix-top/AGENT.md`（设备拓扑/指标采集）、
`immich-machine-learning-cix/AGENT.md`（NPU/NOE）。

## 平台事实（硬件/驱动，勿凭猜测）

- **VPU**：VeriSilicon MVX，内核驱动 `amvx`，V4L2 M2M。
  `/dev/video0=mvxdec`、`/dev/video1=mvxenc`（video2/3 是 jpeg，镜像无需挂载）。
- **GPU 与本项目无关**：VPU 作业全程走纯 V4L2 ioctl，不触碰 `/dev/dri/*`。
  Mali CSF（panthor 内核）与 Mesa 无 VAAPI 等事实不影响 VPU 能力判定。
  **cix-gpu-umd 完全不参与**，本项目只用 VPU。
- **镜像仅含 VPU 组件**：`cix-ffmpeg` + libav 四件套。已剔除
  `cix-libva2` / `cix-libva-drm2` / `cix-vaapi` / `cix-libcme`
  （readelf 验证零链接引用；libOpenCL loader 是 libavutil/libavfilter
  的硬链接依赖，与 GPU 无关，必须保留 `ocl-icd-libopencl1`）。
- **v4l2m2m 硬解完全不依赖 VAAPI（实证修正旧结论）**：
  cix `libavcodec` 的 ELF NEEDED 清单**零 `libva`**（readelf 实测）；
  `av1_v4l2m2m` 运行时 strace 只见 `/dev/video*` + `VIDIOC_QBUF/DQBUF/EXPBUF`，
  **从不打开任何 render 节点**。"AV1 解码需要 VAAPI"的印象源自**上游
  ffmpeg** av1_v4l2m2m 对 v4l2-request/VAAPI 解析的历史依赖；
  CIX 专有 libav fork 直连 VPU，不适用该约束。

## VPU 实测能力矩阵（2026-11-04，CIX P1/CP8180 真机，v4l2m2m 路径）

校验方法：硬解抽帧与 CPU 软解同帧 **NV12/P010 逐字节比对**；编码产物回环解码 + 对源 PSNR。

### 解码
| 编解码 | 覆盖范围 | 结果 |
|---|---|---|
| H264 Baseline/Main/High | L3.0 → **L5.2 @ 4K60**（含 1080p/4K30） | ✅ 全部 BIT-EXACT（即 H264 标准封顶全覆盖） |
| HEVC Main / **Main10** | L4.1 → **L5.2 @ 4K60**；Main10 4K30（p010） | ✅ 全部 BIT-EXACT |
| HEVC **8K** | L6.1 @ 7680x4320x15 | ✅ 硬解出帧，帧尺寸精确（未做位级比对） |
| **AV1 Main** | 640x360；**1080p24** | ✅ 全帧解出，~29x 实时；**不依赖 VAAPI/GPU** |
| VP8/VP9/MPEG1/2/4/VC1/H263 | 驱动已声明 | ⏳ 未逐项实测 |

吞吐（4K30 内容）：h264 ≈ 6.5x、hevc ≈ 7.2x 实时。

### 编码（v4l2m2m = 低功耗档）
| 编解码 | 覆盖范围 | 结果 |
|---|---|---|
| H264 | 720p24、**4K30** | ✅ 出流，level 标注正确；PSNR 720p≈49dB / 4K≈38dB |
| HEVC | 720p24、4K30、**4K60** | ✅ 出流；PSNR 720p≈51dB / 4K@6Mbps≈29dB；**码流 level 恒标 3.0（驱动瑕疵）** |
| AV1 | — | ❌ VPU 无编码器硬件（预期内，软件解码时自动回退 CPU） |

### 对发布的影响
- 补丁中 `av1 → av1_v4l2m2m` 的映射**可以启用**——旧结论"待 VAAPI 就绪"的前提不存在。
  建议在容器内用真实 AV1 源跑一次 Jellyfin 播放验证后再随下一版转正。
- HEVC 编码 level 误标：对 Jellyfin 自解码回放无碍；对严格校验 level 的外部客户端有拒收风险，留意。

## 实测坑（工程笔记）

1. cix-ffmpeg 与系统 libav **ABI 不同**：绝不全局 `export LD_LIBRARY_PATH=/usr/share/cix/lib`
   （会把系统 ffmpeg 打成 `symbol lookup error`），必须按次 `env` 包裹隔离。
2. 本地调试必须用 `/usr/share/cix/bin/ffmpeg`；宿主机 `/usr/local/bin/ffmpeg`
   是残缺副本会遮 PATH（容器内无此问题）。
3. VAAPI 路线的驱动日志**打到 stdout**，会污染 rawvideo 管道校验——校验一律先落盘再比对。
4. VPU 会话给每个任务打 `can't initialize mutex` 警告（无 CME 守护进程时），
   非致命，不影响帧输出。
5. 旧宿主的 VAAPI 路线（libcix_va）缺陷清单（HEVC 解码 SPS-missing / AV1 提交后不回帧
   把 `bbox_main` 内核线程吊成 D 状态 / CME ret=-7）——本项目不走 VAAPI，勿以其能力
   推断 v4l2m2m；残留 D 状态不阻塞 v4l2m2m 新作业。

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
# 3. 提交并 push → CI 自动构建镜像（注意：只 add 补丁文件，勿带上 submodule 指针）
git add patches/ && git commit -m "release 12.4" && git push
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

- **submodule 指针必须指向上游干净 tag**（存在于 mirror 上的提交）。
  `build.sh`/CI 应用补丁后工作树会停在补丁提交（gitlink 显示 dirty），
  **绝不提交该指针**——远端没有补丁提交，CI Clone 的
  `git submodule update --init` 会直接失败。提交时用显式文件列表，
  不要 `git add -A`/`git add .`。（已在 eabe8b5 踩过，ef4048f 回滚）
- **GitHub**：`GITHUB_TOKEN` 触发的事件不级联——`update.yml` 每日 bump 推送后**不会**
  自动触发 Build，需手动 dispatch 或配置 PAT secret 代替 dispatch 用的 token。
  Forgejo 无此问题（workflow 已显式 dispatch）。
- 推送目标自适应：GitHub → `ghcr.io/<owner>/jellyfin-cix`；Forgejo → `REGISTRY_IMAGE`。

## 安全备忘

- `debs/SHA256SUMS` 用于校验专有二进制完整性。
- 本地 `.git/config`、`.git/modules/*` 含内网 remote 属正常本地状态，不会随 push 泄露。
