# jellyfin-cix — CIX VPU 硬件加速版 Jellyfin

独立发布项目：submodule 钉住上游 Jellyfin + CIX 代码补丁 + CIX 专有二进制 deb，
一键构建带 VPU 硬件加速的 Docker 镜像。

## 结构

```
├── jellyfin/           # submodule → 上游 jellyfin/jellyfin（钉住 tag，零改动）
├── patches/            # CIX 代码增量（从 fork 的 cix-vpu 分支生成同步）
├── debs/               # CIX 专有二进制 deb + SHA256SUMS 锁定
├── Dockerfile          # 官方镜像 + deb 解包 + apt 公共依赖 + 补丁 dll
├── build.sh            # 一键构建
├── .github/workflows/  # CI/CD
└── README.md
```

## 构建

```bash
./build.sh                    # 完整: submodule → patch → publish → 镜像
./build.sh --skip-pull        # 跳过 submodule fetch（本地已有）
```

产物: `jellyfin-cix:<上游版本>-cix.<序号>`

## 发布流程

1. fork（rgan/jellyfin, cix-vpu 分支）上 coding → 单测 → 上游 rebase → tag
2. 本仓库:
   ```bash
   ./sync-from-fork.sh v10.11.11..cix-vpu    # 同步 patch
   cd jellyfin && git checkout v10.11.11    # 钉住上游版本
   git add -A && git commit -m "release 10.11.11-cix.1"
   ```
3. push → CI 自动构建 → 推镜像到 Forgejo 容器仓库

## CIX SDK 升级

从 cix-mm.tar.gz 提取新 deb 放入 `debs/`，更新 SHA256SUMS，全量重建。

## 许可

- Jellyfin 衍生代码: GPL-2.0（继承）
- CIX 专有 deb: 保留所有权利，仅打包分发
- 本仓库构建脚本: SSPL-1.0
