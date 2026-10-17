# Lakka RK3588（野火鲁班猫 5）编译操作手册

> 目标机：`dev@10.255.200.141`，源码 `/home/dev/Lakka-LibreELEC`  
> 当前分支：`lubancat`（基于 `Lakka-v6.1`，改动已全部应用）  
> 野火 SDK（只读参考、素材来源）：`/home/dev/LubanCat_SDK`  
> 本文所有路径/变量/版本号均来自实际验证，可直接照做。

---

## 一、这次移植改了什么（先有个全局认识）

**新增目录/文件**（`projects/Rockchip/devices/RK3588/`）

```
options                                  设备参数（CPU/内核/GPU/cmdline）
linux/lubancat-6.1/linux.aarch64.conf    内核配置基线（取自 SDK 的 lubancat_linux_rk3588_defconfig）
config/kernel-firmware-any.dat           固件白名单（rockchip/* 等）
bootloader/config                        U-Boot 配置片段（强制 SPL 从 8MiB 裸扇区读 U-Boot）
README.md                                板名、构建命令、移植说明
packages/u-boot/package.mk               覆盖共享 u-boot 包：用野火 2017.09 + 其 make.sh 打 FIT 链
packages/rkbin/package.mk                覆盖共享 rkbin 包：用 LubanCat/rkbin
packages/libmali/package.mk              覆盖共享 libmali 包：Mali-G610 gbm blob + 固件 + GL 头文件
```

**修改**（14 处）

| 文件                                                               | 改动                                                                                                     |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `scripts/uboot_helper`                                           | 新增 `'RK3588'` 段：`lubancat-5`、`lubancat-5io` 的 dtb 与 u-boot defconfig                                   |
| `config/arch.aarch64`                                            | 补 `cortex-a76.cortex-a55`（不加会导致 `-march=` 为空、编译失败）                                                     |
| `packages/linux/package.mk`                                      | 新增 `lubancat-6.1)` 内核分支（野火 vendor 6.1）                                                                 |
| `projects/Rockchip/bootloader/install`                           | 新增 RK3588 分支：把 loader 与 `uboot.img` 摆到 32KiB / 8MiB                                                    |
| `projects/Rockchip/patches/linux/*.patch` → `.../linux/default/` | 57 个**主线**内核补丁归入 `default/`（vendor 内核不再套用）                                                             |
| `packages/devel/glibc/package.mk`                                | 加 `elif [ "${LINUX}" = "lubancat-6.1" ]` 分支，把 `--enable-kernel` 从 6.6.0 降到 6.1.0（适配 vendor 6.1 内核头文件）  |
| `scripts/get_git`                                                | 网络 git 操作加**带清理的重试循环**（默认 5 次，`GIT_RETRIES` 可覆盖）：本机代理会间歇截断 TLS 流导致 `early EOF`，全树 195 个 git 源包否则极易整批失败 |
| `packages/lakka/retroarch_base/retroarch/package.mk`               | GLES3 开关是**硬编码设备白名单**（RPi4/5、RK3288、RK3326、RK3399、Generic、Odin）→ 把 `RK3588` 加进去，否则 configure 只给 `--enable-opengles`、没有 `--enable-opengles3/_3_1`，G610 的 GLES3 与 GL 视频驱动会被关掉 |
| `packages/lakka/libretro_cores/flycast/package.mk`                | 同一份 GLES3 白名单 → 加 `RK3588`（否则 flycast 走 GLES2 分支）                                                                                    |
| `packages/lakka/libretro_cores/amiarcadia/package.mk`              | 源 URL 从不可达的 `git.libretro.com` 换成 GitHub 镜像 `warmenhoven/amiarcadia`（**同一锁定 commit，内容逐字节相同**）；`PKG_VERSION` 不变 |
| `packages/lakka/libretro_cores/yabasanshiro/package.mk`   | 该核心 `Makefile.common` 默认走桌面 GL（`-D_OGL3_` + `-lGL`），只有 `FORCE_GLES=1` 才切到 `-D_HAVE_OPENGLES3` + `-lGLESv2`；LibreELEC 原来只把 `${OPENGLES}` 加进依赖、不传该变量 → GLES-only 平台补 `FORCE_GLES=1` |
| `packages/lakka/libretro_cores/parallel_n64/package.mk`     | 该核心的 `Makefile.common` 把 GLES 宏**嵌套**在 `ifeq ($(HAVE_OPENGL),1)` 里，而 LibreELEC 在「只有 GLES」的平台只传 `HAVE_OPENGL=0` → 一个 GL 宏都不定义 → `#include <GL/gl.h>` 失败。改为在 GLES-only 平台传 `HAVE_OPENGL=1` + `GLES=1`（桌面 GL 平台行为不变） |
| `packages/lakka/lakka_depends/SDL/package.mk`                     | host 侧不再继承 target 的 `--with-alsa-{inc-,}prefix=${SYSROOT_PREFIX}/...`（否则 x86_64 host 编译器会包含 aarch64 glibc 头，报 `unknown type name '__Float32x4_t'`） |
| `build_all.sh` / `pkg_all.sh`                                    | 追加 `Rockchip\|RK3588\|aarch64\|image`                                                                  |

**版本钉子**（都取自 SDK 实际使用/发布的版本）

| 组件      | 版本                                  | 上游仓库                                       |
| ------- | ----------------------------------- | ------------------------------------------ |
| 内核      | commit `1bc19c5…`（6.1.99）           | `LubanCat/kernel` branch `lbc-develop-6.1` |
| U-Boot  | commit `8f53f80…`（2017.09 vendor）   | `LubanCat/u-boot` branch `main`            |
| rkbin   | commit `58a39b4…`                   | `LubanCat/rkbin` branch `master`           |
| libmali | `1.9-1`（valhall-g610-g24p0 **gbm**） | `tsukumijima/libmali-rockchip` release     |

---

## 二、环境依赖

### 2.1 硬件/系统现状（本机实测）

| 项    | 值                              | 说明                             |
| ---- | ------------------------------ | ------------------------------ |
| CPU  | 4 核                            | 全量构建很慢，见 §6.1                  |
| 内存   | 15 GiB（当前可用约 6.5 GiB）          | 紧，失败时降 `THREADCOUNT`           |
| Swap | 3.9 GiB（已用 1.6 GiB）            | 建议保持 ≥4 GiB                    |
| 磁盘   | `/home/dev` 余约 125 GiB（67% 已用） | 构建需 40–60 GiB，够；**不用清理 SDK**   |
| 系统   | Ubuntu x86_64                  | 必须以普通用户构建（root 会被拒绝）           |
| sudo | **需要密码**                       | `scripts/checkdeps` 不能自动安装，需手动 |

### 2.2 必须的宿主工具（已全部就绪，仅作核对）

```bash
for c in dtc python2 python3 qemu-x86_64 rsync wget curl bc gcc g++ make patch git; do
  printf "%-14s %s\n" "$c" "$(command -v $c || echo MISSING)"
done
```

- `dtc`、`python2`：野火 U-Boot 的 `make.sh`/`fit.sh` 打包 FIT 时必需
- **`zstd`（含 `zstdcat`）**：解压 `.tar.zst` 源码包必需（`scripts/extract` 调 `zstdcat`）。本机**原本没有**，导致 `zstd-1.5.5.tar.zst` 解包失败，已用下面的借用方案补齐
- **`git` 走 HTTPS 的稳定性**：本机在代理后面，GitHub 的 TLS 流会被间歇截断（`curl 56 GnuTLS recv error (-9)`）。已设 `git config --global http.version HTTP/1.1`，并在 `scripts/get_git` 里加了重试；两者都不生效时可 `git config --global --unset http.version` 回退
- **`yapp` 与 `Parse::Yapp`（samba 必需）**：samba 自带的 `pidl`（Perl 写的 NDR/RPC 生成器）在 `pidl/wscript:30` 硬性要求 `yapp` 程序：
  ```python
  if not conf.find_program('yapp', var='YAPP'):
      raise Errors.WafError('yapp not found')
  ```
  `--without-ad-dc` / `--without-ads` 都绕不过去。宿主原本**没有**真模块，早期为过 `checkdeps` 写过一个 57 字节的假 `Parse/Yapp/Driver.pm` —— 它让模块探测（`perl -MParse::Yapp::Driver`）误判通过，却提供不了 `yapp` 可执行文件，于是 samba 在 configure 阶段报 `yapp not found` 而失败。**正确做法是从 Ubuntu pool 解包真包**（见下面 §2.2.1）。
- **`JSON`**：同样换成 Ubuntu pool 里的真 `libjson-perl`（4.10），不再是包装 `JSON::PP` 的自制垫片。
- **`rdfind`**：仅 `scripts/checkdeps` 声明、构建流程**从不调用**（全树 grep 已确认）。Ubuntu pool 里的 rdfind 二进制都链接 `libnettle.so.8`，而本机只有 `libnettle.so.7` → 装了反而会在被调用时报动态库错误，因此保留一个 `exit 0` 的占位脚本（比装一个跑不起来的真二进制更安全）。
- **`wget` 包装器**（`~/bin/wget`）：HTTPS 失败时自动改用同一 URL 的 HTTP 重试 —— 部分站点经代理 TLS 不通但 HTTP 正常（如 `www.kernel.org`）。源码包由 `PKG_SHA256` 校验，安全性不受影响；触发记录在 `/tmp/wget-fallback.log`

#### 2.2.1 无 sudo 时用「Ubuntu pool deb 解包」补齐宿主依赖（首选手段）

不需要 root、不需要 PPA、不污染系统 —— `dpkg-deb -x` 只解包到临时目录，再挑文件放进 `~/bin` 与 `~/perl5`：

```bash
mkdir -p ~/bin ~/perl5
# samba 的 pidl 需要 yapp + Parse::Yapp（本次真实故障的修复）
curl -sL -o /tmp/libparse-yapp-perl.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libp/libparse-yapp-perl/libparse-yapp-perl_1.21-2_all.deb
rm -rf /tmp/yapp-x && mkdir -p /tmp/yapp-x && dpkg-deb -x /tmp/libparse-yapp-perl.deb /tmp/yapp-x
cp -a /tmp/yapp-x/usr/share/perl5/. "$HOME/perl5/"      # Parse/Yapp*.pm → PERL5LIB
install -Dm755 /tmp/yapp-x/usr/bin/yapp "$HOME/bin/yapp" # yapp → PATH

# 真 JSON（替代自制垫片）
curl -sL -o /tmp/libjson-perl.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libj/libjson-perl/libjson-perl_4.10000-1_all.deb
rm -rf /tmp/json-x && mkdir -p /tmp/json-x && dpkg-deb -x /tmp/libjson-perl.deb /tmp/json-x
cp -a /tmp/json-x/usr/share/perl5/. "$HOME/perl5/"

# 验证（版本应为 1.21 / 4.10，且 yapp 能打印用法）
export PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5"
perl -MParse::Yapp -e 'print $Parse::Yapp::VERSION,"\n"'
perl -MJSON -e 'print $JSON::VERSION,"\n"'
yapp 2>&1 | head -3
```

> **为什么解包 deb 是首选**：`archive.ubuntu.com` 与 `mirrors.aliyun.com` 在本机都稳定可达（`www.kernel.org` 的 HTTPS 反而不通）；pool 里的包是发行版构建的正式产物，比"自制垫片"可靠得多。
> **教训（务必记住）**：**不要为了过 `checkdeps` 而写假模块/假脚本**。本次假 `Parse::Yapp::Driver` 让模块探测通过，却在 samba 的 `find_program('yapp')` 处炸掉，排查成本远高于当初写脚本省下的时间。宿主依赖优先级：**官方包解包 > 源码编译 > 借用现成二进制 > 绝不写假货**。
> **选包注意架构与动态库**：`amd64` 二进制要确认 `ldd` 依赖在本机存在（本机 `libnettle.so.7` ≠ pool 新版的 `.8`）；纯 Perl 的 `_all.deb` 无此问题。
- `qemu-x86_64`：仅当宿主不是 x86_64 时才需要（本机是 x86_64，实际用不到它跑 rkbin 工具）
- 若缺工具：`sudo apt-get install device-tree-compiler python2 qemu-user-static rsync bc zstd`
- 也可以通过 `./scripts/checkdeps` 让它列出缺失项（但它要 sudo 自动装，本机需手动）

**无 sudo 时补齐 zstd 的办法**（已执行，脚本 `/tmp/fix_host_zstd.sh`）：

```bash
mkdir -p ~/bin
for n in zstd zstdcat unzstd; do ln -sf /home/dev/anaconda3/bin/zstd ~/bin/$n; done
grep -qF 'HOME/bin' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/bin:$PATH"          # 非交互 ssh 跑构建时必须显式带上
zstdcat --version                      # 验证
```

> zstd 是“多调用名”程序：同一个二进制按 `argv[0]` 决定行为，所以一个软链即可同时提供 `zstd`/`zstdcat`/`unzstd`。  
> 用它启动构建时要写成 `nohup env PATH="$HOME/bin:$PATH" PROJECT=… ./scripts/build linux &`，否则非交互 shell 不读 `~/.bashrc`、PATH 里仍找不到 zstd。

---

## 三、编译前准备

### 3.1 切到移植分支

```bash
cd /home/dev/Lakka-LibreELEC
git status                    # 确认干净
git branch --show-current     # 应为 lubancat
git log --oneline -1
```

若不在该分支：`git switch lubancat`（回到原状态：`git switch Lakka-v6.1`）。

### 3.2 源码缓存（**关键**，本机网络特殊）

本机外网像走 fake-ip 代理（解析出 `198.18.x.x`），到 GitHub 的 `git fetch` 会 `early EOF` 中断，因此**四个大源码包已预置缓存**，构建时直接命中、不联网：

```bash
ls -lh sources/linux/*.tar.xz sources/u-boot/*.tar.xz sources/rkbin/*.tar.xz sources/libmali/*.tar.xz
```

| 包       | 缓存文件                                    | 大小     | 生成方式                              |
| ------- | --------------------------------------- | ------ | --------------------------------- |
| linux   | `sources/linux/linux-1bc19c52….tar.xz`  | 184 MB | 从 SDK 内核树 `git archive` 导出        |
| u-boot  | `sources/u-boot/u-boot-8f53f80….tar.xz` | 14 MB  | 从 SDK u-boot 树 `git archive` 导出   |
| rkbin   | `sources/rkbin/rkbin-58a39b4….tar.xz`   | 14 MB  | 从 SDK rkbin 树 `git archive` 导出    |
| libmali | `sources/libmali/libmali-1.9-1.tar.xz`  | 16 MB  | 由 `-gbm` deb 重新打包 + SDK 里的 GL 头文件 |

每个包旁边还有两个戳文件：`<file>.url`、`<file>.sha256`（内容必须与 `package.mk` 里的 `PKG_SHA256` 一致，否则会重新下载）。

重新生成缓存的两个脚本（已放在 `/tmp`，建议归档到仓库外保存）：

```bash
/tmp/seed_sources.sh        # 重新生成 linux/u-boot/rkbin 的 tar.xz（从 SDK 树）
/tmp/make_libmali_src.sh    # 重新生成 libmali 的 tar.xz（需要 /tmp/libmali-gbm.deb 存在）
```

### 3.3 环境变量（三层参数）

```bash
export PROJECT=Rockchip
export DEVICE=RK3588
export ARCH=aarch64
export UBOOT_SYSTEM=lubancat-5      # 或 lubancat-5io
export THREADCOUNT=4                # 4 核机器就用 4；内存吃紧降到 2
```

快速自检（不编译，确认参数被正确解析）：

```bash
PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  bash -c '. config/options "" ; echo "LINUX=$LINUX OPENGLES=$OPENGLES"; echo "CFLAGS=$TARGET_CFLAGS"; kernel_config_path'
```

期望输出：`LINUX=lubancat-6.1 OPENGLES=libmali`，`CFLAGS` 含 `-march=armv8-a+crc+crypto -mtune=cortex-a76.cortex-a55`，最后一行指向 `.../devices/RK3588/linux/lubancat-6.1/linux.aarch64.conf`。

---

## 四、编译命令与执行顺序

### 4.1 推荐顺序（分步，失败面小）

```bash
cd /home/dev/Lakka-LibreELEC

# ① 内核（会连带构建 aarch64 工具链，是最耗时的第一步）
PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  ./scripts/build linux

# ② U-Boot（调用野火 make.sh，产出 loader + uboot.img 并拼成 u-boot-rockchip.bin）
PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  ./scripts/build u-boot

# ③ 出镜像（构建其余全部包：RetroArch、SDL、libmali、各 libretro 核心……）
PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  THREADCOUNT=4 make image
```

### 4.2 后台跑（强烈建议，全程数小时）

```bash
cd /home/dev/Lakka-LibreELEC
nohup env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" \
  PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  THREADCOUNT=4 make image > /tmp/rk3588-build.log 2>&1 < /dev/null &

tail -f /tmp/rk3588-build.log          # 实时看
grep -c FAILED /tmp/rk3588-build.log   # 出错计数（正常始终为 0）
```

### 4.3 直接一把梭（等价，但中途出错要重新定位）

```bash
PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 make image
```

`make image` 会自动补齐所有依赖（含内核与 U-Boot）。

### 4.4 其他有用目标

| 命令                                                      | 用途                                        |
| ------------------------------------------------------- | ----------------------------------------- |
| `./scripts/build <pkg>`                                 | 单独构建某包（如 `retroarch`、`libmali`），失败时只重试这一包 |
| `./scripts/build <pkg>:host`                            | 只构建 host 侧                                |
| `./scripts/clean <pkg>`                                 | 清掉某包的构建目录（改配置后重编）                         |
| `rm -rf build.Lakka-RK3588.aarch64`                     | 全清（下次从零开始，工具链也要重编，慎用）                     |
| `./scripts/uboot_helper Rockchip RK3588 lubancat-5 dtb` | 查板卡对应的 dtb / defconfig                    |
| `OFFICIAL=yes ./build_all.sh`                           | 全平台批量构建（含新增的 RK3588 目标）                   |

---

### 4.5 多板卡构建（build-board.sh）

`projects/Rockchip/tools/build-board.sh` 按「芯片 + 板卡」构建镜像；板卡清单从
`scripts/uboot_helper` 现取，**新增板卡甚至新增芯片后脚本都不用改**：

```sh
projects/Rockchip/tools/build-board.sh                      # 菜单（whiptail；无 whiptail 时退化为编号选择）
projects/Rockchip/tools/build-board.sh RK3588 lubancat-4    # 参数直构
projects/Rockchip/tools/build-board.sh --list               # 列出所有 (芯片, 板卡)
```

它做的事：白名单校验 → 磁盘预检 → `./scripts/clean u-boot` → `make image`
（日志 `/tmp/lakka-build-<board>.log`）→ 失败时打印第一处 `FAILED COMMAND`
上下文 → 成功后**自动校验产物**：FAT 里只有该板的 dtb、`extlinux.conf` 的
`FDT` 指向它、dtb 的 `model` 与 `hdmi@fde80000`/`route-hdmi0`、32 KiB / 8 MiB
引导魔数、sha256。逐板跑即可，其它板已构建的镜像不会被删。

#### 多板卡的三条坑

1. **dtb 名写错是静默故障**：`scripts/mkimage` 只在
   `${RELEASE_DIR}/3rdparty/bootloader/${DTB}` 存在时才把它拷进 boot 分区，
   `uboot_helper` 里 dtb 文件名写错**不报错**，只会产出一张没有 dtb 的镜像
   （上电卡死）。build-board.sh 的产物断言就是为此而设。
2. **换板必须清 u-boot 构建树**：厂商 `make.sh` 不做 distclean，同一棵源码树
   换板只跑 `make <board>_defconfig`，会带上上一块板的对象文件。build-board.sh
   默认每板 `./scripts/clean u-boot`（源码包已缓存，重解不联网，1-2 分钟）。
3. **共享 defconfig 的 fragment 合并必须幂等**：`lubancat-5` 与 `lubancat-5-v2`
   共用 `lubancat-5-rk3588-pcie_defconfig`，而 LibreELEC 复用同一棵 u-boot 源码树
   —— 盲目 `cat >>` 会把 fragment 每行写两遍。`packages/u-boot/package.mk`
   现在先存 `…_defconfig.lakka-pristine` 副本、每次从副本恢复再追加。

#### 同一块板的不同硬件版本（如鲁班猫4 的 v0 / v1）怎么切 dtb

厂商对每版 PCB 给一个 dts（`rk3588s-lubancat-4.dts` = v0，`rk3588s-lubancat-4-v1.dts` = V1），
两者**只差两组引脚**：`dsi0_reset`（GPIO0_A31 → GPIO1_A1）与 `tp1_irq`（GPIO3_D20 → GPIO4_A1），
即 **MIPI DSI 屏复位 + 触摸中断**；HDMI/USB/eMMC/网口/mSATA 完全相同。
⇒ **不用 MIPI DSI 屏 + 电容触摸时，v0/v1 用同一张镜像、同一个 dtb 都能正常跑**（已实测 v0 dtb 跑在鲁班猫4 上）。

需要切时的两种方式：

1. **不刷机，30 秒切换（推荐）**：SYSTEM 里带着全部 dtb（`/usr/share/bootloader/`），
   而 `/flash` 就是 boot FAT 分区：
   ```sh
   mount -o remount,rw /flash
   cp /usr/share/bootloader/rk3588s-lubancat-4-v1.dtb /flash/     # 两个 dtb 并存
   sed -i 's|^FDT /rk3588s-lubancat-4.dtb$|FDT /rk3588s-lubancat-4-v1.dtb|' /flash/extlinux/extlinux.conf
   cat /flash/extlinux/extlinux.conf        # 确认 FDT 行
   mount -o remount,ro /flash && reboot
   ```
   切回 v0 把 FDT 行改回去即可（v1 的 dtb 留在 FAT 里不影响）。拔卡到 Windows 上
   用记事本改 `extlinux.conf` 同样可行。**判断依据**：接 MIPI 屏后触摸不动 / 屏不亮
   就换另一个 dtb；`cat /proc/device-tree/model` 显示 `Embedfire LubanCat-4 V1` 即生效。
2. **每版一张镜像（LibreELEC 原生做法）**：`lubancat-4-v1` 已注册进 `scripts/uboot_helper`
   （dtb `rk3588s-lubancat-4-v1.dtb`，defconfig 复用 lubancat-4 的），直接
   `projects/Rockchip/tools/build-board.sh RK3588 lubancat-4-v1` 出专用镜像。

#### DDR blob（全系统一 1848MHz）

`packages/u-boot/package.mk` 把 rkbin `RK3588MINIALL.ini` 里的 DDR blob 统一改成
1848MHz（= rkbin / LubanCat SDK 的默认值），不再按板区分：

| 板卡 | DDR blob |
| --- | --- |
| lubancat-5 / 5-v2 / 5io / 4 / 4-v1 | `rk3588_ddr_lp4_1848MHz_lp5_2400MHz_v1.18.bin` |

实验时不用改代码：`DDR_FREQ=2112 projects/Rockchip/tools/build-board.sh RK3588 lubancat-5`。

#### 每块新板的上机检查清单（串口 1500000 8N1）

1. 看 DDR 打印行（`LPDDR4/LPDDR4X, <频率>MHz`）是否与所选 blob 一致 —— **完全无输出 = loader 没跑**，第一嫌疑是 DDR blob；
2. HDMI 出 Lakka 主界面；关注是否反复闪屏/短时黑屏（对应 `video=HDMI-A-1:1920x1080@60`）；
3. 串口敲回车出 root shell；`cat /proc/device-tree/model` 打印对应型号；
4. `ls /dev/dri/` 有 `card0`；`dmesg | grep -iE 'vop2|rockchip-dw-hdmi|mali'` 无 `No crtc register`；
5. `df -h /storage` 已自动扩容（>26G）；
6. 板卡差异项：鲁班猫4 的 mSATA/AHCI、5IO 的双千兆网口与 SATA、5-V2 的 USB/DSI 复位改动。

## 五、产物与位置

| 产物              | 路径                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------- |
| 最终镜像            | `target/Lakka-RK3588.aarch64-*.img.gz`（解压后 `dd` 到 eMMC/SD）                                                    |
| 内核              | `target/Lakka-RK3588.aarch64-*.kernel`                                                                        |
| 根文件系统           | `target/Lakka-RK3588.aarch64-*.system`                                                                        |
| 引导链中间产物         | `build.Lakka-RK3588.aarch64/build/u-boot-*/`：`uboot.img`、`u-boot.itb`、`rk3588_spl_loader_v*.bin`、`u-boot.cfg` |
| 拼接好的 bootloader | `build.Lakka-RK3588.aarch64/image/system/usr/share/bootloader/u-boot-rockchip.bin`                            |
| 构建目录            | `build.Lakka-RK3588.aarch64/`（源码缓存 `sources/` 在仓库根）                                                           |

**eMMC 上的引导布局**（与野火 SDK 的 `parameter-extboot.txt` 完全一致）


| 偏移                | 内容                                                                          |
| ----------------- | --------------------------------------------------------------------------- |
| 32 KiB（LBA 64）    | SPL loader（`rk3588_spl_loader_v1.18.113.bin`，实测 487872 B）                   |
| 8 MiB（LBA 16384）  | `uboot.img`（FIT：U-Boot + BL31/BL32，4 MiB 对齐）                                |
| 16 MiB（LBA 32768） | BOOT 分区（vfat，`extlinux/extlinux.conf` + `KERNEL` + `rk3588-lubancat-5.dtb`） |

> **容器内偏移 vs 磁盘偏移（容易搞混）**：`u-boot-rockchip.bin` 这个「容器」文件里，loader 在偏移 0、`uboot.img` 在偏移 16320 扇区（= 8 MiB − 32 KiB）；而容器本身由 `projects/Rockchip/bootloader/mkimage` 用 `dd bs=32k seek=1` 写到磁盘 **32 KiB** 处 —— 两者相加才得到上表的 32 KiB / 8 MiB。实测校验：容器偏移 0 处是 `4c 44 52 20`（"LDR " loader 头），偏移 8355840 处是 `d0 0d fe ed`（FIT 魔数）；文件总长 16744448 B = 8 MiB + (8 MiB − 32 KiB)。

启动由 U-Boot 的 `distro_bootcmd` 完成（已确认 `CONFIG_FS_FAT`/`CMD_FAT`/`CMD_EXT4`/`DISTRO_DEFAULTS` 均开启）。

---

## 六、常见错误与排查


### 6.1 编译期

| 现象                                                                                                                                                                                                                                                                 | 原因                                                                                                                                                                                             | 处理                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET <pkg> (git)` → `GIT FETCH` 失败：`error: RPC failed; curl 56 GnuTLS recv error (-9): Error decoding the received TLS packet` + `fatal: early EOF` / `index-pack failed` → `FAILURE: scripts/install <pkg>:target has failed!`（本次真实故障：`glsl_shaders`，`[011/432]`） | 本机在代理后面，GitHub 的 TLS 流被**间歇性**截断（同一条命令手动重跑往往就成功）；而 `scripts/get_git:47` 原来是裸的 `git fetch`、**一次失败即整包放弃**，并行构建下一处抖动就中止整个 `make image`。全树 195 个包走 git 源、github 相关 737 个 → 逐个预置源码不现实，必须做通用重试       | ① （已改）`scripts/get_git` 重试循环：失败后 `rm -rf` 半成品仓库、重新 init/fetch/checkout/submodule，最多 `GIT_RETRIES`（默认 5）次，间隔 15 s；② （已设）`git config --global http.version HTTP/1.1`，缓解代理下的 HTTP/2 流截断；③ 单包可单独验证：`env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 ./scripts/get <pkg>`（实测 `glsl_shaders` 25 s 完成、产出 45 MB tarball）                                                                                                                                                                                                                                                  |
| `git fetch` → `fatal: the remote end hung up unexpectedly / early EOF / index-pack failed`                                                                                                                                                                         | 本机到 GitHub 极慢/不稳（fake-ip 代理），git 无断点续传                                                                                                                                                         | 用 §3.2 的缓存；或改用 `git archive` 本地生成（`/tmp/seed_sources.sh`）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `Cannot get <pkg> sources : ...` + `ERROR 404` / `Unable to establish SSL connection`                                                                                                                                                                              | 上游 URL 是重定向服务（`ftpmirror.gnu.org`）或镜像 404                                                                                                                                                      | 分两类处理：① **上游是重定向服务**（`ftpmirror.gnu.org`）→ 全树 19 处已改成规范地址 `ftp.gnu.org/gnu/`；② **代理过不去 TLS 的站点** —— 本次真实故障：`https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.69.tar.xz` 报 `Unable to establish SSL connection`，而 LibreELEC 兜底镜像 `sources.libreelec.tv/mirror/libcap/...` 返回 `404 Not Found` → `FAILURE: scripts/build libcap:host has failed!`。同一 URL 用 **HTTP 就正常**（实测 189200 B 完整下载）。已装 `~/bin/wget` 包装器：**HTTPS 失败时自动用同一 URL 的 HTTP 重试**（源码包由 `PKG_SHA256` 校验，实测 http 取回的 libcap SHA256 与 `PKG_SHA256` 逐字节一致），触发记录在 `/tmp/wget-fallback.log`。彻底兜底：手动下到 `sources/<pkg>/` 并写 `.url`/`.sha256` 戳                       |
| `WARNING Incorrect checksum calculated on downloaded file: got <A> wanted <B>` → `Cannot get <pkg> sources` → `FAILURE: ... <pkg> ... has failed!`（本次真实故障：`wireguard-tools` 的 `git.zx2c4.com/.../snapshot/...tar.xz`，`[166/432]`）                                  | 这类 `*/snapshot/*` URL 是 **gitweb/cgit 在线生成**的归档；上游 cgit 一升级或换参数，**字节就变**（tar 元数据/压缩差异），recipe 里钉的 `PKG_SHA256` 随即过期。实测该包：两次独立下载字节完全一致（100340 B）、`xz -t` 通过、169 个条目、顶层目录正确 → **不是截断，是上游变了**     | ① **先判性质**：重复下载两次比对 sha256，并用 `xz -t` / `tar -tJf \| wc -l` 验证归档完整，区分「上游变了」与「下载被截断」；② **再交叉验证**：用同 tag 的独立来源逐文件比对（本次 `wireguard-tools` 与 GitHub `v1.0.20250521` 的 **122 个文件逐字节相同**，版本串 `1.0.20250521` 一致）→ 确认无误后才更新 `PKG_SHA256`；③ 预置缓存需**三个文件齐全**：`sources/<pkg>/<file>` + `<file>.sha256`（内容必须等于 `PKG_SHA256`）+ `<file>.url`，否则 `get_archive` 仍会重新下载；④ **上游自带逃逸开关** `CHANGE_HASH=yes`：会让 `get_archive` 在哈希不符时自动把新值写回 `package.mk` —— 用前必须自己确认内容，否则等于放弃完整性校验；⑤ 批量体检：`/tmp/probe_snapshot_hashes.py` 一次性列出全树所有 `*/snapshot/*` 源的 OK / MISMATCH / DL-FAIL（本次 12 个：6 个 OK、3 个 MISMATCH、3 个 DL-FAIL 中 `connman`/`configtools` 实际已缓存成功）。**更正一处早先的判断**：当时说「3 个 MISMATCH 都不在构建计划内」是错的 —— `edid-decode` 其实**在**计划内（由无条件进入镜像的 `debug` 元包拉入，见 §11.3），只是它的源码早已缓存成功（`sources/edid-decode/edid-decode-9ba4e90….tar.gz`）、`build_target` stamp 也已生成，所以没有触发失败；`/tmp/edid-decode` 那类判断不能只看当时截断的日志 |
| `scripts/extract: line NN: zstdcat: command not found` + `tar: This does not look like a tar archive` + `FAILURE: scripts/unpack zstd during unpack`                                                                                                               | 宿主没装 `zstd`，`.tar.zst` 解不开（本次真实故障）                                                                                                                                                             | 见 §2.2 的借用方案或 `sudo apt-get install -y zstd`；修好后重跑同一条构建命令即可（失败包没有 stamp，会重新解包）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `configure: error: cannot compute suffix of object files: cannot compile`（glibc 阶段）+ `config.log` 里 `cc1: error: unknown value 'cortex-a76.cortex-a53' for '-mtune'`                                                                                               | `TARGET_CPU` 值不符硬件/GCC 支持：RK3588 是 **4×A76 + 4×A55**，GCC 13 只认 `cortex-a76.cortex-a55`（无 `A76.A53`）                                                                                            | 设备 options 用 `TARGET_CPU="cortex-a76.cortex-a55"`，并确保 `config/arch.aarch64` 的 case 列表含该值；改完 `./scripts/clean glibc` 后重跑。验证：`toolchain/bin/aarch64-libreelec-linux-gnu-gcc -march=armv8-a+crc+crypto -mtune=cortex-a76.cortex-a55 -c t.c`                                                                                                                                                                                                                                                                                                                                                                                                          |
| `configure: error: *** The available kernel headers are older than the requested compatible kernel version`（glibc 阶段，日志有 `checking for kernel header at least 6.6.0... too old!`）                                                                                  | `packages/devel/glibc/package.mk` 默认 `--enable-kernel=6.6.0`（适配 Lakka 主线内核），而 vendor 内核头文件只有 6.1.99                                                                                            | 已在 `glibc/package.mk` 加 `elif [ "${LINUX}" = "lubancat-6.1" ]` 分支，把 `--enable-kernel` 降到 `6.1.0`；清 glibc 后重跑。验证：configure 行出现 `--enable-kernel=6.1.0` 且紧接 `checking for kernel header at least 6.1.0... ok`                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| 内核 `make_target` 阶段：`drivers/net/wireless/rockchip_wlan/aic8800_usb/.../aicwf_wext_linux.c:403: ... [-Werror=address]` + `cc1: all warnings being treated as errors`                                                                                               | vendor 内核 defconfig 里 **`CONFIG_WERROR=y`** → 内核 `Makefile:868 KBUILD_CFLAGS-$(CONFIG_WERROR) += -Werror`；GCC 13 对老 vendor 驱动报新警告（`&scan_re->bss->bssid[0]` 恒真），warning 变致命错误，整个 `drivers/` 中断 | 把设备 conf 里 `CONFIG_WERROR=y` 改成 `# CONFIG_WERROR is not set`（`pre_make_target()` 每次都会重新把 conf 拷成 `.config`，**改完直接重跑即可，不需要 `clean`**）。验证：`grep CONFIG_WERROR <conf>`；重跑后 `grep -c FAILED` 为 0 且 `arch/arm64/boot/Image` 产出                                                                                                                                                                                                                                                                                                                                                                                                                         |
| u-boot 阶段 `ERROR: No configs/lubancat-5-rk3588-pcie_defconfig_defconfig`（后面跟一长串 `configs/*.defconfig` 列表）                                                                                                                                                          | 野火 `make.sh` **自己会拼 `_defconfig`**（第 240/254 行 `configs/${ARG_BOARD}_defconfig`），期望的是**不带后缀的裸板名**（用法示例：`./make.sh evb-rk3399`）；而 `uboot_helper` 的 `config` 字段按仓库惯例给的是完整文件名                     | 已在设备包 `packages/u-boot/package.mk` 加 `uboot_cfg="${uboot_cfg%_defconfig}"` 剥掉后缀；`uboot_helper` 仍返回完整名（主线包是按 `configs/<config>` 与 `make <config>` 用的）。对照 SDK：`RK_UBOOT_CFG="rk3568-pcie-ep"`，同样不带后缀                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| u-boot 阶段 `error: ... [-Werror=address]` / `[-Werror=maybe-uninitialized]` + `Error 1`（如 `cmd/dtfile.c:116`、`common/edid.c:2934`）                                                                                                                                  | U-Boot 2017.09 的 `Makefile:370` 是**硬编码**的 `KBUILD_CFLAGS += -fshort-wchar -Werror`；GCC 13 比厂商当年验证的编译器新，老代码的警告直接变致命错误                                                                           | 设备包已 `export KCFLAGS="-Wno-error"`（`Makefile:632` 的 `KBUILD_CFLAGS += $(KCFLAGS)` 追加在 `-Werror` 之后，故可覆盖），显式的 `-Werror=implicit-function-declaration` / `-Werror=return-type` / `-Werror=date-time` 仍生效                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `make image` 阶段 `FAILED COMMAND: ${SCRIPTS}/checkdeps`，输出 `**** The following packages were not installed correctly ****` + `perl::JSON provided by libjson-perl` / `perl::Parse::Yapp::Driver ...` / `rdfind provided by rdfind`                                  | `scripts/image:22` **无条件**调用 `checkdeps`；checkdeps 用 `command -v <tool>` / `test -f <file>` / `perl -M<mod> -e exit` 三种方式判定，缺任一项就 `exit 1`（本机 `sudo` 需密码，无法自动安装）                               | **按 §2.2.1 装真包**（`libparse-yapp-perl` 提供 `Parse::Yapp` + `yapp`；`libjson-perl` 提供 `JSON`）到 `~/perl5` 与 `~/bin`；只有 `rdfind` 保留 `exit 0` 占位脚本（构建流程**从不调用**它，且 pool 里的二进制依赖 `libnettle.so.8`、本机只有 `.7`）。⚠️ **早期用假垫片凑 `Parse::Yapp::Driver` 是错误做法** —— 它骗过 checkdeps 与 samba 的模块探测，却让 samba 在 `find_program('yapp')` 处失败（见 §6.1 对应行）。别忘了把 `~/bin`、`~/perl5` 写进 `~/.bashrc`。跑 `make image` 时必须带 `env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB"`                                                                                                                                                                                                                                                                                                                                                                                            |
| samba `configure` 阶段 `Checking for program 'yapp' : not found` + `yapp not found` → `FAILURE: scripts/build samba:target during configure_target`（本次真实故障，`[209/432]`） | samba 自带的 `pidl`（Perl 写的 NDR/RPC 生成器）在 **`pidl/wscript:30`** 硬性要求 `yapp` 程序；而宿主只有当初为过 `checkdeps` 写的 **57 字节假模块** `~/perl5/Parse/Yapp/Driver.pm` —— 模块探测通过、`yapp` 可执行文件却不存在，waf 随即 `raise WafError`。`--without-ad-dc` / `--without-ads` 绕不过去 | 见 **§2.2.1**：从 Ubuntu pool 解包 `libparse-yapp-perl` 装真模块 + `yapp`。验证：configure 行变为 `Checking for program 'yapp' : /home/dev/bin/yapp`，随后 `'install' finished successfully` 且 `smbd`/`nmbd` 产出。**核心教训：绝不用假模块/假脚本凑依赖** |
| RetroArch `configure` 阶段 `Checking presence of package gbm >= 9.0 ... no` → `Error: GBM is disabled and forced to build with KMS support.`（本次真实故障，`[229/432]`） | `gbm.pc` **全树只有 mesa 提供**，而本设备用 libmali blob 替代 mesa（`OPENGLES=libmali`、`GRAPHIC_DRIVERS=mali`）不构建 mesa → sysroot 里 `libgbm.so`/`libgbm.so.1` 已有（libmali 包装器提供）却**没有 pkg-config 元数据**；RetroArch 默认 `--enable-kms`（只有 RPi/L4T 才 disable-kms），KMS 后端强制要 gbm | 已在设备 libmali 包里生成 `gbm.pc` / `egl.pc` / `glesv2.pc`（版本对齐本树 mesa `26.0.3`，`libdir=${prefix}/lib` 与实际安装位置一致）。验证：configure 行变为 `Checking presence of package gbm >= 9.0 ... 26.0.3` |
| RetroArch `make_target` 阶段 `gfx/drivers_context/drm_ctx.c:36:10: fatal error: gbm.h: No such file or directory`（紧接着上一条） | 同上：mesa 不构建 → 没人安装 `gbm.h` 头文件；设备 libmali 只带了 Khronos 的 EGL/GLES/KHR 头 | 从 Ubuntu pool 的 **`libgbm-dev_26.0.3-1ubuntu1_arm64.deb`**（与本树 mesa 版本一致、MIT 许可、只依赖 `<stddef.h>/<stdint.h>`）取 `gbm.h`，放进设备包 `packages/libmali/gbm.h`（随仓库提交、可审阅），并在 `makeinstall_target()` 里装到 `${SYSROOT_PREFIX}/usr/include/`。验证：`ls sysroot/usr/include/gbm.h`；重编后日志中 `gbm.h: No such file` 计数为 0 |
| RetroArch 编译命令行里**没有** `--enable-opengles3`（隐性功能缺失，无报错） | `retroarch/package.mk:46` 的 GLES3 白名单硬编码了 `RPi4/RPi5/RK3288/RK3326/RK3399/Generic/Odin`，**新设备不会自动继承** | 在 `retroarch` 与 `flycast` 的白名单里加 `RK3588`。验证：configure 参数出现 `--enable-opengles3 --enable-opengles3_1`，编译命令行出现 `-DHAVE_OPENGLES3 -DHAVE_EGL -DHAVE_OPENGL_CORE`。**新增设备时务必全树 `grep RK3399` 检查同类白名单**（本树共 3 处，见 §一） |
| RetroArch **链接**阶段大量 `undefined reference to 'gbm_create_device'` / `glDrawElements` / `glCreateProgram` …（**注意链接行里明明有 `-lgbm -lGLESv2 -lEGL`**） | Rockchip libmali blob 的 `mali/*.so.1`（每个 **5928 B**）是**动态符号表为空的 hook 桩**：`readelf -d` 显示 `DT_NEEDED = libmali-hook.so.1 + libmali.so.1`、SONAME 是 `libgbm.so.1`，`nm -D --defined-only` 输出 **0 个符号**；真正的实现是 `libmali.so.1.9.0`（**57 MB**，SONAME `libmali.so.1`，导出 39 个 `gbm_*` 与全部 `gl*`/`egl*`）。官方 `mali.pc` 给的链接配方 `-lmali-hook -Wl,--whole-archive -lmali-hook-injector -Wl,--no-whole-archive -lmali` 里的注入器**并不在 blob 里**，所以常规 `-lgbm` 只能链到空桩 | 设备 libmali 包在 **sysroot**（仅构建期）把裸链接名指向真实现：`for lib in libEGL libGLESv1_CM libGLESv2 libgbm libMaliOpenCL libMaliVulkan; do ln -sfv libmali.so.1.9.0 "${SYSROOT_PREFIX}/usr/lib/${lib}.so"; done`（用**相对**目标，避免依赖 ld 的 sysroot 翻译）；运行时布局保持 Rockchip 原样。验证：`nm -D --defined-only <sysroot>/usr/lib/libgbm.so \| grep gbm_create_device` 有输出；重编后 `grep -c "undefined reference"` 为 0 且产出 15 MB 的 `retroarch` |
| `GET amiarcadia (git)` → `GIT FETCH` 连续失败：`fatal: unable to access 'https://git.libretro.com/libretro/amiarcadia.git/': Failed to connect to git.libretro.com port 443: Connection timed out` → `get_git: amiarcadia failed after 8 attempts` → `[247/432] [FAIL] install amiarcadia:target`（本次真实故障） | 全树 183 个 libretro 核心里**只有 `amiarcadia` 用 `git.libretro.com`**（其余 176 个在 github.com）；该主机（`5.9.231.20`，Hetzner）**TCP 80/443/9418 全部超时**，构建机与另一台完全不同的机器实测一致、而同时 github.com 正常 → **不是代理抖动，是主机整体不可达，重试再多次也没用**（这也是 8 次重试全败的原因） | 已把该核心 `PKG_SITE` 换成 GitHub 镜像 **`https://github.com/warmenhoven/amiarcadia`**：它含**完全相同的锁定 commit `34af1c9eb71c7ef58e7719e67d77881a99874c36`**（提交信息 `libretro: add webOS to CI`），**同 SHA ⇒ 树内容逐字节相同**，且该树有 `Makefile`（`TARGET_NAME := amiarcadia` → `amiarcadia_libretro.so`），与 recipe 的安装路径完全一致。验证：`git fetch --depth 1 origin 34af1c9e…` 成功（EXIT=0）；`./scripts/get amiarcadia` 产出 `<sha>.tar.xz` + `<sha>.tar.xz.gitstamp`。⚠️ **这是 git 源，缓存格式与归档源不同**：只需 `<pkg>-<sha>.tar.xz`（顶层目录同名）+ `<pkg>-<sha>.tar.xz.gitstamp`（内容 `PKG_URL\|PKG_VERSION`），**不要**用 `get_archive` 的 `.url`/`.sha256` 三件套。若 HTTPS 仍抖动，用 `bash /tmp/seed_amiarcadia.sh`（先 10 次 HTTPS，失败自动转 SSH——本机 `ssh -T git@github.com` 已验证可用），或直接取 `https://codeload.github.com/<owner>/<repo>/tar.gz/<sha>`（单次 HTTP GET，实测 60 s 下完 13.9 MB、顶层目录名天然就是 `<repo>-<sha>`，与缓存要求吻合）。本次实际执行时该链路**又全部失败**（`SSL_ERROR_SYSCALL`、`kex_exchange_identification: Connection closed by remote host`、TLS 握手被切），最终改用**离线方案**：复用此前成功抓到并已由 git 校验过 SHA 的那棵树（`/tmp/amtest`，HEAD 正是目标 commit、885 文件）直接生成缓存 —— `/tmp/seed_amiarcadia3.sh`，**完全不需要网络**。验证：`./scripts/get amiarcadia` 秒过（EXIT=0，不联网）、`./scripts/build amiarcadia` → `FAILED: 0`、产出 `install_pkg/amiarcadia-*/usr/lib/libretro/amiarcadia_libretro.so`（861,416 B），全量构建里该任务转为 `[247/432] [DONE] install amiarcadia:target` |
| SDL `make_host` 阶段 `bits/math-vector.h:30:9: error: unknown type name '__Float32x4_t'` + `make[1]: *** [build-deps:699: build/SDL_gamma.lo] Error 1` → `FAILURE: scripts/build SDL:host during make_host`（本次真实故障，`[225/432]`） | **上游遗留 bug**（`packages/lakka/lakka_depends/SDL/package.mk:79` 原样，本地未改过）：`PKG_CONFIGURE_OPTS_HOST="${PKG_CONFIGURE_OPTS_TARGET}"`，而 target 选项里有 `--with-alsa-prefix=${SYSROOT_PREFIX}/usr/lib` 与 `--with-alsa-inc-prefix=${SYSROOT_PREFIX}/usr/include`（**指向 aarch64 目标 sysroot**）。host 构建（`host-gcc`＝x86_64 gcc-9 的包装脚本）因此带上 `-I<toolchain>/aarch64-libreelec-linux-gnu/sysroot/usr/include`，`#include <math.h>` 解析到 aarch64 的 glibc 头，该头用了只有 aarch64 GCC 才有的 `__Float32x4_t`/`__Float64x2_t` → 致命错误 | 已改 `SDL/package.mk`：host 变体从 target 选项里剔除那两条目标 ABI 路径 —— `PKG_CONFIGURE_OPTS_HOST="$(echo ${PKG_CONFIGURE_OPTS_TARGET} \| sed -e 's\|--with-alsa-prefix=[^ ]*\| \|g' -e 's\|--with-alsa-inc-prefix=[^ ]*\| \|g')"`。改完 `./scripts/clean SDL` 再编。**验证两件事**：① 变量级 `HOST 选项里 alsa-prefix 由 2 条变 0 条、TARGET 仍为 2 条`；② 编译行里 `-I` 只剩 `toolchain/include`、`include`、`build/SDL-1.2.15/include` 三条，`__Float32x4_t` 错误计数为 0，`SDL:host` 与 `SDL`（target）均 `FAILED: 0`，产出 `install_pkg/SDL-1.2.15/usr/lib/libSDL-1.2.so.0.11.4`。**通用教训：交叉编译项目里，host 侧构建绝不能继承 target 的 `-I`/`--with-*-prefix` 之类的 ABI 路径**；遇到 "unknown type name '__Float32x4_t'/'__Float64x2_t'" 基本就是这个原因 |
| `GET doublecherrygb (git)` → `gnutls_handshake() failed: The TLS connection was non-properly terminated` / `Failed to connect to github.com port 443: Connection timed out` → `get_git: doublecherrygb failed after 8 attempts` → `[271/345] [FAIL] install doublecherrygb:target`（本次真实故障） | **GitHub 直连整体不通**（不只是抖动）：同时刻 `curl https://github.com` 与 `https://codeload.github.com` 均返回 `000`（5–8 s 快速失败），`git ls-remote` 报 TLS 握手被截断；而**非 GitHub 站点全部正常**（`baidu.com` 200 / 0.05 s、`archive.ubuntu.com` 200 / 0.86 s）→ 是到 GitHub 的链路被阻断，`get_git` 的 8 次重试全败。**注意这时 `~/bin/wget` 的 HTTPS→HTTP 兜底与 `glsl_shaders` 那类"重跑就好"的重试都无效** | **经 GitHub 加速代理走 git 协议灌缓存**（已脚本化）：`gh-proxy.com` 实测支持 git（`git ls-remote https://gh-proxy.com/https://github.com/<owner>/<repo>.git` 正常），于是 `bash /tmp/seed_git_pkg.sh <pkg> <owner/repo> <sha>` —— 它 `git init` + `git remote add origin https://gh-proxy.com/https://github.com/<owner>/<repo>.git` + `git fetch --depth 1 origin <sha>`（**git 会校验每个对象的 SHA，所以即使传输走第三方，内容仍与锁定 commit 逐字节一致**），再按 `get_git` 的布局重打包成 `<pkg>-<sha>.tar.xz`（顶层目录同名）+ `.gitstamp`（内容 `PKG_URL\|PKG_VERSION`，**用原始非代理 URL**）。兜底通道：`ghfast.top`（实测同样支持 git）、jsDelivr。**验证**：`./scripts/get doublecherrygb` → `EXIT=0`、**0.12 s**（纯缓存命中、零网络）；`./scripts/build doublecherrygb` → `EXIT=0`、`FAILED: 0`、产出 `install_pkg/doublecherrygb-*/usr/lib/libretro/DoubleCherryGB_libretro.so`（894,784 B）。⚠️ 注意 `seed_git_pkg.sh` 里 **git 工作树与打包目录必须在不同父目录**，否则 `tar: file changed as we read it`；且脚本**不要**写 `... \| head -3` 之后再 `set -e -o pipefail`（SIGPIPE 会让成功的脚本假报失败） |
| `Cannot get liblcf sources : https://github.com/EasyRPG/liblcf/archive/<sha>.tar.gz` → `~/bin/wget` 里 `URL transformed to HTTPS due to an HSTS policy` → `Unable to establish SSL connection` → LibreELEC 镜像 404 → `FAILURE: scripts/install liblcf:target has failed!`（本次真实故障，`[281/345]`） | **GitHub 托管的是「归档源」而不是 git 源**：走 `get_archive`，缓存需要**三件套**（`<PKG_SOURCE_NAME>` + `.url` + `.sha256`），与 git 源的 `.gitstamp` 完全不同。GitHub 直连被阻断后，`~/bin/wget` 的 HTTPS→HTTP 兜底又被 **HSTS** 挡回 https，镜像也没有该文件 | 用 `bash /tmp/seed_any_pkg.sh liblcf`：经 `gh-proxy.com` 下载归档 → 计算 sha256 → 与 recipe 的 `PKG_SHA256` 比对（`liblcf` 没有该字段，改用**第二个独立镜像 `ghfast.top` 交叉比对，`cmp` 字节一致**）→ 按 `config/functions` 的 `PKG_SOURCE_NAME` 推导规则生成文件名（如 `liblcf-<sha>.tar.gz`、`nss-mdns-0.15.1.tar.gz`）并写 `.url`（内容为**展开后**的 PKG_URL）/ `.sha256`。**验证**：`./scripts/get liblcf` → `rc=0` |
| `yabasanshiro:target during make_target`：`libretro-common/include/glsym/rglgen_headers.h:72:10: fatal error: GL/gl.h: No such file or directory`（`make[1]: *** [Makefile:511: ../vidogl.c.o] Error 1`，本次真实故障，`[337/345]`） | **核心默认走桌面 GL，而本平台只有 GLES**：`yabause/src/libretro/Makefile.common` 的 GL 分支是 `ifeq ($(FORCE_GLES),1)` → `-D_OGLES3_ -DHAVE_OPENGLES -DHAVE_OPENGLES3` + `-lGLESv2`；`else` → `-D_OGL3_` + **`-lGL`**。而 `FORCE_GLES` 默认值就是 0，`platform=arm64` 分支也不置 1，LibreELEC 的 package.mk 又只负责把 `${OPENGLES}` 加进依赖、从不传这个变量 → 编译命令行里只有 `-DHAVE_LIBGL -D_OGL3_`，头文件于是落到 `#else` 去 include `<GL/gl.h>` | 改 `yabasanshiro/package.mk`：`OPENGLES_SUPPORT=yes` 且 `OPENGL_SUPPORT!=yes` 时补 `PKG_MAKE_OPTS_TARGET+=" FORCE_GLES=1"`（`FORCE_GLEW` 默认 0，所以 `-DHAVE_OPENGLES3` 会生效；sysroot 里已有 `GLES3/gl3.h`）。**验证**：编译命令行变为 `-D_OGLES3_ -DHAVE_OPENGLES -DHAVE_OPENGLES3`、`GL/gl.h` 报错归零、产出 `install_pkg/yabasanshiro-*/usr/lib/libretro/yabasanshiro_libretro.so` |
| `parallel_n64:target during make_target`：`libretro-common/include/glsym/rglgen_private_headers.h:67:10: fatal error: GL/gl.h: No such file or directory`（本次真实故障，`[312/345]`） | **核心 Makefile 的 GLES 宏被嵌套在桌面 GL 条件里**：`Makefile.common` 是 `ifeq ($(HAVE_OPENGL),1)` → `ifeq ($(GLES),1)` → `GLFLAGS += -DHAVE_OPENGLES -DHAVE_OPENGLES2 -DDISABLE_3POINT`。而本设备 `OPENGL_SUPPORT=no`（只有 `OPENGLES=libmali`），`parallel_n64/package.mk` 于是只传了 `HAVE_OPENGL=0 FORCE_GLES=1` → 外层条件为假、**一个 GL 宏都没定义** → `rglgen_private_headers.h` 落到 `#else` 分支去 include 桌面 GL 头（libmali 环境里没有，而且全树只有 `gliden64` 和这个头文件需要它）。同家族的 `mupen64plus_next` 之所以没事，是因为它的 `Makefile.common` 写的是顶层 `else ifeq ($(GLES),1)`，只需 `GLES=1` | 改 `parallel_n64/package.mk`：GLES-only 平台传 `HAVE_OPENGL=1`（让嵌套分支生效）并加 `GLES=1`（同时让 `Makefile.common` 自动关掉只支持桌面 GL 的 `GLIDEN64`）。**验证**：编译命令行出现 `-DHAVE_OPENGLES -DHAVE_OPENGLES2`、`GL/gl.h` 报错归零、产出 `install_pkg/parallel_n64-*/usr/lib/libretro/parallel_n64_libretro.so`，全量构建里转为 `[311/345] [DONE] install parallel_n64:target`。排查同类问题时用：在核心 package.mk 里同时 `grep OPENGLES_SUPPORT` 与 `HAVE_OPENGL=0`（本树只有 `melonds` 与它，前者早已编过） |
| `melondsds:target during configure_target`：CMake 报 `Build step for melonds failed: 1`、`FetchContent.cmake:1679`、`ninja: build stopped`（本次真实故障，`[297/345]`） | 这个包在 **configure 阶段**用 CMake `FetchContent` 拉 **11 个 GitHub 依赖**（`melonDS`/`libretro-common`/`glm`/`fmt`/`zlib`/`libslirp`/`pntr`/`yamc`/`span-lite`/`date`/`embed-binaries`），而 github.com 直连被阻断 → 逐个预置 11 个仓库显然不现实 | **加 git 全局镜像重定向即可一次修好**（`tools/fix-build-env.sh --net-only` 会自动设置）：`git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"` —— 该配置对 `git clone`（FetchContent 用的就是它）**与所有子进程**生效，所以 FetchContent、git 源包、递归子模块一起解决。**验证**：清理后重编 `melondsds` → `EXIT=0`、产出 `install_pkg/melondsds-*/usr/lib/libretro/melondsds_libretro.so`（4,114,776 B） |
| `picodrive:host` → `make[1]: Entering directory '.../cpu/cyclone'` + `make[1]: *** No targets specified and no makefile found. Stop.` → `FAILED COMMAND: make -C ../cpu/cyclone CONFIG_FILE=../cyclone_config.h`（本次真实故障，`[093/345]`） | **我灌的 git 缓存漏了子模块**：`scripts/get_git` 会跑 `git submodule update --init --recursive --depth 1`，而 `seed_git_pkg.sh` 只做了 `git fetch --depth 1` + `checkout` → 子模块挂载点（`cpu/cyclone`、`platform/libpicofe`…）在 tarball 里只是**空目录**，编译时自然找不到 Makefile。判定方法：缓存 tarball 里有 `.gitmodules`，但 `.gitmodules` 声明的 `path=` 目录下**一个文件都没有** | ① 用支持子模块的 `bash /tmp/seed_any_pkg.sh <pkg>`（仓库内版本：`tools/seed-any-pkg.sh`）重灌 —— 它会 `git submodule update --init --recursive --depth 1`，并为 github 子模块加上 `-c url."https://gh-proxy.com/https://github.com/".insteadOf="https://github.com/"`（**`-c` 会传递给子进程，所以嵌套子模块如 flycast→glslang→SPIRV-Tools 也能过代理**）；② **必须** `rm -rf <build>/build/<pkg>-* <build>/.stamps/<pkg>` —— `unpack` 是按 stamp 跳过的，光换 tarball 不会重新解包，旧空目录会一直在。本次共 6 个包中招（`easyrpg`/`flycast`/`pcsx_rearmed`/`picodrive`/`vbam`/`yabasanshiro`）。**验证**：`picodrive:host` → `EXIT=0`，日志出现 `Creating Opcodes: … 36426 ARM instructions used` |
| `Cannot get llvm sources : https://github.com/llvm/llvm-project/releases/download/...` → `FAILURE: scripts/build llvm:host has failed!`（本次真实故障，`[253/432]`） | **`llvm:host` 只是被 Rust 核心间接拉进来的**：依赖链 `llvm:host → rust:host → cargo:host → {boytacean, doukutsu_rs, rustation_ng}` —— 全树只有这 3 个 Rust 写的 libretro 核心依赖 `cargo:host`。而 LLVM 源码是 **130 MB** 的 GitHub release 资产，本机 HTTPS 建不了连接（`Unable to establish SSL connection`），`~/bin/wget` 的 HTTPS→HTTP 兜底也**救不了**（GitHub 有 HSTS，会把 http 强制转回 https），LibreELEC 镜像又是 404 | 两条路：① **推荐**——排除那 3 个 Rust 核心（`EXCLUDE_LIBRETRO_CORES+=" rustation_ng boytacean doukutsu_rs"`），依赖链整条消失，130 MB 下载与数小时的 LLVM 编译都省掉；三者都有更好的替代（PS1：`beetle_psx`/`pcsx_rearmed`/`swanstation`；GB：`gambatte`/`sameboy`；洞窟物语：`nxengine`）。② 若确实要保留 Rust 核心，就得想办法拿到 LLVM：可走 GitHub 代理（实测 `gh-proxy.com` 2.3s、`ghfast.top` 6.3s 可用）手动下到 `sources/llvm/llvm-19.1.7.tar.xz` 并补齐 `.url`/`.sha256` 戳（见 §4.5）。**验证**：重新生成清单后确认 `llvm:host`/`rust:host`/`cargo:host` 三行都消失、任务数从 432 降到 347 |
| `patch ... Hunk #1 FAILED`（内核补丁）                                                                                                                                                                                                                                   | 补丁是为主线内核写的，vendor 6.1 内核不适用                                                                                                                                                                    | 主线补丁已归入 `projects/Rockchip/patches/linux/default/`；vendor 内核 case 用 `PKG_PATCH_DIRS="vendor"`。新增 RK3588 专用补丁放 `patches/linux/vendor/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `-march=` 为空 / `unknown CPU` 之类                                                                                                                                                                                                                                    | `config/arch.aarch64` 不认 `cortex-a76.cortex-a55`                                                                                                                                               | 已修复；若回退分支记得带上这一改动                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `u-boot: ./make.sh ...` 之后 FIT 生成失败、提示缺 `BL31` / `python2` / `dtc`                                                                                                                                                                                                 | 野火 `make.sh` 的依赖或 rkbin 路径不对                                                                                                                                                                   | 确认 `dtc`、`python2` 在 PATH；确认 `build.Lakka-RK3588.aarch64/build/rkbin` 软链存在（our package 自动创建）；`rkbin/RKTRUST/RK3588TRUST.ini` 里的 bl31 路径必须真实存在                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `install: uboot.img was not produced`                                                                                                                                                                                                                              | U-Boot 没走到 FIT 打包阶段                                                                                                                                                                            | 看 `build.Lakka-RK3588.aarch64/build/u-boot-*/` 里的日志与产物；确认 `CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y`（由 defconfig 提供）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `ld: cannot find -lEGL/-lGLESv2` 编译 GLES 相关包时                                                                                                                                                                                                                      | libmali 的库没进 sysroot                                                                                                                                                                           | 确认 `libmali` 包先于依赖方构建（`./scripts/build libmali`），并检查 `${SYSROOT_PREFIX}/usr/lib` 下有 `libEGL.so*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| 运行时 dlopen libmali 失败：`libX11.so.6 not found`                                                                                                                                                                                                                      | 用了 SDK 的 `x11-wayland-gbm` 变体                                                                                                                                                                  | 必须用 **`-gbm` 变体**（`NEEDED` 只有 libdrm/libc/libstdc++）——当前包已如此                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 编译被 OOM killer 杀掉 / 机器卡死                                                                                                                                                                                                                                           | 4 核 15 GiB 偏紧                                                                                                                                                                                  | `THREADCOUNT=2` 重跑；或加 swap（`sudo fallocate -l 8G /swap.img` 系列命令）；单个包失败就 `./scripts/clean <pkg>` 后单独重编                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 磁盘写满                                                                                                                                                                                                                                                               | 构建+缓存约 40–60 GiB                                                                                                                                                                               | `df -h /home/dev`；清 `target/`、单个 `build.*/build/<pkg>-*`；**不要动 SDK，也不要 `make distclean` 后不清 `sources/`**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `Building as the root user is NOT supported`                                                                                                                                                                                                                       | 用了 root                                                                                                                                                                                        | 用 `dev` 用户                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `Building in a folder that includes spaces is NOT supported`                                                                                                                                                                                                       | 路径含空格                                                                                                                                                                                          | 换路径                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |

### 6.2 上机启动期

| 现象              | 排查顺序                                                                                                                                                                                                 |                                                                         |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| 串口完全无输出         | ① 接线/波特率：UART2，**1500000 8N1**，GND 共地 ② 是否从 eMMC 启动（板载 SPI NOR 若已有 bootloader，BootROM 可能优先 SPI，需清 SPI 或用 rkdeveloptool 直写 eMMC）③ 确认 `dd` 写的是整盘而非分区 ④ 用 `rkdeveloptool` 的 Maskrom 模式看是否能枚举            |                                                                         |
| U-Boot 起来但找不到内核 | 看 `printenv bootcmd`（应含 `run distro_bootcmd`）；`ls mmc 0:1 /` 看 BOOT 分区里是否有 `extlinux/extlinux.conf`、`KERNEL`、`rk3588-lubancat-5.dtb`；`cat mmc 0:1 /extlinux/extlinux.conf` 确认 `FDT` 指向的 dtb 名与实际文件一致 |                                                                         |
| 内核起来但挂不上 rootfs | 串口日志看分区号；`SYSTEM_PART_START=32768`/`SYSTEM_SIZE=2048` 与镜像一致；必要时加 `initramfs` 调试                                                                                                                      |                                                                         |
| **HDMI/串口都能看到内核日志，但永远进不了系统；日志反复刷 `Filesystem uses "zstd" compression. This is not supported`，`loop0: detected capacity change from 0 to 1837288` 每秒重复一次** | **内核的 squashfs 缺 zstd 解码器**：`projects/Rockchip/options:30` 设 `SQUASHFS_COMPRESSION="zstd"`，而 LubanCat vendor defconfig 只开了 `SQUASHFS_{ZLIB,LZO,XZ}` → SYSTEM（squashfs）挂不上，initramfs 每秒重试约 15 次后放弃，**永远走不到 switch_root**。设备内核配置已补 `CONFIG_SQUASHFS_ZSTD=y` | 验证：① `grep '^CONFIG_SQUASHFS_ZSTD=y' build.*/build/linux-*/.config`；② 构建日志应有 `CC fs/squashfs/zstd_wrapper.o`；③ `nm build.*/build/linux-*/vmlinux | grep squashfs_zstd_comp_ops`；④ 镜像的 `.system` 前 32 字节偏移 20 处为 `06 00`（squashfs 压缩 id 6 = zstd） |
| **HDMI 上有内核日志，但串口敲回车毫无反应** | 内核把**最后一个** `console=` 当作 `/dev/console`（交互控制台）。之前写 `console=ttyFIQ0 console=tty1` → 交互控制台落在 HDMI(tty1)，串口只收到 printk 镜像、没有 getty/shell。已改为 `console=tty1 console=ttyFIQ0`（两个 console 都仍收到 printk） | 想临时在 initramfs 里要一个 shell：cmdline 加 `boot_step=<步骤名>`（如 `boot_step=mount_sysroot`）；GRUB/ESP 里的 `progress` 与 `debug_shell()` 都写 stderr，控制台就是 `/dev/console` |
| **能进系统，但 `/storage` 只有 26 MB，没有自动扩容**（`df -h` 里 `/dev/mmcblk0p3` 26M/100%） | **LibreELEC 的 `fs-resize` 硬编码 /storage 是分区 2**（`PART=$(grep "/storage " /proc/mounts | cut -d" " -f1 | grep '2$')`）。Rockchip `update.img` 布局（`package-file-extboot`）把 uboot/boot/rootfs 定义为分区 **1/2/3**，`/storage` 在 **p3** → `PART`/`DISK` 为空 → 走到 `Partition was not detected - resizing aborted.`，而它在检测**之前**就删掉了 `/storage/.please_resize_me`（第 51 行），所以**永不重试**。`/flash/fs-resize.log` 是现场证据 | 已修：`packages/sysutils/busybox/scripts/fs-resize` 改为从挂载设备名推导分区号（`PARTNUM`）并用 `parted resizepart ${PARTNUM} 100%`。重刷镜像后首次开机会自动扩容并重启一次。**已在用的机器**不想重刷时手工做：`parted -s -f -m /dev/mmcblk0 resizepart 3 100%` → `reboot` → `resize2fs /dev/mmcblk0p3` → `df -h /storage` |
| 屏幕无显示           | 默认命令行带 `video=HDMI-A-1:1920x1080@60`；先确认串口正常再用 `cat /sys/kernel/debug/dri/0/state` 看显示状态                                                                                                             |                                                                         |
| **HDMI 完全无信号，且串口出现 `[drm:vop2_bind] *ERROR* No crtc register, please check dts config` / `display-subsystem: failed to bind fdd90000.vop: -19`** | **板级 dts 把显示路由的 include 注释掉了**：`rk3588-lubancat-5.dts` 第 23 行 `// #include "rk3588-lubancat-5-hdmi0-vp0.dtsi"` 是注释状态，于是 `&hdmi0` / `&hdmi0_in_vp0` / `&route_hdmi0` 从未被设为 `okay` → vop2 注册 **0 个 CRTC** → DRM 绑定失败 → 没有 `/dev/dri/card0`，HDMI 与 `console=tty1` 都无处输出。**厂商自己预编译的 `rk3588-lubancat-5.dtb` 同样是 `disabled`**——这是留给你按显示方案自开选项的骨架，不是出厂配置。注意**不要换用 `rk3588-lubancat-generic.dtb`**（厂商 SDK 默认），它只 `#include "rk3588s.dtsi"`，是 RK3588**S** 基座，对完整 RK3588 的鲁班猫5 会丢外设 | 已由 `patches/linux/vendor/rockchip-9000-rk3588-lubancat-5-enable-hdmi0-vp0.patch` 修好（取消注释该 include）。验证：`dtc -I dtb -O dts target/*.img.gz解出的/rk3588-lubancat-5.dtb | grep -A30 'hdmi@fde80000'` 应为 `status = "okay"`，且 `grep -A8 'route-hdmi0 {'` 为 `okay`、`grep -c rockchip-hdmi0` = 1；板上 `ls /dev/dri/` 应出现 `card0` |
| 进系统但没画面/黑屏      | GPU 未初始化：\`dmesg                                                                                                                                                                                     | grep -i mali`、`ls /lib/firmware/mali_csffw.bin`、`ls /usr/lib/libmali*\` |

### 6.3 串口登录与调试

- 内核串口：UART2，**1500000 8N1**。vendor 内核把它交给 fiq_debugger → 设备节点是 **`/dev/ttyFIQ0`**（没有 `ttyS2`）
- 交互控制台是谁：内核取**最后一个** `console=` 作 `/dev/console`。本设备是 `console=tty1 console=ttyFIQ0`，且 u-boot 会把它规整成 `console=ttyFIQ0 console=ttyFIQ0`（见启动日志的 `Kernel command line:`），所以交互控制台就是串口
- **串口 shell**：由设备包 `packages/rk-serial-console` 提供（`ttyFIQ0-console.service`）。做法是**直接在 tty 上起一个 root 登录 shell**（`ExecStart=-/bin/sh -l` + `StandardInput=tty-force` + `TTYPath=/dev/ttyFIQ0`），与 systemd 自带的 `debug-shell.service` 是同一套机制，不需要 getty/login
  - **为什么不用 agetty**：① LibreELEC 有意删除了所有 getty 单元（`packages/sysutils/systemd/package.mk`）；② 镜像里**根本没有 agetty** —— `packages/sysutils/util-linux` 的目标配置是 `--disable-all-programs` + 白名单，白名单里没有 `--enable-agetty`。真想用 agetty 必须先改 util-linux 配置（项目级覆盖的写法可参考 `projects/L4T/packages/util-linux/package.mk`）
  - **踩坑 1（假阳性，极易误判）**：`$BUILD/image/system/bin` 与 `/sbin` 是**绝对**符号链接（`bin -> /usr/bin`、`sbin -> /usr/sbin`），所以在构建机上 `ls image/system/sbin/agetty` 会穿透到**宿主机**的 x86_64 二进制、看起来"文件存在"，而镜像里其实没有。核查镜像真实内容要用宿主的 `unsquashfs -ll target/*.system`；**不要**用 `$BUILD/toolchain/bin/unsquashfs`（那是目标二进制，在宿主上跑不了，会静默无输出）
  - **踩坑 2（systemd 依赖）**：unit **不能**写 `After=/BindsTo=dev-ttyFIQ0.device`。fiq_debugger 自己注册 tty、udev 从不给它打 tag，`dev-ttyFIQ0.device` 永远不 active，unit 会永远卡在 `systemd[1]: Expecting device dev-ttyFIQ0.device...` 而永不启动（已在板子上实测）
  - 诊断：`systemctl --no-pager -l status ttyFIQ0-console`；`ls -l /dev/ttyFIQ0`；`cat -v /dev/ttyFIQ0`（然后在串口窗口敲字符，SSH 里应看到对应字符 —— 这条能单独验证串口**接收**通路是否正常）
- 不要用 `DEBUG_TTY`：那只是 systemd **debug-shell** 的 tty（build 时 `-Ddebug-tty=`，projects/Rockchip/options 设的 `/dev/ttyS2` 在本内核不存在），不是自动 getty
- 常用诊断：`dmesg | head -50`、`cat /proc/cmdline`、`cat /sys/kernel/debug/dri/0/state`、`cat /sys/kernel/debug/clk/clk_summary`

---

## 七、烧写与验证

```bash
# 1) 解压镜像
gunzip -k target/Lakka-RK3588.aarch64-*.img.gz

# 2) 写 eMMC（把整盘写进去；注意 /dev/mmcblkX 是“整盘”不是分区）
sudo dd if=target/Lakka-RK3588.aarch64-*.img of=/dev/mmcblkX bs=4M conv=fsync status=progress
sync

# 3) 接 USB-TTL 看日志：UART2 / 1500000 8N1
#    期望：BootROM → SPL(loader) → U-Boot(U-Boot 2017.09 ...) → distro_bootcmd → Image + dtb → 内核日志 → Lakka
```

---

## 八、清理与回滚

```bash
# 只清某个包
./scripts/clean <pkg>

# 全清构建目录（保留 sources 缓存，工具链会重编）
rm -rf build.Lakka-RK3588.aarch64

# 强制重新下载某源码（会触发联网，谨慎）
rm -f sources/linux/linux-*.tar.xz*

# 回到未移植状态
git switch Lakka-v6.1
# 丢弃移植改动
git stash -u        # 或 git switch -f Lakka-v6.1
```

---

## 九、从零复现这次移植（万一要在别的机器重做）

移植脚本都已落在 `/tmp`（建议复制到仓库外长期保存）：

| 脚本                                  | 作用                                                                                                                           |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **`tools/fix-build-env.sh`** | 仓库内交付脚本（**推荐入口**）：一键补齐宿主依赖 + 网络垫片，幂等、支持 `--check`。与下面 `/tmp/` 的临时脚本功能重叠，但更适合新用户 |
| **`tools/configure-cores.sh`** | 仓库内交付脚本：交互式配置要打进镜像的 libretro 核心（预设方案 + 分类勾选 + 写回校验） |
| **`tools/NETWORK_BUILD.md`** | 仓库内交付文档：国内网络构建的原理、验证步骤与完整排查表 |
| **`tools/audit-missing-sources.sh`** / **`tools/seed-missing-sources.sh`** / **`tools/seed-any-pkg.sh`** | 仓库内交付脚本：审计并批量预置缺缓存的源码（git 含**递归子模块** / 归档做 SHA256 校验） |
| `/tmp/rk3588-port/apply_edits.py`   | 放好设备项目文件 + 改 uboot_helper/arch.aarch64/linux case/bootloader install/CI 清单                                                   |
| `/tmp/rk3588-port/patch_sources.py` | 把内核/u-boot/rkbin 包改成归档源（含 SHA256）                                                                                            |
| `/tmp/seed_sources.sh`              | 从 SDK 生成 linux/u-boot/rkbin 的源码缓存                                                                                            |
| `/tmp/make_libmali_src.sh`          | 生成 libmali 源码缓存                                                                                                              |
| `/tmp/patch_get_git_retry.py`       | 给 `scripts/get_git` 加网络重试循环（幂等，已打过会跳过）                                                                                       |
| `/tmp/probe_snapshot_hashes.py`     | 体检全树所有 `*/snapshot/*` 源：下载并与 recipe 哈希比对，输出 OK / MISMATCH / DL-FAIL                                                          |
| `/tmp/wget-https-fallback`          | 安装为 `~/bin/wget`：HTTPS 失败自动用同 URL 的 HTTP 重试（代理 TLS 不通的站点）                                                                    |
| `/tmp/patch_sdl_host.py`            | 修 `SDL/package.mk`：host 侧剔除 target ABI 路径（幂等）                                                                                            |
| `/tmp/seed_git_pkg.sh`              | **通用（单包、不含子模块）**：经 `gh-proxy.com` 用 git 协议抓取 git 源包并生成 `get_git` 格式缓存（`<pkg>-<sha>.tar.xz` + `.gitstamp`）。`bash /tmp/seed_git_pkg.sh <pkg> <owner/repo> <sha>`。⚠️ 若包含 `.gitmodules` 请改用 `seed_any_pkg.sh` |
| `/tmp/seed_any_pkg.sh`              | **通用（含子模块 + 归档源），首选**：自己读 `package.mk` 解析 `PKG_NAME/VERSION/URL/SHA256` 并展开 `${...}` 占位符；git 源走 `git fetch --depth 1` + **`git submodule update --init --recursive`**（github 子模块自动经代理，`insteadOf` 对嵌套子模块同样生效），归档源做下载 + SHA256 校验 + `.url`/`.sha256` 三件套。用法 `bash /tmp/seed_any_pkg.sh <pkg>` |
| `/tmp/seed_missing_batch.sh`        | 批量：按审计结果逐个调用 `seed_any_pkg.sh`，日志 `/tmp/seed-missing.log`。`bash /tmp/seed_missing_batch.sh /tmp/audit-out.tsv` |
| `/tmp/audit_missing_sources.sh`     | 审计：列出构建计划里**所有缺缓存**的包（git 看 `.gitstamp`、归档看 `.url`+`.sha256`），输出 `type/pkg/host/url/version` TSV。`bash /tmp/audit_missing_sources.sh /tmp/plan-new2.txt` |
| `/tmp/scan_submodules.sh`           | 扫描：找出缓存 tarball 里含 `.gitmodules` 的包（这些包**必须**带子模块灌源） |
| `/tmp/scan_empty_submodules.sh`     | 精查：读 `.gitmodules` 的 `path=` 列表，逐条判断该目录在 tarball 里是否**真的为空** —— 区分「我灌的（空）」与「`get_git` 灌的（已填充）」。`bash /tmp/scan_empty_submodules.sh <pkg...>` |
| `/tmp/reseed_submodules.sh`         | 批量重灌被判定为子模块为空的包 |
| `/tmp/seed_amiarcadia3.sh`          | **离线**灌 `amiarcadia` 缓存：直接复用此前已抓取并校验过 SHA 的树（`/tmp/amtest`），无需网络 —— 网络全断时也能完成                                |
| `/tmp/patch_amiarcadia_mirror.py`   | 把 `amiarcadia` 核心的源从不可达的 `git.libretro.com` 换成 GitHub 镜像（幂等，已改会跳过）                                                                          |
| `/tmp/seed_amiarcadia.sh`           | 灌 `amiarcadia` 的 **git 缓存**：先 10 次 HTTPS 重试，失败自动转 SSH，最后按 `get_git` 的格式生成 `<sha>.tar.xz` + `<sha>.tar.xz.gitstamp`（git 源**不能用**归档三件套） |
| `/tmp/fix_host_deps.sh`             | 补齐 `checkdeps` 要求、但构建流程并不使用的宿主依赖（`rdfind` / perl `JSON` / `Parse::Yapp::Driver`），免 sudo                                      |
| 手动步骤                                | ① `git switch -c rk3588-port` ② 把 57 个主线补丁 `git mv` 到 `patches/linux/default/` ③ 全树 `ftpmirror.gnu.org` → `ftp.gnu.org/gnu/` |

---

## 十、尚未完成/待验证（当前进度）

- [x] 设备项目、构建系统改动、源码缓存、libmali 包（编译期就绪）
- [x] aarch64 工具链 + glibc 编译通过（含 CPU 目标 `-mtune` 与 `--enable-kernel` 两处修正）
- [x] 内核本体编译通过（关 `CONFIG_WERROR` 越过 vendor WiFi 驱动；`arch/arm64/boot/Image` 45.9 MB 已产出）
- [x] U-Boot 编译 + FIT 打包通过（`uboot.img` 8 MiB、`rk3588_spl_loader_v1.18.113.bin`，容器按 32 KiB / 8 MiB 摆好）
- [ ] `make image` 出镜像（**进行中：`[244/347]`、`FAILED: 0`**——任务总数已因裁剪核心从 432 降到 347）
- [x] 核心裁剪：`devices/RK3588/options` 里写入 `EXCLUDE_LIBRETRO_CORES`（82 个），核心 172→90，并连带去掉 `llvm/rust/cargo` 工具链
- [ ] 网络恢复后继续：`~/resume_build.sh`；若某包源码拉不下，按 §4.5 单独修（`amiarcadia` 已就绪，无需再处理）
- [ ] 上机启动验证（eMMC 烧写 + UART2 串口）
- [ ] GPU 实机验证（`glmark2-es2` / RetroArch GLES）、`libstdc++.so.6` 是否随镜像提供（libmali blob 依赖它）
- [ ] 视频硬解（vendor 内核下 lakka 的 `kernel_options_overrides` 会关掉 V4L2，需要例外机制）
- [ ] 4K 输出、HDMI 音频、风扇调速

---

## 十一、镜像内容由什么决定、如何增删软件（包选择机制）

### 11.1 决策链：谁说了算

`make image` 实际只做一件事——构建**唯一一个虚拟包 `image`**（`scripts/image:141`：
`MTADDONBUILD=no start_multithread_build image`）。其余全部由依赖闭包展开：

| 环节 | 文件 | 作用 |
| --- | --- | --- |
| 三层参数 | `distributions/Lakka/options` → `projects/Rockchip/options` → `projects/Rockchip/devices/RK3588/options` → `config/arch.aarch64` | 按顺序 source，后者覆盖前者（见 §3.3） |
| **顶层清单** | `packages/virtual/image/package.mk` | `PKG_DEPENDS_TARGET` 列出顶层组件，下半部分按开关条件追加 |
| 分类元包 | `packages/virtual/{network,debug,remote,alsa,x11,mediacenter,misc-packages,linux-drivers,linux-firmware,…}/package.mk` | 每类再列一批包；其中 `misc-packages` = `toolchain ${ADDITIONAL_PACKAGES}` |
| 叶子包 | 各包自己的 `PKG_DEPENDS_TARGET` | 继续递归展开 |
| 任务清单 | `<build>/.threads/plan`（另有 `plan.json`） | 生成命令见 11.4 |

本设备实测：`Packages loaded: 1189`、`Package steps: 432` = **78 个 `build`（host 工具）+ 354 个 `install` 任务** —— 这就是日志里 `[n/432]` 的来源。

`install image` 展开后的顶层清单（实测）：

```
install image (wants: toolchain, squashfs-tools:host, dosfstools:host, fakeroot:host,
  kmod:host, mtools:host, populatefs:host, libc, gcc, linux, linux-drivers,
  linux-firmware, u-boot, busybox, util-linux, corefonts, network, misc-packages,
  debug, exfatprogs, mediacenter, alsa, udevil)
```

### 11.2 每个包"放什么文件进镜像"

* 包自己的 `makeinstall_target()` 把文件写进 `${PKG_INSTALL}`（= `<build>/install_pkg/<pkg>/`）。
* `scripts/install` 末尾用 `tar` 把 `${PKG_INSTALL}` 合并进 `${INSTALL}`（= `<build>/image/system`），并**自动排除** `*.a`、`*.la`、`include/`、`*/pkgconfig`、`*/cmake`、`.*` —— 所以头文件与静态库不会进镜像。
* `scripts/image` 再把 `<build>/image/system` 打成 squashfs（`.system`），内核单独拷成 `.kernel`，最后交给 `projects/Rockchip/bootloader/mkimage` 生成 `.img`。
* 另有两条**绕过包机制**的直插通道（`scripts/image` 189–221 行）：`projects/<PROJECT>/filesystem/*` 与
  `projects/<PROJECT>/devices/<DEVICE>/filesystem/*` 会被**原样拷进镜像根**，其中的 `*.service` 还会被自动 enable
  （并把 `kodi.service`→`retroarch.service`、`kodi.target`→`retroarch.target`）。

### 11.3 增删软件的层次（从轻到重）

| 想做什么 | 改哪里 | 影响面 | 本仓库已在用的例子 |
| --- | --- | --- | --- |
| **加包** | `ADDITIONAL_PACKAGES+=" foo bar"`（写在 `projects/<PROJECT>/options` 或 `projects/<PROJECT>/devices/<DEVICE>/options`） | 项目级 / 设备级 | 设备级 `pciutils`、项目级 `dtc`、发行版级 `rsync` |
| **用开关关功能／减包** | 同名 `options` 里的开关：`MEDIACENTER`(lakka/kodi/no)、`DISPLAYSERVER`、`INSTALLER_SUPPORT`、`REMOTE_SUPPORT`、`ALSA_SUPPORT`、`PULSEAUDIO_SUPPORT`、`PIPEWIRE_SUPPORT`、`UDEVIL`、`TESTING`、`OEM_SUPPORT`、`BLUETOOTH_SUPPORT`、`SAMBA_SUPPORT` | 按开关范围 | `distributions/Lakka/options`：`MEDIACENTER="lakka"`、`INSTALLER_SUPPORT="yes"` |
| **改清单减包** | `packages/virtual/image/package.mk`（顶层）或某个分类元包；libretro 核心则改 `packages/lakka/libretro_cores/package.mk` 的 `LIBRETRO_CORES` | **全部设备**（慎改） | 现有 183 个核心，删几行即少编几个 |
| **改某个包的内容** | 设备级覆盖目录 `projects/<PROJECT>/devices/<DEVICE>/packages/<pkg>/`（可放 `package.mk`/`patches/`/附加文件） | 仅该设备 | 覆盖了 `u-boot`、`rkbin`、`libmali` |
| **塞自己的文件 / 服务** | `projects/<PROJECT>/devices/<DEVICE>/filesystem/` | 仅该设备 | 配置、脚本、systemd unit、固件 |
| **固件白名单** | `projects/<PROJECT>/devices/<DEVICE>/config/kernel-firmware-any.dat` | 仅该设备 | 挑了 `rockchip/*` 等 |

⚠️ 注意 `toolchain libc gcc linux linux-drivers linux-firmware busybox util-linux corefonts network misc-packages debug exfatprogs` 在 `image` 里是**无条件**的（`debug` 会带进 `gdb` / `edid-decode` / `memtester` / `strace` / `kmsxx`）。要减这些必须改 `packages/virtual/image/package.mk`；只用一个 `ADDITIONAL_PACKAGES` 是减不掉的。

### 11.4 查看与验证

```bash
cd /home/dev/Lakka-LibreELEC

# ① 本次构建的完整任务清单（432 行，格式：install <pkg> (wants: ...)）
cat build.Lakka-RK3588.aarch64/.threads/plan

# ② 按当前配置重新生成一份（不依赖已有构建；实测 432 行、EXIT=0）
env PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  bash -c '. config/options ""; set -o pipefail;
           ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' > /tmp/plan.txt

# ③ 某个包往镜像里放了什么
ls build.Lakka-RK3588.aarch64/install_pkg/<pkg>/

# ④ 镜像根目录（staging，构建收尾时才完整）
ls build.Lakka-RK3588.aarch64/image/system/usr/lib/libretro/   # 各 libretro 核心

# ⑤ 已构建完成的包
ls build.Lakka-RK3588.aarch64/.stamps/
```

### 11.5 用开关关功能：应该改哪个文件

选项文件按**固定顺序** source（`config/options` 第 45–61 行），**后加载的覆盖先加载的**：

| 顺序 | 文件 | 作用范围 |
| --- | --- | --- |
| 1 | `distributions/Lakka/options` | 所有 Lakka 设备（发行版默认值） |
| 2 | `projects/Rockchip/options` | 所有 Rockchip 板卡 |
| 3 | **`projects/Rockchip/devices/RK3588/options`** | **只影响鲁班猫5 ← 推荐** |
| 4 | `config/arch.aarch64` | 架构相关 |
| 5（最后） | `${ROOT}/.libreelec/options`、`~/.libreelec/options` | **本机临时覆盖，优先级最高**；`/.libreelec` 已写进 `.gitignore`（第 16 行），不会进仓库 |

所以"关功能"就是在**你期望的那一层** options 文件里写一行同名赋值（普通赋值即可，不用 `export`）：

```sh
# projects/Rockchip/devices/RK3588/options（设备级，推荐）
BLUETOOTH_SUPPORT="no"
PULSEAUDIO_SUPPORT="no"
```

`projects/Rockchip/options` 里已有现成范例：`DISPLAYSERVER="no"`、`CEC_FRAMEWORK_SUPPORT="no"`、`INSTALLER_SUPPORT="no"`、`DRIVER_ADDONS_SUPPORT="no"`。

常用开关及其影响：

| 开关 | 影响 |
| --- | --- |
| `MEDIACENTER`（`lakka`/`kodi`/`no`） | 设成 `no` 会**移除 retroarch 与全部 libretro 核心（183 个）** —— 游戏机镜像千万别动 |
| `INSTALLER_SUPPORT` | `no` 则不带 `install2emmc` 等安装器（Rockchip 项目级已设 `no`） |
| `BLUETOOTH_SUPPORT` | 实测 `no` → 少一个 `bluez`（432 → 431） |
| `SAMBA_SUPPORT` / `NFS_SUPPORT` / `ISCSI_SUPPORT` | 网络共享相关组件 |
| `OPENVPN_SUPPORT` / `WIREGUARD_SUPPORT` | VPN 客户端 |
| `ALSA_SUPPORT` / `PULSEAUDIO_SUPPORT` / `PIPEWIRE_SUPPORT` | 音频栈（Lakka 现状：ALSA=yes，后两者 no；二者不可同时开） |
| `JOYSTICK_SUPPORT` | 手柄支持（游戏机建议保持 `yes`） |
| `CEC_SUPPORT` / `CEC_FRAMEWORK_SUPPORT` | HDMI-CEC |
| `CRON_SUPPORT` / `SWAP_SUPPORT` | cron / swapfile |
| `REMOTE_SUPPORT` | 遥控器元包（`eventlircd libirman v4l-utils evrepeat`） |
| `OEM_SUPPORT` | OEM 包；也可命令行覆盖：`OEM=yes make image` |
| `HARDENING_SUPPORT` / `LTO_SUPPORT` / `GOLD_SUPPORT` | 编译与安全相关，**改动会触发大范围重编**，慎用 |

**验证（改完先看清单，别直接开编）**：

```bash
cd /home/dev/Lakka-LibreELEC
env PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  bash -c '. config/options ""; set -o pipefail;
           ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' > /tmp/plan-new.txt
wc -l /tmp/plan-new.txt          # 基线是 432 行
diff /tmp/plan-old.txt /tmp/plan-new.txt   # 看具体增删了哪些包
```

实测：加一行 `BLUETOOTH_SUPPORT="no"` → 431 行，`install bluez` 整行消失、`network` 的 `wants` 不再含 `bluez`；删掉该文件后回到 432 行且与基线逐行一致。

⚠️ 三个注意点：

* 开关只能用在**可减的地方**。`toolchain libc gcc linux linux-drivers linux-firmware busybox util-linux corefonts network misc-packages debug exfatprogs` 在 `packages/virtual/image/package.mk` 里是**无条件**的，靠开关减不掉（见 11.3）。
* 改动会改变依赖图：已构建的包不会自动删除（留在 `build/` 里不影响结果），下次 `make image` 会按新图构建；而 `HARDENING_SUPPORT`/`LTO_SUPPORT` 这类会影响编译命令行的开关会引起大范围重编。
* 别用 `+=` 去"追加"，例如 `INSTALLER_SUPPORT+=" no"` 会得到 `"yes no"`，判断就失效了。

### 11.6 去掉不需要的 libretro 核心（比如 atari800）

核心清单在 `packages/lakka/libretro_cores/package.mk` 的 `LIBRETRO_CORES`（本设备实际进镜像 **189 个核心**）。**上游已内置排除机制**，不必改共享文件：

```bash
# exclude some cores at build time via env EXCLUDE_LIBRETRO_CORES="core1 core2"
# passed to make and cores added to the env above
if [ -n "${EXCLUDE_LIBRETRO_CORES}" ]; then
  for core in ${EXCLUDE_LIBRETRO_CORES} ; do
    LIBRETRO_CORES="${LIBRETRO_CORES// ${core} /}"
  done
fi
PKG_DEPENDS_TARGET="${LIBRETRO_CORES}"
```

| 目的 | 做法 |
| --- | --- |
| **只对鲁班猫5 生效（推荐）** | 在 `projects/Rockchip/devices/RK3588/options` 加一行 `EXCLUDE_LIBRETRO_CORES="atari800 a5200 prosystem vecx o2em handy"` |
| 只临时试一次 | `EXCLUDE_LIBRETRO_CORES="atari800 a5200" make image` |
| 影响所有设备 | 直接删 `packages/lakka/libretro_cores/package.mk` 里 `LIBRETRO_CORES` 的对应行 |
| 一个核心都不要 | `DISABLE_LIBRETRO_CORES="yes"`（在 `packages/lakka/package.mk` 里判断） |

**实测（本设备）**：只加选项文件那一行 → 任务清单 **432 → 426**（正好少 6 个），`install atari800`/`a5200`/`prosystem`/`vecx`/`o2em`/`handy` 六行全部消失；用环境变量得到的结果与写进选项文件**逐行完全一致**。核心数 172 → 166（含 `toolchain` 计数的口径）。

⚠️ 注意事项：

* **名字必须精确**：该机制是按**包名**做字符串替换，写错的名字会被**静默忽略、不报错**（实测写 `atari7800` 无效——Atari 7800 的核心包名其实是 `prosystem`）。改完务必用 §11.4 重新生成清单 + `diff` 核对。
* **核心之间互不依赖**：实测遍历所有核心的 `PKG_DEPENDS_TARGET`，只有 `toolchain`（个别带 `:host`），**没有任何核心依赖另一个核心**，所以删任何核心都不会连带破坏别的。
* 上游也用同一机制做设备特例，可作范本：`packages/lakka/libretro_cores/package.mk` 里对 `RPi3` 等设备执行 `EXCLUDE_LIBRETRO_CORES+=" panda3ds"`。
* 收益：核心编译是这次构建耗时的大头（`mame`/`mame2010`/`mame2015`、`scummvm`、`dolphin`、`ppsspp`、`same_cdi` 这类尤其慢），去掉不需要的能明显缩短构建时间并缩小镜像；每个核心会往 `/usr/lib/libretro/` 装一个 `.so` 与配套 `.info`，排除即从镜像消失。

**常用核心名对照（可直接复制）**：

| 机种 | 核心包名 |
| --- | --- |
| Atari 2600 / 5200 / 7800 / 8-bit 电脑 | `stella`（或 `stella2014`）/ `a5200` / `prosystem` / `atari800` |
| Vectrex / Odyssey² / Channel F / Intellivision | `vecx` / `o2em` / `freechaf` / `freeintv` |
| Atari Lynx / Arcadia 2001 / Watara Supervision | `handy`（或 `beetle_lynx`）/ `amiarcadia` / `potator` |
| Game & Watch / Virtual Boy / WonderSwan / Neo Geo Pocket | `gw_libretro` / `beetle_vb` / `beetle_wswan` / `beetle_ngp` |
| ZX Spectrum / C64 等 / MSX / Amstrad CPC | `fuse_libretro` / `vice` / `bluemsx`、`fmsx` / `crocods`、`cap32` |
| NEC PC-98 / PC-88 / Sharp X1 / X68000 | `np2kai`、`meowpc98` / `quasi88` / `xmil` / `px68k` |
| Thomson / Enterprise / P2000T | `theodore` / `ep128emu` / `m2000` |
| 非游戏机的小众平台（PICO-8、TIC-80、WASM-4、Uzebox、LowRes NX、ChaiLove、Lutro） | `retro8` / `tic80` / `wasm4` / `uzem` / `lowres_nx` / `chailove` / `lutro` |
| 内置小游戏／引擎类（非模拟器，可视需要保留） | `2048` / `81` / `dice` / `pocketcdg` / `gme` / `mu` / `mojozork` |

> 完整核心名单（裁剪前 172 个）可用 §11.4 的命令从 `plan` 里导出：`grep -oE "^install libretro_cores.*" <build>/.threads/plan | tr "," "\n"`。

#### 11.6.1 本设备已应用的裁剪（现状）

`projects/Rockchip/devices/RK3588/options` 里已写入 **84 个核心的排除名单**（"只留主流现代机种" + 指定项），效果实测：

| 指标 | 裁剪前 | 裁剪后 |
| --- | --- | --- |
| 任务总数 | 432 | **345** |
| 核心数 | 172 | **88** |
| `llvm:host`/`rust:host`/`cargo:host` | 有 | **消失**（连带的 130 MB LLVM 下载与编译都省掉） |

分两批应用：
1. **第一批 82 个**（方案 A "只留主流现代机种" + 指定 `lrps2`/`play`/`boom3`/`tyrquake`/`vitaquake2`/`vitaquake3`/`ecwolf`/`openlara`）→ 432 → 347、核心 172 → 90；
2. **第二批 2 个** = `dolphin`（GameCube/Wii）、`azahar`（3DS）→ 347 → **345**、核心 90 → **88**。
   注意 `dolphin` 是编译很重的大件；若它在上一轮已编完（stamp 存在），改完 options **必须重启构建**才能生效——
   正在跑的 job 用的是生成时的 plan，新增排除不会回溯。手工停掉旧 job 的写法：`pkill -f pkgbuilder`（`pkill -f "scripts/build"` 会自匹配杀掉自己所在的 ssh shell）。

校验方式（三个必查项，本次全部为"无"）：
1. 名单里的名字**是否都真实存在**（防拼写错误被静默忽略）；
2. 名单里的名字**是否都真的消失了**（防未生效）；
3. **是否有名单外的核心被误删**（防依赖副作用）。

留下的 88 个核心覆盖：任天堂（NES/SNES/N64/GB/GBA/NDS/VB）、
世嘉全系（MD/Saturn/Dreamcast）、索尼（PS1×3、PSP；已去掉 `lrps2`/`play`）、
街机（`mame` 系 5 个 + `fbneo`/`fbalpha2012`）、PC Engine 系、PC-FX、Neo Geo（AES/CD）、
CD-i、3DO、ColecoVision、Amiga×4、DOS×4、Commodore/C64、MSX、Atari ST、IBM PC/XT、
以及 `scummvm`/`prboom`/`reminiscence`/`nxengine` 等引擎。
（GameCube/Wii 的 `dolphin` 与 3DS 的 `azahar` 已在第二批中移除。）

> 想调整：直接编辑那一行 `EXCLUDE_LIBRETRO_CORES="..."`，然后按 §11.4 重新生成清单 + `diff` 核对即可（务必做上面三项校验）。
> 完整核心对照表见同目录 `CORES.md`。

