# Lakka - The DIY retro emulation console

Lakka is a lightweight Linux distribution that transforms a small computer into a full blown emulation console.

## Why use Lakka?

* **Powerful** - Built on top of the famous RetroArch emulator, Lakka is able to emulate a large range of hardware and has some useful features such as Braid-like rewinding, joypad hotplug and video streaming.
* **User friendly** - Lakka is easy to setup and use. Once installed to your SD card, you just have to put your rom on the card, plug your joypad and enjoy your favorite old games. We also support PS3 and XBox360 controllers so you don't have to buy new ones. 
* **Low cost** - We try our best to keep the hardware required to run Lakka as cheap as possible. The software is optimized to run fast even on low end computers. The power can be supplied by any micro USB adapter like the one for your smartphone.
* **Open source** - Our code is free as in freedom and hosted on Github (though the project uses emulators that forbid commercialisation). We accept external contributions, and we do our best to integrate our own patches into upstream projects.

## Installation instructions

Please refer to our website https://www.lakka.tv/get on how to setup Lakka.

## Rockchip / 野火鲁班猫支持（`rk3588-port` 分支）

本分支为野火（Embedfire）鲁班猫系列板卡提供 Lakka 支持，基于厂商 BSP 构建（vendor 6.1 内核 + vendor u-boot 2017.09 FIT 引导链 + rkbin）。所有源码都是构建时按钉住的 commit 自动从 GitHub 拉取，无需手动下载任何东西。

* **支持板卡**：鲁班猫 4 / 4-V1 / 5 / 5-V2 / 5IO（RK3588 / RK3588S）
* **验证状态**：鲁班猫 5 与鲁班猫 4 已上机验证（HDMI 出图、调试串口 root shell、首次开机自动扩容）；5-V2 / 5IO 已通过构建期产物校验，待上机测试
* **内置能力**：`build-board.sh` 选板构建、`mk-rockchip-update.sh` 打包 eMMC 用的 update.img（RKDevTool/upgrade_tool 直刷，**不依赖野火 SDK**）、`setup-cn-network.sh` 国内网络一键配置、串口（`/dev/ttyFIQ0`）开箱即用 root shell

### 快速开始

```sh
# 1. 安装宿主依赖（Ubuntu/Debian x86_64）
sudo apt-get install make gcc g++ sed gawk wget patch pkg-config bison flex \
  ntp libssl-dev libxml2-dev zlib1g-dev libncurses-dev bc rsync zip unzip \
  imagemagick default-jre-headless xsltproc device-tree-compiler git lz4 \
  zstd libparse-yapp-perl rdfind
# （或用构建系统自查：  ./scripts/checkdeps）

# 2. 克隆本分支
git clone -b rk3588-port https://github.com/raidenkl/Lakka-LibreELEC.git
cd Lakka-LibreELEC

# 3. 选板构建，产物在 target/（SD 卡直写；eMMC 见下）
./projects/Rockchip/tools/build-board.sh                        # 菜单选板
# ./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5    # 直接指定

# 国内网络不稳时，先执行一次（用户级配置，可 -u 撤销）
./projects/Rockchip/tools/setup-cn-network.sh
```

**刷写**：`target/*.img.gz` 解压后用 balenaEtcher/Rufus(DD 模式) 写 SD 卡；eMMC 用
RKDevTool（MaskROM + 「下载镜像」）或先 `./projects/Rockchip/devices/RK3588/tools/mk-rockchip-update.sh`
打包成 update.img 再刷。

**详细文档**（逐板构建与刷写指南、串口调试、update.img 打包、相对厂商默认配置的全部改动说明，均为中文）：
[`projects/Rockchip/devices/RK3588/README.md`](projects/Rockchip/devices/RK3588/README.md)
与
[`projects/Rockchip/devices/RK3588/BUILD_GUIDE.md`](projects/Rockchip/devices/RK3588/BUILD_GUIDE.md)。

## Support

* [FAQ](https://github.com/libretro/Lakka-LibreELEC/wiki/FAQ)
* #lakkatv on irc.libera.chat
* [Discord](https://discord.gg/BNFR4hM)
* [Forums](https://forums.libretro.com/c/libretro/lakka-tv-general)
