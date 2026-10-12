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

# CIX 专有二进制（deb 解包）
COPY debs/ /tmp/cix-debs/
RUN cd /tmp/cix-debs && \
    for deb in *.deb; do \
        [ "$deb" = "SHA256SUMS" ] && continue; \
        dpkg -x "$deb" /; \
    done && rm -rf /tmp/cix-debs

# 公共依赖（Debian 公开包, 走内网可达的华为云 mirror）
RUN sed -i 's|deb.debian.org|repo.huaweicloud.com|g; s|security.debian.org|repo.huaweicloud.com|g' \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        libavdevice61 libpostproc58 libswresample5 libswscale8 \
        libyuv0 ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*

# 删除 Debian 的 libav*（CIX 版本必须优先）
RUN rm -f /usr/lib/aarch64-linux-gnu/libavcodec.so.61* \
          /usr/lib/aarch64-linux-gnu/libavfilter.so.10* \
          /usr/lib/aarch64-linux-gnu/libavformat.so.61* \
          /usr/lib/aarch64-linux-gnu/libavutil.so.59* \
          /usr/lib/aarch64-linux-gnu/libva.so.2* \
          /usr/lib/aarch64-linux-gnu/libva-drm.so.2* \
    || true

# ld.so.conf 指向 CIX 库
RUN echo "/usr/share/cix/lib" > /etc/ld.so.conf.d/cix.conf && ldconfig

# CIX 补丁编译的 Jellyfin DLL（CI 编译步骤产出）
COPY publish/ /jellyfin/

ENV JELLYFIN_FFMPEG=/usr/share/cix/bin/ffmpeg

# 运行时需挂载: --device /dev/video0 --device /dev/video1 --device /dev/dma_heap/system
