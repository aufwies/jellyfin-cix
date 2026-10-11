# jellyfin-cix — CIX VPU 硬件加速版 Jellyfin

独立发布项目：submodule 钉住上游 Jellyfin + CIX 代码补丁 + CIX 专有二进制 deb，
构建带 VPU 硬件加速的 Docker 镜像。

## 环境变量（必须配置）

在 Forgejo 仓库 **Settings → Actions → Variables** 或 runner 环境变量中设置：

| 变量 | 用途 | 内网示例值 | GitHub 默认 |
|---|---|---|---|
| `SDK_IMAGE` | .NET SDK 容器镜像 | `git.example.com/rgan/dotnet-sdk:9.0` | `mcr.microsoft.com/dotnet/sdk:9.0` |
| `BASE_IMAGE` | jellyfin 基础镜像 | `docker.m.daocloud.io/jellyfin/jellyfin:10.11.11` | `docker.io/jellyfin/jellyfin:10.11.11` |
| `NUGET_SOURCE` | NuGet 包源 | `https://mirrors.huawei.com/repository/toolkit/nuget/v3/index.json` | `https://api.nuget.org/v3/index.json` |
| `JELLYFIN_MIRROR_URL` | submodule 源（可选） | `https://git.example.com/mirrors/jellyfin.git` | （默认 .gitmodules） |

另需 **Secrets**：
- `PUBLISH_TOKEN` — Forgejo 个人 token（推送镜像用）

## 结构

```
├── jellyfin/           # submodule → 上游 jellyfin/jellyfin
├── patches/            # CIX 代码增量（HardwareAccelerationType.cix）
├── debs/               # CIX 专有二进制 deb + SHA256SUMS
├── Dockerfile          # 运行时组装（无编译阶段）
├── build.sh            # 本地构建入口
├── sync-from-fork.sh   # 从开发 fork 同步补丁
└── .github/workflows/  # CI/CD（零硬编码 URL）
```

## 发布流程

```bash
# 1. 开发仓库(rgan/jellyfin, cix-vpu 分支) coding → 单测 → tag
# 2. 本仓库同步:
./sync-from-fork.sh ../jellyfin v10.11.11
# 3. 提交并 push → CI 自动构建镜像
git add -A && git commit -m "release X.Y.Z" && git push
```

## CIX SDK 升级

从 cix-mm.tar.gz 提取新 deb 放入 `debs/`，更新 SHA256SUMS。

## 许可

- Jellyfin 衍生代码: GPL-2.0
- CIX 专有 deb: 保留所有权利
- 本仓库脚本: SSPL-1.0
