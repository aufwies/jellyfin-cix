# Vulkan GPU 缩放研究档案

> 状态：**持续研究中** | 最后更新：2026-11-17 | 结论快照：panvk 对 Mali-G720 (v12) 的 GPU 执行路径未完工，滤镜缩放暂走 CPU，全量实验基础设施已就位待上游修复。

## 1. 背景与目标

jellyfin-cix 已实现 VPU 硬解+硬编（patch 0001-0006），唯一遗留 CPU 开销在滤镜链（1080i 源去隔行+缩放 ~390% CPU）。目标：把 `scale` 滤镜搬到 Mali GPU（Vulkan compute），预期 CPU 降半以上（实测探针已达 36%）。

## 2. 平台事实

| 层 | 现状 |
|---|---|
| 内核 | panthor（主线驱动，Armbian/CIX edge 内核），**不动** |
| GPU 固件 | `/lib/firmware/arm/mali/arch12.8/mali_csffw.bin` 307200B (md5 15f238b5…)，sky1-firmware 仓为另一版 303104B (481c112a…) — **不换**（BSP 依赖风险，用户定案） |
| Mesa 用户态 | Debian trixie-backports 26.1.6（panvk），纯用户态可随时升级/回退 |
| GPU | Mali-G720 MC10 = **v12 "Avalon" 架构**；panvk 仅 v10 (G610) 过 Vulkan conformance |

## 3. 绿屏 bug 档案（核心问题）

**症状**：`scale_vulkan`/`libplacebo` 任何 GPU 滤镜输出 = 纯绿帧 `#008000`（YUV 全零），帧率/退出码正常（假成功）。像素级复现法：lavfi `smptebars` 经 GPU 链出 PNG 判色。

**病理**：输出缓冲从未被 GPU 写入（清屏零值经 YUV→RGB 恰为绿色）。

**根因推断**（证据收窄）：v12 CSF 指令流实现缺口——panvk 按 v10 语义构建的 command stream 在 v12 上静默失败（compute job 不执行但 fence 假完成）。佐证：设备枚举/队列创建（CPU 侧）全正常，唯派 shader 上 GPU 才踩雷；ffmpeg 与 libplacebo 双实现同症状=坑在驱动底座。次级嫌疑：v12 tiler/AFBC 布局变化致写入落错地址。

**非原因**（已排除）：ffmpeg 构建（Debian 官方 ffmpeg 同样绿屏）、容器/设备节点（CPU 路径正常）、固件错位（Debian panvk 配宿主固件仍绿屏）。

## 4. 已穷尽路线矩阵（全部实测）

| # | 路线 | 结果 | 证据/备注 |
|---|---|---|---|
| 1 | Debian mesa 25.0.7 panvk | ❌ 初始化失败 | 容器内 vulkaninfo ERROR_INITIALIZATION_FAILED |
| 2 | Debian mesa 26.1.6 bpo（生产基线） | ❌ 绿屏 | smptebars 纯绿；探针 CPU 收益 36%（假输出下测得，不作数） |
| 3 | Sky1-Linux/mesa-sky1 源码自编（26.0+WLS 串行化/VM_BIND/VA 40bit 三修复） | ❌ 绿屏 | sky1 修复不覆盖 CP8180/MC10 场景 |
| 4 | Sky1 apt 仓 mesa-vulkan-drivers 26.0.0-**1sky1.2** 打包版 | ❌ 初始化失败 | 疑似要求 sky1-firmware（固件墙，BSP 依赖，不跨） |
| 5 | GO 引擎闭源 libmali (cix-gpu-umd 2026Q2) | ❌ 绑死 mali_kbase | loader 明示 `No mali devices found`（读 /sys/module/mali_kbase）；与 panthor 互斥，用户定案不切内核栈 |
| 6 | CIX ffmpeg 私有 VPU scale 滤镜 | ❌ 不存在 | 5.1.7 与 7.1.2 libavfilter 零 VPU/mvx 滤镜符号；release note 的 "VPU scaling" 仅存于 gstreamer/私有 API |
| 7 | mvxenc 内建缩放 | ❌ 无 | `-s` 触发 ffmpeg 自动插软 scale（auto_scale_0） |
| 8 | CIX RGA 类 2D 引擎 | ❌ 硬件没有 | 设备树/驱动零暴露 |
| 9 | wonderkast02/panvk-g720-kbase-csf | ⛔ 平台不匹配 | Android + /dev/mali0 + Kbase/CSF；我们是 Linux panthor + renderD128 |

## 5. mesa-sky1 容器编译配方（复用资产）

- 基座：`debian:trixie` + 华为云/中科大 apt 源（容器对 apt 源敏感，NJU/华为云曾卡死，USTC 稳）
- 依赖链（踩坑顺序）：`meson ninja-build pkg-config python3-mako python3-yaml libdrm-dev zlib1g-dev libexpat1-dev byacc flex bison glslang-tools llvm-dev libwayland-bin wayland-protocols libx11-dev libxext-dev libxfixes-dev git cmake build-essential`
- **版本墙**：mesa 26.0 起 panvk 硬依赖 CLC 预编译体系（`with_driver_using_cl` 显式含 `with_panfrost_vk`）→ 需要 **LLVMSPIRVLib ≥19 + libclang**
  - trixie 只有 18.1 → 解法：apt.llvm.org 加 `llvm-toolchain-trixie-20` 源装 `libllvm20 llvm-20-dev libclang-20-dev libclang-cpp20-dev libclang-common-20-dev`
  - SPIRV-LLVM-Translator v20.1.8 源码自编（github tarball；其 CMake 会 git clone spirv-headers，需容器内 git）
  - libclc：trixie 是版本化命名 `libclc-18-dev`（无 libclc-dev）
- meson（只编 panvk，~15 分钟 8 核）：`meson setup build -Dgallium-drivers= -Dvulkan-drivers=panfrost -Dbuildtype=release -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dtools=[]`
- ICD 测试：自写 json `{"ICD":{"library_path":"/out/libvulkan_panfrost.so","api_version":"1.4.302"}}` + `VK_ICD_FILENAMES` 指向

## 6. 验收标准（复测时用）

1. smptebars 经 `hwupload,scale_vulkan=1280:720,hwdownload,format=yuv420p` 出帧 → PNG 视觉判色（**非纯绿**）
2. 建议补位级：GPU 帧与 CPU scale 帧 PSNR>40dB
3. 通过后：jellyfin 镜像换 ICD → 开 `JELLYFIN_CIX_GPU_SCALE=1`（patch 0007 代码已就位，0008 默认禁用中）→ 1080i 实测 CPU 对照（基线 390%）

## 7. 持续研究 TODO

- [ ] 关注 Mesa release notes：panvk v12/CSF conformance 与 compute 修复（26.2+/27.x）
- [ ] 新版 mesa 出来后按 §5 配方编译复测 §6
- [ ] （可选）关注 CIX 官方 PPA 是否发布新版 cixdeb13 deb（7.1.2 之上）带 VPU scale 滤镜
- [ ] （参考）Sky1 apt 仓的 `ffmpeg 8.0.1+av1v4l2`（FFmpeg 8.0 + AV1 v4l2m2m）与 `libva-v4l2-stateful`（stateful VAAPI 桥）——VPU 线升级候选，与 GPU 绿屏无关

## 8. 相关资产

- jellyfin-cix patch 0007（GPU scale 注入，默认禁用）/ 0008（开关）——镜像已含
- 宿主 vulkan 探测：`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json vulkaninfo --summary`（Mali-G720 MC10 / panvk / Vulkan 1.4.354）
- titan 双 GPU 注意：renderD128=panthor(Mali)，renderD129=nvidia；测试须钉 panfrost ICD
