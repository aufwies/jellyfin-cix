// LD_PRELOAD: 在 ffmpeg v4l2m2m 解码会话 STREAMON 前注入 mvx DSL 缩放
// 用法: LD_PRELOAD=./libdsl.so MVX_DSL_HOR=2 MVX_DSL_VER=2 ffmpeg ...
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>

struct v4l2_mvx_dsl_ratio { unsigned int hor; unsigned int ver; };
#define VIDIOC_S_MVX_DSL_RATIO _IOWR('V', BASE_VIDIOC_PRIVATE + 7, struct v4l2_mvx_dsl_ratio)
#define VIDIOC_S_MVX_DSL_MODE  _IOWR('V', BASE_VIDIOC_PRIVATE + 9, int)

static int injected = 0;

int ioctl(int fd, unsigned long req, ...) {
    static int (*real_ioctl)(int, unsigned long, ...) = NULL;
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    va_list ap; va_start(ap, req);
    void *arg = va_arg(ap, void*);
    va_end(ap);

    if (!injected && req == VIDIOC_STREAMON && arg) {
        enum v4l2_buf_type t = *(enum v4l2_buf_type *)arg;
        if (t == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE || t == V4L2_BUF_TYPE_VIDEO_OUTPUT) {
            // 先放行真正的 streamon? 不: 注入要在 streamon 之前 → 先设 DSL 再透传
            const char *hs = getenv("MVX_DSL_HOR"), *vs = getenv("MVX_DSL_VER");
            unsigned h = hs ? atoi(hs) : 2, v = vs ? atoi(vs) : 2;
            if (h > 0 && v > 0) {
                struct v4l2_mvx_dsl_ratio r = { h, v };
                int mode = 1;
                int rc1 = real_ioctl(fd, VIDIOC_S_MVX_DSL_MODE, &mode);
                int rc2 = real_ioctl(fd, VIDIOC_S_MVX_DSL_RATIO, &r);
                fprintf(stderr, "[libdsl] injected DSL %u:%u (mode rc=%d ratio rc=%d) fd=%d\n",
                        h, v, rc1, rc2, fd);
                injected = 1;
            }
        }
    }
    return real_ioctl(fd, req, arg);
}
