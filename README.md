# Lakka - The DIY retro emulation console

Lakka is a lightweight Linux distribution that transforms a small computer into a full blown emulation console.

## Why use Lakka?

* **Powerful** - Built on top of the famous RetroArch emulator, Lakka is able to emulate a large range of hardware and has some useful features such as Braid-like rewinding, joypad hotplug and video streaming.
* **User friendly** - Lakka is easy to setup and use. Once installed to your SD card, you just have to put your rom on the card, plug your joypad and enjoy your favorite old games. We also support PS3 and XBox360 controllers so you don't have to buy new ones. 
* **Low cost** - We try our best to keep the hardware required to run Lakka as cheap as possible. The software is optimized to run fast even on low end computers. The power can be supplied by any micro USB adapter like the one for your smartphone.
* **Open source** - Our code is free as in freedom and hosted on Github (though the project uses emulators that forbid commercialisation). We accept external contributions, and we do our best to integrate our own patches into upstream projects.

## Installation instructions

Please refer to our website https://www.lakka.tv/get on how to setup Lakka.

## Rockchip / Embedfire LubanCat support (`rk3588-port` branch)

**This branch adds Lakka support for the Embedfire LubanCat boards on Rockchip RK3588 / RK3588S**, built on the vendor BSP (kernel 6.1 + vendor u-boot 2017.09 FIT chain + rkbin). All sources are pinned upstream commits fetched automatically at build time - nothing needs to be downloaded manually.

* **Supported boards**: LubanCat 4, LubanCat 4-V1, LubanCat 5, LubanCat 5-V2, LubanCat 5IO
* **Status**: boot-verified on LubanCat 5 and LubanCat 4 (HDMI out, root shell on the debug UART, first-boot storage auto-resize); 5-V2 / 5IO images pass build-time artifact checks and await hardware testing
* **Useful extras**: `build-board.sh` board picker, `mk-rockchip-update.sh` (packs a Rockchip `update.img` for eMMC flashing via RKDevTool/upgrade_tool, vendor SDK not required), `setup-cn-network.sh` (one-time mirror setup for building from mainland China), serial console on `/dev/ttyFIQ0` out of the box

### Quick start

```sh
# 1. host dependencies (Ubuntu/Debian x86_64)
sudo apt-get install make gcc g++ sed gawk wget patch pkg-config bison flex   ntp libssl-dev libxml2-dev zlib1g-dev libncurses-dev bc rsync zip unzip   imagemagick default-jre-headless xsltproc device-tree-compiler git lz4   zstd libparse-yapp-perl rdfind
# (or let the build check them for you:  ./scripts/checkdeps)

# 2. clone this branch
git clone -b rk3588-port https://github.com/raidenkl/Lakka-LibreELEC.git
cd Lakka-LibreELEC

# 3. pick a board and build (SD-card image in target/)
./projects/Rockchip/tools/build-board.sh                 # interactive menu
# ./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5   # direct

# mainland-China network mirror setup (optional, one-time, user-level)
./projects/Rockchip/tools/setup-cn-network.sh
```

Full documentation - per-board build & flashing guides, serial-console debugging, update.img packaging, and every intentional deviation from the vendor defaults - lives in
[`projects/Rockchip/devices/RK3588/README.md`](projects/Rockchip/devices/RK3588/README.md)
and
[`projects/Rockchip/devices/RK3588/BUILD_GUIDE.md`](projects/Rockchip/devices/RK3588/BUILD_GUIDE.md)
(中文).

### 中文说明

本分支为野火（Embedfire）鲁班猫系列板卡提供 Lakka 支持，基于厂商 BSP（6.1 内核 + 厂商 u-boot）。三步出镜像：装依赖（`./scripts/checkdeps` 可自查）→ `git clone -b rk3588-port` 本仓库 → `./projects/Rockchip/tools/build-board.sh` 选板构建，产物在 `target/`（SD 卡直写；eMMC 可用 `mk-rockchip-update.sh` 打成 update.img 走 RKDevTool）。国内网络不稳定时先执行一次 `./projects/Rockchip/tools/setup-cn-network.sh`。详细文档见 `projects/Rockchip/devices/RK3588/{README,BUILD_GUIDE}.md`（中文）。

## Support

* [FAQ](https://github.com/libretro/Lakka-LibreELEC/wiki/FAQ)
* #lakkatv on irc.libera.chat
* [Discord](https://discord.gg/BNFR4hM)
* [Forums](https://forums.libretro.com/c/libretro/lakka-tv-general)
