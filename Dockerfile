# ============================================================
# jellyfin-cix 多阶段构建
#
# Stage 1: 用 dotnet SDK 容器编译打补丁后的 Jellyfin
# Stage 2: 用官方 jellyfin 镜像 + CIX deb 组装运行时
#
# 构建前提: 构建上下文中 jellyfin/ 目录包含上游源码(submodule)
# ============================================================

# --- Stage 1: 编译 ---
# 内部: Forgejo 容器仓库的 SDK 镜像; GitHub: --build-arg SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:9.0
ARG SDK_IMAGE=git.example.com/rgan/dotnet-sdk:9.0
ARG BASE_REGISTRY=docker.m.daocloud.io
FROM ${SDK_IMAGE} AS build

# 复制上游源码 + CIX 补丁 + NuGet 镜像源
COPY jellyfin/ /src
COPY patches/ /patches
COPY nuget.config /src/nuget.config

# 应用补丁并编译
RUN cd /src && \
    cat /patches/*.patch | patch -p1 && \
    dotnet publish Jellyfin.Server/Jellyfin.Server.csproj \
        -c Release -o /out \
        -p:UseAppHost=false

# --- Stage 2: 运行时 ---
ARG BASE_REGISTRY
FROM ${BASE_REGISTRY}/jellyfin/jellyfin:10.11.11

# CIX 专有二进制（deb 解包）
COPY debs/ /tmp/cix-debs/
RUN cd /tmp/cix-debs && \
    for deb in *.deb; do \
        [ "$deb" = "SHA256SUMS" ] && continue; \
        dpkg -x "$deb" /; \
    done && rm -rf /tmp/cix-debs

# 公共依赖（Debian 公开包）
RUN apt-get update -qq && \
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

# 从编译阶段拿 DLL
COPY --from=build /out/MediaBrowser.Controller.dll /out/MediaBrowser.Model.dll /jellyfin/

ENV JELLYFIN_FFMPEG=/usr/share/cix/bin/ffmpeg

# 运行时需挂载: --device /dev/video0 --device /dev/video1 --device /dev/dma_heap/system
