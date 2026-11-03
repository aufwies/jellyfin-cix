# jellyfin-cix — CIX VPU 硬件加速版 Jellyfin

基于上游 Jellyfin + CIX 代码补丁 + CIX 专有 ffmpeg/VPU 二进制构建的 Docker 镜像
（linux/arm64），在 CIX 芯片上提供硬件转码加速。

## 特性

- 解码走 CIX VPU（mvxdec）：h264 / hevc / vp8 / vp9 / av1 / mpeg2 / mpeg4 / h263，最高 8K
- 编码走 CIX VPU（mvxenc）：h264 / hevc
- 不支持的编码自动回退软件编解码，无需人工干预
- 控制台硬件加速下拉中已注入 **CIX VPU** 选项
- 版本自动跟随上游：Jellyfin 每发布一个稳定版，镜像自动构建 `<版本>-cix` 与 `latest`

## 运行

镜像已内置 CIX ffmpeg 与全部运行时依赖，容器需挂载 VPU 相关设备：

```bash
docker run -d \
  --name jellyfin \
  --device /dev/video0 --device /dev/video1 \
  --device /dev/dma_heap/system \
  -v jellyfin-config:/config \
  -v /path/to/media:/media \
  -p 8096:8096 \
  <registry>/jellyfin-cix:latest
```

首次启动后，在 **控制台 → 播放 → 转码** 中将硬件加速选为 **CIX VPU** 即可。

## 目录

```
├── jellyfin/            # submodule → 上游 jellyfin（每日自动跟踪最新稳定版）
├── patches/             # CIX 代码补丁（构建时 git am 到上游 tag）
├── debs/                # CIX 专有二进制 deb + SHA256SUMS
├── Dockerfile           # 运行时镜像组装（无编译阶段）
└── .github/workflows/   # CI：构建推送 / 上游跟踪
```

CI 配置、发布流程、镜像源映射等维护细节见 [AGENTS.md](AGENTS.md)。
