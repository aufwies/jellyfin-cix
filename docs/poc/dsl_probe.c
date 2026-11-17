// DSL probe: 验证 mvx VPU 驱动是否响应私有缩放 uAPI
// 编译: gcc -o dsl_probe dsl_probe.c
// 运行: ./dsl_probe [/dev/video0]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <linux/videodev2.h>

// 私有 uAPI (来自 mvx-v4l2-controls.h, cix_opensource__vpu_driver eb86680)
struct v4l2_mvx_dsl_ratio { unsigned int hor; unsigned int ver; };
#define VIDIOC_S_MVX_DSL_RATIO  _IOWR('V', BASE_VIDIOC_PRIVATE + 7, struct v4l2_mvx_dsl_ratio)
#define VIDIOC_G_MVX_DSL_RATIO  _IOWR('V', BASE_VIDIOC_PRIVATE + 6, struct v4l2_mvx_dsl_ratio)
#define VIDIOC_S_MVX_DSL_MODE   _IOWR('V', BASE_VIDIOC_PRIVATE + 9, int)

static void try_ioctl(int fd, unsigned long req, void *arg, const char *name) {
    int rc = ioctl(fd, req, arg);
    printf("%-28s rc=%d errno=%d (%s)\n", name, rc, rc == 0 ? 0 : errno,
           rc == 0 ? "OK ✓" : strerror(errno));
}

int main(int argc, char **argv) {
    const char *dev = argc > 1 ? argv[1] : "/dev/video0";
    int fd = open(dev, O_RDWR);
    if (fd < 0) { perror("open"); return 1; }

    struct v4l2_capability cap;
    ioctl(fd, VIDIOC_QUERYCAP, &cap);
    printf("device=%s driver=%s card=%s\n", dev, cap.driver, cap.card);

    // OUTPUT (码流端) 设 H264, 触发驱动初始化 codec session
    struct v4l2_format fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    fmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
    fmt.fmt.pix_mp.width = 3840; fmt.fmt.pix_mp.height = 2160;
    fmt.fmt.pix_mp.num_planes = 1;
    int rc = ioctl(fd, VIDIOC_S_FMT, &fmt);
    printf("S_FMT(H264 3840x2160)    rc=%d\n", rc);

    // 查询当前 DSL (G 若支持说明驱动认识此 uAPI)
    struct v4l2_mvx_dsl_ratio cur = {0, 0};
    try_ioctl(fd, VIDIOC_G_MVX_DSL_RATIO, &cur, "G_MVX_DSL_RATIO");

    // 设置 DSL 2:1 (hor=2, ver=2 —— 先按"分母"猜: 输出缩为一半; 其他语义再扫)
    struct v4l2_mvx_dsl_ratio r2 = {2, 2};
    try_ioctl(fd, VIDIOC_S_MVX_DSL_RATIO, &r2, "S_MVX_DSL_RATIO{2,2}");
    struct v4l2_mvx_dsl_ratio r4 = {4, 4};
    try_ioctl(fd, VIDIOC_S_MVX_DSL_RATIO, &r4, "S_MVX_DSL_RATIO{4,4}");

    int mode = 1;
    try_ioctl(fd, VIDIOC_S_MVX_DSL_MODE, &mode, "S_MVX_DSL_MODE(1)");

    // 读回验证
    struct v4l2_mvx_dsl_ratio back = {0, 0};
    try_ioctl(fd, VIDIOC_G_MVX_DSL_RATIO, &back, "G_MVX_DSL_RATIO(读回)");
    printf("读回值: hor=%u ver=%u\n", back.hor, back.ver);

    // CAPTURE (帧端) 看格式是否随之变化 (DSL 生效则 height 减半/四分)
    struct v4l2_format cf;
    memset(&cf, 0, sizeof(cf));
    cf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    rc = ioctl(fd, VIDIOC_G_FMT, &cf);
    if (rc == 0)
        printf("CAPTURE fmt: %dx%d %c%c%c%c\n", cf.fmt.pix_mp.width, cf.fmt.pix_mp.height,
               cf.fmt.pix_mp.pixelformat & 0xff, (cf.fmt.pix_mp.pixelformat >> 8) & 0xff,
               (cf.fmt.pix_mp.pixelformat >> 16) & 0xff, (cf.fmt.pix_mp.pixelformat >> 24) & 0xff);

    close(fd);
    return 0;
}
