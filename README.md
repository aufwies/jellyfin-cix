# jellyfin-cix — CIX VPU 硬件加速版 Jellyfin

基于上游 Jellyfin + CIX 代码补丁 + CIX 专有 ffmpeg/VPU 二进制构建的 Docker 镜像
（linux/arm64），在 CIX 芯片上提供硬件转码加速。

## 特性

- 解码走 CIX VPU（mvxdec，V4L2 M2M）：h264 / hevc / vp8 / vp9 / mpeg2 / mpeg4 / h263，最高 8K
- 编码走 CIX VPU（mvxenc）：h264 / hevc
- **AV1 硬解可用**（v4l2m2m 直连 VPU，**不依赖 VAAPI/GPU**——即使平台没有 VAAPI 也能硬解 AV1）
- 不支持的编码自动回退软件编解码，无需人工干预
- 控制台硬件加速下拉中已注入 **CIX VPU** 选项
- 版本自动跟随上游：Jellyfin 每发布一个稳定版，镜像自动构建 `<版本>-cix` 与 `latest`

## 实测能力矩阵（CIX P1/CP8180 真机，2026-11-04）

校验方法：硬解抽帧与 CPU 软解同帧逐字节比对；编码产物回环 + 对源 PSNR。

### 解码

| 编解码 | 实测覆盖 | 结果 |
|---|---|---|
| H264 Baseline/Main/High | L3.0 → **L5.2 @ 4K60** | 全部位精确（H264 标准封顶全覆盖） |
| HEVC Main / Main10 | L4.1 → **L5.2 @ 4K60**（10bit 含） | 全部位精确 |
| HEVC 8K | L6.1 @ 7680×4320 | 正常出帧 |
| **AV1 Main** | 640×360 / **1080p** | 正常解码，~29x 实时 |
| VP8/VP9/MPEG/VC1/H263 | 驱动声明支持 | 未逐项实测 |

4K30 吞吐：h264 ≈ 6.5x、hevc ≈ 7.2x 实时。

### 编码

| 编解码 | 实测覆盖 | 结果 |
|---|---|---|
| H264 | 720p / **4K30** | 正常，level 标注正确，PSNR 38–49dB |
| HEVC | 720p / 4K30 / **4K60** | 正常出流；注意码流 **level 恒标 3.0**（驱动瑕疵） |
| AV1 | — | VPU 无编码器硬件（解码时回退 CPU 软解，不受影响） |

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

CI 配置、发布流程、镜像源映射等维护细节见 [AGENT.md](AGENT.md)。
