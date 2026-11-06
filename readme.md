# Debian 11 (Bullseye) Rootfs — TBoard (RK3588S)

为 TBoard (RK3588S) 构建基于 linaro 底包的 Debian 11 (Bullseye) ARM64 根文件系统。
桌面环境 XFCE，板载 AIC8800 SDIO WiFi（含实验性 UART H4 蓝牙，详见 bsp/wifibt/README.bluetooth.md）。

## 构建

推荐从 SDK 根目录走统一入口：

    ./build.sh rockchip_rk3588s_tboard_debian11_defconfig
    ./build.sh debian
    ./build.sh firmware
    # 或一键完整构建（bootloader + kernel + rootfs + 打包）
    ./build.sh all

单独构建 rootfs（在本目录内执行）：

    # 1. 生成底包（已有 linaro-bullseye-alip-*.tar.gz 底包时可跳过）
    RELEASE=bullseye TARGET=desktop ARCH=arm64 ./mk-base-debian.sh

    # 2. 应用 overlay / bsp / packages，产出 binary/ 目录
    RELEASE=bullseye ARCH=arm64 ./mk-rootfs-bullseye.sh
    # 调试版：VERSION=debug ARCH=arm64 ./mk-rootfs-bullseye.sh

    # 3. 打包 ext4 镜像
    ./mk-image.sh

只读资源校验（脚本/固件校验和、核心包架构）：

    ARCH=arm64 ./debian/check-resources.sh   # SDK 根目录执行

更新 bsp/ 或 overlay-firmware/ 内容后需刷新校验和：

    (cd debian && find bsp overlay-firmware/lib/firmware/aic8800 -type f \
        ! -path bsp/SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > bsp/SHA256SUMS)

## 产物

| 文件 | 说明 |
| --- | --- |
| tboard-debian11-rootfs.img | 最终 rootfs 镜像（烧写用） |
| linaro-rootfs.img | mk-image.sh 中间产物，每次构建重新生成 |
| linaro-bullseye-alip-*.tar.gz | linaro 底包，保留可避免重新下载 |

## 默认账号

- root / root
- tboard / tboard（普通用户，有 sudo 权限）
- SSH 密码登录已开启（含 root）；串口控制台需账号密码登录。

## 主机依赖与常见问题

- 主机需安装 rsync：sudo apt-get install rsync
- 底包制作需要 qemu 用户态模拟：sudo apt-get install binfmt-support qemu-user-static
- debootstrap 报 noexec or nodev / Cannot install into target：构建目录所在分区需以 exec/dev 权限挂载：
  mount -o remount,exec,dev <挂载点>
