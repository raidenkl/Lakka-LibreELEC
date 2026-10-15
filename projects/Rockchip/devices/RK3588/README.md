# RK3588 - 鲁班猫5（野火 LubanCat 5）

这是 RK3588 的设备项目，面向野火鲁班猫5 系列开发板，使用 Rockchip/野火的
vendor 启动链与 vendor 内核：

* U-Boot：[LubanCat/u-boot](https://github.com/LubanCat/u-boot) 分支 `main`
  （U-Boot 2017.09 的厂商 fork，走 FIT 启动链，由厂商脚本 `make.sh`/`fit.sh` 打包）
* rkbin：[LubanCat/rkbin](https://github.com/LubanCat/rkbin) 分支 `master`
* 内核：[LubanCat/kernel](https://github.com/LubanCat/kernel) 分支 `lbc-develop-6.1`
* GPU：Rockchip `libmali` 闭源 blob（Mali-G610 / Valhall）—— vendor 内核里没有 panfrost

## 快速开始（三步）

```sh
git clone -b rk3588-port https://github.com/raidenkl/Lakka-LibreELEC.git
cd Lakka-LibreELEC
cd projects/Rockchip/devices/RK3588/tools

./fix-build-env.sh          # ① 修好宿主依赖 + 网络垫片（幂等，可重复跑；--check 只检查）
./configure-cores.sh        # ② 选要打进镜像的游戏机核心（有推荐预设）
./resume-build.sh           # ③ 编译（后台跑：./resume-build.sh & 然后 tail -f /tmp/rk3588-build-image.log）
```

产物在仓库根的 `target/Lakka-RK3588.aarch64-*.img.gz`。

- **SD 卡**：`gzip -dc target/…img.gz | dd of=/dev/sdX bs=4M status=progress conv=fsync`（或 balenaEtcher / Rufus DD 模式）
- **eMMC**：Windows 用 RKDevTool「升级固件」加载 `target/…-update.img`（由
  `mk-rockchip-update.sh --board <board>` 生成；afptool/rkImageMaker 已内置在本目录
  `rkfw/`，**不需要野火 SDK**），或 Linux 下 `rkdeveloptool` / `upgrade_tool`
- 也可以用仓库级的板卡选择脚本直接构建（含产物校验）：
  `projects/Rockchip/tools/build-board.sh RK3588 lubancat-4`（`--list` 列出全部芯片/板卡）

## 工具脚本（`tools/`）

| 脚本 | 用途 |
| --- | --- |
| `fix-build-env.sh` | **国内构建的第一步**。补齐 `scripts/checkdeps` 要求而系统缺失的宿主依赖（`zstd`、`Parse::Yapp`+`yapp`、`JSON`、`rdfind`，**不需要 sudo**），并装好网络垫片（git 镜像重定向 + `~/bin/wget` 包装器）。幂等；`--check` 只报告不修改 |
| `configure-cores.sh` | **游戏机核心配置 GUI**（dialog/whiptail）。按 9 大分类勾选要打进镜像的核心，内置「只留主流现代机种」「再砍编译大件」等预设，写回 `options` 的 `EXCLUDE_LIBRETRO_CORES` 前会自备份并校验名字 |
| `gen-cores-data.py` | 重新生成 `cores-data.tsv`（上游 `LIBRETRO_CORES` 名单变化后运行一次即可） |
| `cores-data.tsv` | 核心元数据：分类、推荐取舍（keep/remove/remove-heavy/managed）、备注 |
| `resume-build.sh` | 一键（继续）构建。已设好 `PROJECT/DEVICE/ARCH/UBOOT_SYSTEM/PATH/PERL5LIB`，失败时自动打印第一处 `FAILED COMMAND` 的上下文 |
| `audit-missing-sources.sh` | 列出「构建计划里、源码缓存还没准备好」的包（git 看 `.gitstamp`，归档看 `.url`+`.sha256`） |
| `seed-missing-sources.sh` | 批量预置上一步列出的包（逐包调用 `seed-any-pkg.sh`） |
| `seed-any-pkg.sh` | 单个包的源码预置：git 源走真正的 `git fetch`（**含递归子模块**，github 自动经镜像，git 校验 SHA 保证内容可信）；归档源下载后与 `PKG_SHA256` 比对 |
| `wget-gh-mirror` | `wget` 包装器，会被装成 `~/bin/wget`：GitHub 归档/Release 走镜像，其它主机退化为 `https→http` |
| `NETWORK_BUILD.md` | **国内网络构建的原理、验证步骤与完整排查表** —— 构建被网络卡住时先读这个 |

> 提示：`fix-build-env.sh`、`configure-cores.sh`、`resume-build.sh` 都不需要 sudo，
> 也不会碰 `sources/` 与 `build.*/` 之外的东西。

## 编译依赖（宿主机）

构建机必须是 **x86_64 Linux**，并且必须用**非 root 用户**编译（构建系统会拒绝以
root 运行）。完整编译一个镜像大致需要 **50–60 GiB 可用磁盘** 与 **≥16 GiB 内存**；
4 核够用，若被 OOM killer 杀掉就用 `THREADCOUNT=2` 重新编译。

### 1. 必需软件包（`scripts/checkdeps` 会逐项检查）

`make image` 会先执行 `scripts/checkdeps`，下面任何一项缺失都会直接中止。Ubuntu/Debian：

```sh
sudo apt-get install -y \
  bc bzip2 curl diffutils file g++ gawk gcc gperf git gzip lzop make patch \
  patchutils perl rdfind rsync sed tar unzip wget xz-utils zip zstd \
  libc6-dev libncurses5-dev \
  libjson-perl libparse-yapp-perl libxml-parser-perl
```

| 软件包 | 用途 |
| --- | --- |
| `bc` `bzip2` `curl` `diffutils` `file` `g++` `gawk` `gcc` `gperf` `git` `gzip` `lzop` `make` `patch` `rsync` `sed` `tar` `unzip` `wget` `xz-utils` `zip` | LibreELEC/Lakka 的标准宿主工具集 |
| `zstd` | 解压 `.tar.zst` 源码包——`scripts/extract` 调用的是 `zstdcat`；装不上时会报出**误导性的** `tar: This does not look like a tar archive` |
| `libparse-yapp-perl` | 同时提供 `Parse::Yapp` 模块**和 `yapp` 程序**。samba 自带的 `pidl` 硬性要求 `yapp`（`pidl/wscript`：`raise WafError('yapp not found')`），没有任何 configure 开关能绕开 |
| `libjson-perl` | `JSON` 被 `checkdeps` 检查，samba 也确实会用到 |
| `libxml-parser-perl` | 提供 `XML::Parser`，被 `checkdeps` 检查 |
| `perl` | 同时提供 `Thread::Queue`，被 `checkdeps` 检查 |
| `patchutils` | 提供 `lsdiff`，被 `checkdeps` 检查 |
| `libc6-dev`、`libncurses5-dev` | 提供 `/usr/include/stdio.h` 与 `/usr/include/ncurses.h`，被 `checkdeps` 检查 |
| `rdfind` | **仅被 `checkdeps` 探测**，整个编译流程从不调用它（发行版二进制跑不起来时见第 3 节的处理办法） |

> 各发行版的包名会有差异：新版里 `libncurses5-dev` 已改名为 `libncurses-dev`，而
> Python 2（见下一节）可能只在 `universe` 组件里、甚至完全不再提供——遇到这种情况
> 请用第 3 节的办法，或直接在较老的容器里编译（本移植的参考宿主是 Ubuntu 20.04）。

### 2. vendor 启动链额外需要的工具

设备级的 `u-boot` 包会去驱动野火的厂商脚本 `make.sh`/`fit.sh`，FIT 镜像是它们自己
打包的，所以这些工具不在 `checkdeps` 的检查范围内：

```sh
sudo apt-get install -y device-tree-compiler python2 u-boot-tools
```

| 软件包 | 用途 |
| --- | --- |
| `device-tree-compiler`（`dtc`） | 打包 FIT 时编译设备树 |
| `python2` | 厂商的 `make.sh`/`fit.sh` 是 Python 2 脚本 |
| `u-boot-tools`（`mkimage`） | 可选——vendor 源码树里自带 `mkimage` |
| `qemu-user-static` | **仅当宿主不是 x86_64 时需要**：rkbin 的打包装工具是 x86_64 二进制，要通过 `qemu-x86_64` 执行 |

### 3. 没有 `sudo` 的宿主机（以及懒人做法）

> **推荐先跑 `tools/fix-build-env.sh`** —— 它把本节所有手动步骤都自动化了（幂等、可重复跑，
> `--check` 只检查不修改）。下面保留手动步骤，便于理解脚本到底做了什么。

只有在能使用 `sudo` 时 `checkdeps` 才能自动安装。没有 root 权限时，可以从发行版的
软件包里取同样的依赖，直接解包到 `$HOME` 下使用：

```sh
mkdir -p "$HOME/bin" "$HOME/perl5"
curl -sL -o /tmp/libparse-yapp-perl.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libp/libparse-yapp-perl/libparse-yapp-perl_1.21-2_all.deb
mkdir -p /tmp/yapp && dpkg-deb -x /tmp/libparse-yapp-perl.deb /tmp/yapp
cp -a /tmp/yapp/usr/share/perl5/. "$HOME/perl5/"
install -Dm755 /tmp/yapp/usr/bin/yapp "$HOME/bin/yapp"
# libjson-perl 同理；zstd 也可以这样借一个现成的 1.5.x 二进制
export PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB"
```

有两条经验值得记住：

* **绝不要用假的模块或脚本来凑依赖。** 一个假的 `Parse::Yapp::Driver` 能骗过
  `checkdeps` 的探测、也能骗过 samba 早期的模块检查，但要等到更靠后的
  `find_program('yapp')` 才失败——那时排查难度大得多。`rdfind` 是唯一安全的例外：
  它只被探测、从不被调用。（它在新版 pool 里的二进制还依赖比某些宿主更新的
  `libnettle`，这种情况下一个 `exit 0` 的占位脚本比一个「一被调用就崩」的真二进制
  更可取。）
* **非交互式 shell 不会读取 `~/.bashrc`**，所以通过 `ssh` 启动编译时必须显式传入
  路径，例如：
  `env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" make image`。

完整的逐步编译流程与故障排查表（网络重试、源码缓存、已知报错信息）见同目录下的
`BUILD_GUIDE.md`。

## 编译

推荐用板卡选择脚本（板卡清单从 `scripts/uboot_helper` 现取，新增板卡/芯片后**不用改脚本**）：

```sh
projects/Rockchip/tools/build-board.sh                      # 菜单：选芯片 → 选板卡
projects/Rockchip/tools/build-board.sh RK3588 lubancat-4    # 直接构建
projects/Rockchip/tools/build-board.sh --list               # 列出所有 (芯片, 板卡)
```

脚本会做白名单校验、磁盘预检、清理 u-boot 构建树、`make image`（日志
`/tmp/lakka-build-<board>.log`），构建成功后**自动校验产物**：boot 分区里只有
该板的 dtb、`extlinux.conf` 的 `FDT` 指向它、dtb 的 `model` 与 HDMI 路由
（`hdmi@fde80000` / `route-hdmi0`）、32 KiB / 8 MiB 引导魔数、sha256。
逐板跑即可，已构建的其它板镜像不会被删。

也可以直接用 make（等价）：

* `PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 make image`

板卡（`UBOOT_SYSTEM`）：

| 板卡 | 型号 | 内核 dtb | u-boot defconfig | DDR blob | 状态 |
| --- | --- | --- | --- | --- | --- |
| `lubancat-5` | 鲁班猫5（RK3588） | `rk3588-lubancat-5.dtb` | `lubancat-5-rk3588-pcie_defconfig` | lp4 2112MHz | 已上机验证 |
| `lubancat-5-v2` | 鲁班猫5 V2（RK3588） | `rk3588-lubancat-5-v2.dtb` | 复用 `lubancat-5-rk3588-pcie_defconfig`（厂商无 5-V2 专用 defconfig） | lp4 2112MHz | 静态校验通过，待上机 |
| `lubancat-5io` | 鲁班猫5IO / 5IOB（RK3588） | `rk3588-lubancat-5io.dtb` | `lubancat-5io-rk3588-pcie_defconfig` | lp4 2112MHz | 静态校验通过，待上机 |
| `lubancat-4` | 鲁班猫4（**RK3588S**） | `rk3588s-lubancat-4.dtb` | `lubancat-4-rk3588s-msata_defconfig` | lp4 1848MHz（厂商默认；可用 `DDR_FREQ=2112` 覆盖） | **已上机验证** |
| `lubancat-4-v1` | 鲁班猫4 硬件版本 V1（RK3588S） | `rk3588s-lubancat-4-v1.dtb` | 复用 `lubancat-4-rk3588s-msata_defconfig` | 同上 | 与 v0 只差 DSI 复位/触摸中断引脚（见 BUILD_GUIDE §4.5），不用 MIPI 屏可通用 |

显示通路：四块板都打开 VP0 → HDMI0（`patches/linux/vendor/rockchip-9000/9001/9002-*-enable-hdmi0-vp0.patch`）。
`lubancat-5-v2` 的 dts include 了 `lubancat-5.dts`，自动继承 9000 号补丁。

## 引导布局（eMMC / SD）

镜像按野火 SDK 使用的偏移摆放 Rockchip 启动链（参见 LubanCat SDK 里的
`device/rockchip/.chips/rk3588/parameter-extboot.txt`）：

| 偏移 | 内容 | 由谁生成 |
| --- | --- | --- |
| 32 KiB（LBA 64） | SPL loader（`rk3588_spl_loader_v*.bin`） | rkbin，经 `make.sh`/`fit.sh` |
| 8 MiB（LBA 16384） | `uboot.img`（FIT：U-Boot + BL31/BL32，已填充） | `loaderimage`，经 `fit.sh` |
| 16 MiB（LBA 32768） | BOOT 分区（vfat + extlinux） | `scripts/mkimage` |

启动由 U-Boot 的 `distro_bootcmd` 完成，它会读取 BOOT 分区里的
`/extlinux/extlinux.conf`。

## 串口控制台

UART2，**1500000 8N1**，在系统里表现为 **`/dev/ttyFIQ0`**（Rockchip FIQ debugger 接管了 UART2，没有可用的 `ttyS2`）。系统自带一个 root 串口 shell（`rk-serial-console` 包提供的 `ttyFIQ0-console.service`，直接在 tty 上起 `/bin/sh -l`，不需要登录）。
`DEBUG_TTY` 为 `/dev/ttyS2`。

## 国内网络构建

在中国大陆的宿主机上，`github.com` 往往**直连被阻断**（`curl https://github.com` 返回 `000`，
`git fetch` 报 `gnutls_handshake() failed` / `Connection timed out`）。本仓库的 `tools/`
把这些坑都封成了脚本，一次跑 `tools/fix-build-env.sh` 即可：

```sh
cd projects/Rockchip/devices/RK3588/tools
./fix-build-env.sh --check     # 先看缺什么
./fix-build-env.sh             # 实际修复
```

它做了三件事：

1. **宿主依赖**：`zstd` / `Parse::Yapp`+`yapp` / `JSON` / `rdfind`（从 Ubuntu pool 解包 `.deb`，
   不需要 sudo）。这些缺失时的报错**非常误导**，例如缺 `zstd` 会报成
   `tar: This does not look like a tar archive`。
2. **git 全局镜像重定向**：
   `git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"`
   —— 这一条同时覆盖 **git 源包**、**git 子模块（含嵌套）**、以及 **CMake `FetchContent`**
   （例如 `melondsds` 在 configure 阶段要拉 11 个 GitHub 依赖）。
   可以放心：git 会按对象 SHA 校验，镜像最多让下载失败，不可能篡改源码。
3. **`~/bin/wget` 包装器**：管 git 管不到的下载 —— 归档源（`.../archive/<sha>.tar.gz`）与
   Release 资产走镜像；非 GitHub 主机（如 `www.kernel.org`）退化为 `https→http`。
   （GitHub 有 HSTS，单纯 `https→http` 降级对它是无效的。）

如果仍有个别包拉不到（镜像临时不可用、仓库不在 GitHub、或 recipe 钉的哈希过期）：

```sh
./audit-missing-sources.sh      # 列出还缺源码缓存的包
./seed-missing-sources.sh       # 逐个预置（git 含子模块；归档做 SHA256 校验）
./resume-build.sh               # 继续构建
```

**原理、验证步骤与完整排查表见 [`tools/NETWORK_BUILD.md`](tools/NETWORK_BUILD.md)。**

## 游戏机核心裁剪（GUI）

镜像里的 libretro 核心可以自由增减——构建系统内置了官方排除机制
（`packages/lakka/libretro_cores/package.mk` 里对 `EXCLUDE_LIBRETRO_CORES` 做字符串替换）。
本设备目录提供一个交互式配置脚本：

```sh
cd projects/Rockchip/devices/RK3588/tools
./configure-cores.sh            # 交互式（dialog 两级菜单）
./configure-cores.sh --list     # 只看当前配置
./configure-cores.sh --preset a # 直接套用「只留主流现代机种」
./configure-cores.sh --preset b # 方案 A + 砍掉编译最慢的大件
./configure-cores.sh --dry-run --preset b   # 只打印将写入的内容
```

脚本特点：

* **只允许从真实名单里选**——`EXCLUDE_LIBRETRO_CORES` 是纯字符串替换，**写错名字会被静默忽略**
  （不报错），所以脚本在写回前会逐名校验。
* **按 9 大分类勾选**（任天堂/世嘉/索尼/雅达利/街机/掌机/老式电脑/游戏引擎/幻想平台），
  每项的初始状态来自当前 `options`。
* **预设方案**：A「只留主流现代机种」、B「A + 砍掉编译最慢的大件」、
  全部保留、以及自定义。方案里已经默认排除 3 个 Rust 核心
  （`rustation_ng`/`boytacean`/`doukutsu_rs`）——它们会拉入 130 MB 的 LLVM 源码，国内下载基本必失败。
* **写回前自动备份** `options`（`options.bak.<时间戳>`），并保留文件里的注释块。
* 改完可选择**重新生成构建计划并对比**，直接看到核心数/任务数变化。

> ⚠️ **改完必须重启构建 job**：正在运行的 job 用的是生成时的计划，改 `options` 不会回溯。
> 停旧 job 用 `pkill -f pkgbuilder`，**不要**用 `pkill -f "scripts/build"`（会自匹配杀掉你自己的 ssh shell）。

完整核心对照表（含每个核心的机种说明与备注）见同目录 [`CORES.md`](CORES.md)。

## 移植说明（本地构建）

### 源码缓存

本构建机到 GitHub 的连接很差（`git fetch` 会以 `early EOF` 中断），所以 vendor 相关
包的源码是**预先放入 `sources/`** 的，而不是现场下载：

| 软件包 | 缓存文件 | 来源 |
| --- | --- | --- |
| linux | `sources/linux/linux-<sha>.tar.xz` | 对 SDK 内核树（分支 `lbc-develop-6.1`）执行 `git archive` |
| u-boot | `sources/u-boot/u-boot-<sha>.tar.xz` | 对 SDK u-boot 树执行 `git archive` |
| rkbin | `sources/rkbin/rkbin-<sha>.tar.xz` | 对 SDK rkbin 树执行 `git archive` |
| libmali | `sources/libmali/libmali-1.9-1.tar.xz` | 从 `libmali-valhall-g610-g24p0-gbm_1.9-1_arm64.deb` 重新打包 + SDK Debian rootfs 里的 Khronos 头文件 |

由于这些 tarball 是本地生成的，它们的 `PKG_SHA256` 与 GitHub 上官方归档的值不同。
删掉 `sources/<pkg>/*.tar.xz*` 就会触发真实下载（届时需要刷新 `PKG_SHA256`）。

### 内核补丁

主线 Rockchip 内核补丁集放在 `projects/Rockchip/patches/linux/default/`，由主线内核
分支（`PKG_PATCH_DIRS="default"`）套用。vendor 内核分支（`lubancat-6.1`）改用
`projects/Rockchip/patches/linux/vendor/`，因此那批主线补丁不会打到 6.1 vendor 内核上。

本设备在 `patches/linux/vendor/` 下自带一个 vendor 内核补丁：

| 补丁 | 作用 |
| --- | --- |
| `rockchip-9000-rk3588-lubancat-5-enable-hdmi0-vp0.patch` | 取消注释 `rk3588-lubancat-5.dts` 里 `#include "rk3588-lubancat-5-hdmi0-vp0.dtsi"`。厂商在这份板级 dts 中把所有显示路由 include 都注释掉了，导致 `&hdmi0`/`&hdmi0_in_vp0`/`&route_hdmi0` 从未 enable、vop2 注册 0 个 CRTC、DRM 绑定失败，**HDMI 全程无信号**。加上这个补丁后 VP0 → HDMI0 通路才成立（同时带来 `rockchip-hdmi0` 声卡） |

除补丁外，设备内核配置 `linux/lubancat-6.1/linux.aarch64.conf` 相对厂商
`lubancat_linux_rk3588_defconfig` 只有两处功能性差异，两处都是**必需**的：

| 配置项 | 为什么必需 |
| --- | --- |
| `CONFIG_SQUASHFS_ZSTD=y` | 本项目用 zstd 打 SYSTEM squashfs（`projects/Rockchip/options` 的 `SQUASHFS_COMPRESSION="zstd"`），厂商 defconfig 只开了 zlib/lzo/xz，缺它则镜像**挂不上 rootfs、永远进不了系统**（表现为反复刷 `Filesystem uses "zstd" compression. This is not supported`） |
| `# CONFIG_WERROR is not set` | 厂商 defconfig 是 `CONFIG_WERROR=y`，而我们用 GCC 13（厂商自带 GCC 10.3），不关掉会因 warning 直接编译失败 |

### 内核：有意关闭 CONFIG_WERROR

vendor 内核自带 `CONFIG_WERROR=y`，它会把每一个 GCC 警告都变成硬错误
（`Makefile`：`KBUILD_CFLAGS-$(CONFIG_WERROR) += -Werror`）。而 GCC 13 比厂商当年
验证时用的编译器更新，会对 Rockchip 那些树外驱动报出大量警告，例如：

    drivers/net/wireless/rockchip_wlan/aic8800_usb/aic8800_fdrv/aicwf_wext_linux.c:403:25:
      error: the comparison will always evaluate as true for the address of
      bssid will never be NULL [-Werror=address]
    cc1: all warnings being treated as errors

因此设备配置里设为 `# CONFIG_WERROR is not set`。这只是把警告降回警告（顶层
`Makefile` 里无条件的 `-Werror=implicit-function-declaration`、
`-Werror=return-type` 等检查依然有效）。

### U-Boot：两个 vendor 工具链的坑

1. 厂商的 `make.sh` 会自己拼上 `_defconfig` 后缀（它执行的是
   `make configs/${ARG_BOARD}_defconfig`），所以它要的是**不带后缀的裸板名**。设备包
   因此把 `uboot_helper` 返回的后缀剥掉（`uboot_cfg="${uboot_cfg%_defconfig}"`），
   同时保持 `uboot_helper` 与主线条目一致。野火 SDK 传的也是裸板名
   （`RK_UBOOT_CFG="rk3568-pcie-ep"`）。

2. U-Boot 2017.09 里 `-Werror` 是硬编码的（`Makefile`：
   `KBUILD_CFLAGS += -fshort-wchar -Werror`）。GCC 13 比厂商验证过的版本新，会对老代码
   报出 `-Waddress` 与 `-Wmaybe-uninitialized`，进而中断编译。设备包导出了
   `KCFLAGS="-Wno-error"`；u-boot 的 Makefile 最后才追加 KCFLAGS，所以它能覆盖那个
   硬编码的 `-Werror`，而显式的 `-Werror=implicit-function-declaration`、
   `-Werror=return-type`、`-Werror=date-time` 检查仍然生效。

### 图形栈：libmali 是 GLES-only，桌面 GL 不可用

本设备 `OPENGL_SUPPORT=no`、`OPENGLES=libmali`（Mali-G610 闭源 blob 只提供 EGL/GLES，
没有桌面 GL，sysroot 里也没有 `libGL.so` 与 `GL/gl.h`）。两类坑由此而来：

* **硬编码的设备白名单**：部分包的开关是按设备名列举的（如 RetroArch/flycast 的 GLES3
  白名单），新设备不会自动继承，需手动加入 `RK3588`。
* **核心自身 Makefile 的 GL/GLES 选择方式不一致**，本树遇到过两种写法，都已修：
  * `parallel_n64`：GLES 宏**嵌套**在 `ifeq ($(HAVE_OPENGL),1)` 之内，而本平台只会传
    `HAVE_OPENGL=0`，于是宏一个都没定义，代码去 `#include <GL/gl.h>` 而失败。同家族的
    `mupen64plus_next` 写成顶层 `else ifeq ($(GLES),1)`，只传 `GLES=1` 即可。修法是
    GLES-only 平台传 `HAVE_OPENGL=1` + `GLES=1`。
  * `yabasanshiro`：默认走桌面 GL（`-D_OGL3_` + `-lGL`），只有 `FORCE_GLES=1` 才切到
    `-DHAVE_OPENGLES3` + `-lGLESv2`，而 LibreELEC 原来不传这个变量。修法是 GLES-only
    平台补 `FORCE_GLES=1`。

排查新核心时的经验：遇到 `GL/gl.h: No such file or directory` 或
`GLES2/gl2.h` 找不到，先确认编译命令行里到底有没有 `-DHAVE_OPENGLES2`
（`grep -m1 "<pkg>\.o" 日志 | tr ' ' '\n' | grep '^-DHAVE'`），再看该核心 Makefile 里
这个宏被哪个条件门控。

### 构建系统：git 源的网络重试与镜像

本构建机到 GitHub 的连接不稳（直连被阻断，或代理间歇性截断 TLS 流：
`error: RPC failed; curl 56 GnuTLS recv error (-9)` / `fatal: early EOF` /
`fatal: index-pack failed`）。做了两层加固：

1. `scripts/get_git` 原本只跑一次 `git fetch` 就放弃，一次抖动就会让整个 `make image` 中止
   —— 而本源码树里有 195 个包使用 git 源。现在它会在干净的检出上重试，最多 `GIT_RETRIES`
   次（默认 5，可用环境变量覆盖）。
2. 宿主侧（`tools/fix-build-env.sh` 自动完成）：
   * `git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"`
     —— 一次性覆盖 git 源包、git 子模块、CMake `FetchContent`
   * `git config --global http.version HTTP/1.1`（缓解代理下的 HTTP/2 流截断）
   * `~/bin/wget` 包装器（GitHub 走镜像；非 GitHub 主机 `https→http` 兜底）

细节与排查表见 [`tools/NETWORK_BUILD.md`](tools/NETWORK_BUILD.md)。

## 对上游与厂商配置的改动清单

本设备目录除自有文件外，还改动了下列上游/厂商文件，集中记录便于复核与上游合并：

| 位置 | 改动 | 原因 |
| --- | --- | --- |
| `packages/sysutils/busybox/scripts/fs-resize` | 不再假设 `/storage` 是分区 2，改为从挂载设备名推导分区号 | Rockchip `update.img` 布局（`parameter-extboot`）把 uboot/boot/rootfs 定义为分区 1/2/3，`/storage` 在 **p3**；原脚本 `grep '2$'` 取空值 → 静默放弃扩容且已删掉 `.please_resize_me`（永不重试），系统只剩 26 MB `/storage` |
| `projects/Rockchip/devices/RK3588/packages/rk-serial-console/` | **新增包**：在 `/dev/ttyFIQ0` 上直接起一个 root 登录 shell（`ttyFIQ0-console.service`：`ExecStart=-/bin/sh -l` + `StandardInput=tty-force` + `TTYPath=/dev/ttyFIQ0`），并在 `options` 里 `ADDITIONAL_PACKAGES` 引入 | vendor 内核把 UART2 交给 fiq_debugger（只有 `/dev/ttyFIQ0`，没有 ttyS2），而 LibreELEC 有意删除了所有 getty 单元、镜像里也没有 agetty（util-linux 目标配置未开 `--enable-agetty`，且 `--disable-all-programs` 白名单里没有它）；串口是开机阶段唯一的调试通道。不想要就把它从 `ADDITIONAL_PACKAGES` 去掉 |
| `linux/lubancat-6.1/linux.aarch64.conf` | 补 `CONFIG_SQUASHFS_ZSTD=y` | 本项目用 zstd 打 SYSTEM squashfs，缺它挂不上 rootfs（详见下文表格） |
| 同上 | `# CONFIG_WERROR is not set` | GCC 13 编译厂商 6.1 代码必需 |
| `patches/linux/vendor/rockchip-9000-rk3588-lubancat-5-enable-hdmi0-vp0.patch` | 打开 `rk3588-lubancat-5.dts` 的 HDMI0/VP0 显示路由 | 厂商板级 dts 把所有显示 route include 注释掉了 → vop2 注册 0 个 CRTC → DRM 绑定失败 → HDMI 无信号 |
| `projects/Rockchip/devices/RK3588/options` | `EXTRA_CMDLINE` 改为 `console=tty1 console=ttyFIQ0 …` | 内核取**最后一个** `console=` 作 `/dev/console`；串口要能登录必须让它排在最后 |

| `patches/linux/vendor/rockchip-9001-rk3588-lubancat-5iob-enable-hdmi0-vp0.patch` | 打开 5IO（`rk3588-lubancat-5iob.dts`，`rk3588-lubancat-5io.dts` 只是它的壳）的 HDMI0/VP0 显示路由 | 与 9000 同因：厂商板级 dts 注释掉了全部显示 include，vop2 注册 0 个 CRTC → HDMI 无信号 |
| `patches/linux/vendor/rockchip-9002-rk3588s-lubancat-4-enable-hdmi0-vp0.patch` | 打开鲁班猫4（RK3588S，`rk3588s-lubancat-4.dts`）的 HDMI0/VP0 显示路由 | 同上 |
| `packages/u-boot/package.mk` | DDR blob 按 `UBOOT_SYSTEM` 选择（5 系 2112MHz，鲁班猫4 先用厂商默认 1848MHz，`DDR_FREQ` 可覆盖）；设备 fragment 合并改为幂等（`…_defconfig.lakka-pristine` 副本） | 多板共用同一棵 u-boot 源码树与同一份 defconfig，单向 sed / 盲目 append 都会串板或重复 |
| `projects/Rockchip/tools/build-board.sh` | **新增**：按芯片 + 板卡构建镜像（菜单/参数），板卡清单从 `scripts/uboot_helper` 现取，含产物断言 | 多板卡后手工记 `UBOOT_SYSTEM`/清 u-boot 树/查产物极易出错 |

> 注：`rk-serial-console` 提供的是**免密 root** 串口 shell（物理接触 UART 即等于 root），定位阶段方便，正式发布前可按需移除。
