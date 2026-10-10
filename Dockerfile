ARG BASE_REGISTRY=docker.io

FROM ${BASE_REGISTRY}/jellyfin/jellyfin:10.11.11

# CIX 专有组件（仓库内自带 deb）
COPY debs/ /tmp/cix-debs/

# 解包 CIX deb 到镜像
RUN cd /tmp/cix-debs && \
    for deb in *.deb; do \
        [ "$deb" = "SHA256SUMS" ] && continue; \
        dpkg -x "$deb" /; \
    done && \
    rm -rf /tmp/cix-debs

# 公共依赖（Debian 公开包）
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        libavdevice61 \
        libpostproc58 \
        libswresample5 \
        libswscale8 \
        libyuv0 \
        ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*

# 删除 Debian 的 libav*（与 CIX 版本冲突, CIX 必须优先）
RUN rm -f /usr/lib/aarch64-linux-gnu/libavcodec.so.61* \
          /usr/lib/aarch64-linux-gnu/libavfilter.so.10* \
          /usr/lib/aarch64-linux-gnu/libavformat.so.61* \
          /usr/lib/aarch64-linux-gnu/libavutil.so.59* \
          /usr/lib/aarch64-linux-gnu/libva.so.2* \
          /usr/lib/aarch64-linux-gnu/libva-drm.so.2* \
    || true

# ld.so.conf 指向 CIX 库
RUN echo "/usr/share/cix/lib" > /etc/ld.so.conf.d/cix.conf && ldconfig

# CIX 补丁编译的 Jellyfin dll
COPY publish/MediaBrowser.Controller.dll publish/MediaBrowser.Model.dll /jellyfin/

ENV JELLYFIN_FFMPEG=/usr/share/cix/bin/ffmpeg

# 运行时需挂载: /dev/video0 /dev/video1 /dev/dma_heap/*
