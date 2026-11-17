# ============================================================
# jellyfin-cix 运行时镜像（纯组装，无编译）
#
# 编译在 CI 步骤中用 SDK 容器完成（见 .github/workflows/）
# 本 Dockerfile 只做: CIX deb 解包 + apt 依赖 + DLL 覆盖
#
# 必需环境变量:
#   BASE_IMAGE  - jellyfin 基础镜像 (如 docker.m.daocloud.io/jellyfin/jellyfin:10.11.11)
# ============================================================

ARG BASE_IMAGE=docker.io/jellyfin/jellyfin:10.11.11
FROM ${BASE_IMAGE}

# CIX VPU 专有二进制（deb 解包；仅 VPU 组件：ffmpeg + libav 四件套。
# GPU 走 panthor 开源栈，cix-gpu-umd/VAAPI/CME 均不参与，勿再加回）
# sky1-ffmpeg deb = ffmpeg-sky1 8.0.1 + mvx DSL 硬件缩放 (dsl_ratio)，替代 cix ffmpeg 主位
COPY debs/ /tmp/cix-debs/
RUN cd /tmp/cix-debs && \
    for deb in *.deb; do \
        [ "$deb" = "SHA256SUMS" ] && continue; \
        [ "${deb#sky1-ffmpeg}" != "$deb" ] && continue; \
        dpkg -x "$deb" /; \
    done && rm -rf /tmp/cix-debs
# sky1-ffmpeg 用 dpkg -i 正式安装（So 版本 60/62/11 等与镜像内 61 系并存，文件名规范）
COPY debs/sky1-ffmpeg_8.0.1-dsl1_arm64.deb /tmp/sky1.deb
RUN dpkg -i /tmp/sky1.deb && rm -f /tmp/sky1.deb

# 公共依赖（Debian 公开包; USE_MIRROR=true 时 apt 改走华为云镜像源, 默认官方源）
ARG USE_MIRROR=false
RUN if [ "${USE_MIRROR}" = "true" ]; then \
      sed -i 's|deb.debian.org|repo.huaweicloud.com|g; s|security.debian.org|repo.huaweicloud.com|g' \
        /etc/apt/sources.list.d/debian.sources; \
    fi \
    && apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        libavdevice61 libpostproc58 libswresample5 libswscale8 \
        libyuv0 ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*

# Vulkan 运行时 (Mali panvk, GPU scale_vulkan 滤镜管线); mesa>=26.1 必须 (25.0 panvk 初始化失败)
RUN MIRROR="repo.huaweicloud.com"; [ "${USE_MIRROR}" != "true" ] && MIRROR="deb.debian.org"; \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://${MIRROR}/debian trixie-backports main" \
      > /etc/apt/sources.list.d/bpo.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends -t trixie-backports libvulkan1 mesa-vulkan-drivers && \
    rm -rf /var/lib/apt/lists/*
ENV VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json

# 删除 Debian 的 libav*（CIX 版本必须优先；系统路径会遮蔽 /usr/share/cix/lib）
RUN rm -f /usr/lib/aarch64-linux-gnu/libavcodec.so.61* \
          /usr/lib/aarch64-linux-gnu/libavfilter.so.10* \
          /usr/lib/aarch64-linux-gnu/libavformat.so.61* \
          /usr/lib/aarch64-linux-gnu/libavutil.so.59* \
    || true

# ld.so.conf 指向 CIX 库
RUN echo "/usr/share/cix/lib" > /etc/ld.so.conf.d/cix.conf && ldconfig

# CIX 补丁编译的 Jellyfin DLL（CI 编译步骤产出, self-contained 含运行时）
COPY publish/ /jellyfin/

# jellyfin-web 硬件加速下拉是前端硬编码, 后端枚举加了也不会显示; 注入 CIX VPU 选项
RUN set -e; f=$(ls /jellyfin/jellyfin-web/playback-transcoding.*.chunk.js); \
    sed -i 's|\((0,[a-z]*\.jsx)\)(\([A-Za-z]*\.[A-Za-z]*,\){value:"videotoolbox",children:"Apple VideoToolBox"})|\1(\2{value:"videotoolbox",children:"Apple VideoToolBox"}),\1(\2{value:"cix",children:"CIX VPU"})|' "$f" && \
    grep -q 'value:"cix"' "$f" && \
    # 复选框组: codec→types 白名单含当前 type 才渲染; cix 追加进 VPU 实测支持的 codec (h264/hevc 解码主力)
    sed -i 's|{name:"H264",codec:"h264",types:\([^]]*\)\]|{name:"H264",codec:"h264",types:\1,"cix"]|' "$f" && \
    sed -i 's|{name:"HEVC",codec:"hevc",types:\([^]]*\)\]|{name:"HEVC",codec:"hevc",types:\1,"cix"]|' "$f" && \
    grep -q 'codec:"h264",types:\[[^]]*"cix"' "$f" && \
    grep -q 'codec:"hevc",types:\[[^]]*"cix"' "$f" && \
    echo "web 已注入 CIX VPU 选项 + 硬件解码复选框(h264/hevc): $f"

# ffmpeg 主选 sky1 (8.0.1, 含 dsl_ratio 硬件缩放)；cix-ffmpeg 7.1.2 保留于 /usr/share/cix/bin 作回退
ENV JELLYFIN_FFMPEG=/usr/bin/ffmpeg
# 回退方式: 设 JELLYFIN_FFMPEG=/usr/share/cix/bin/ffmpeg
ENV VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json

# 运行时需挂载: --device /dev/video0 --device /dev/video1 --device /dev/dma_heap/system
