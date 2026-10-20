# Lakka - The DIY retro emulation console

Lakka is a lightweight Linux distribution that transforms a small computer into a full blown emulation console.

## Why use Lakka?

* **Powerful** - Built on top of the famous RetroArch emulator, Lakka is able to emulate a large range of hardware and has some useful features such as Braid-like rewinding, joypad hotplug and video streaming.
* **User friendly** - Lakka is easy to setup and use. Once installed to your SD card, you just have to put your rom on the card, plug your joypad and enjoy your favorite old games. We also support PS3 and XBox360 controllers so you don't have to buy new ones. 
* **Low cost** - We try our best to keep the hardware required to run Lakka as cheap as possible. The software is optimized to run fast even on low end computers. The power can be supplied by any micro USB adapter like the one for your smartphone.
* **Open source** - Our code is free as in freedom and hosted on Github (though the project uses emulators that forbid commercialisation). We accept external contributions, and we do our best to integrate our own patches into upstream projects.

## Installation instructions

Please refer to our website https://www.lakka.tv/get on how to setup Lakka.

## Rockchip / 野火鲁班猫支持（`lubancat` 分支）

本分支为野火（Embedfire）鲁班猫系列板卡提供 Lakka 支持，基于厂商 BSP 构建（vendor 6.1 内核 + vendor u-boot 2017.09 FIT 引导链 + rkbin）。所有源码都是构建时按钉住的 commit 自动从 GitHub 拉取，无需手动下载任何东西。

* **支持板卡**：鲁班猫 0 / 1 / 1N（RK3566）、鲁班猫 2 / 2-V1 / 2-V2 / 2-V3 / 2N（RK3568）、鲁班猫 3 / 3IO（RK3576）、鲁班猫 4 / 4-V1 / 5 / 5-V2 / 5IO（RK3588 / RK3588S）
* **验证状态**：鲁班猫 0（Zero N）/ 1 / 2 / 3 / 4 / 5 已上机验证（HDMI 出图、调试串口 root shell、首次开机自动扩容）；1N / 2-V1 / 2-V2 / 2-V3 / 2N / 3IO / 5-V2 / 5IO 已通过构建期产物校验，待上机测试
* **内置能力**：`build-board.sh` 选板构建、`mk-rockchip-update.sh` 打包 eMMC 用的 update.img（RKDevTool/upgrade_tool 直刷，**不依赖野火 SDK**）、`setup-cn-network.sh` 国内网络一键配置、串口（`/dev/ttyFIQ0`）开箱即用 root shell
* **DDR 频点**：RK3588 全系 1848MHz、RK3576 1560MHz、RK3568 1560MHz、RK3566 1056MHz（构建时自动选 rkbin 的 DDR blob，`DDR_FREQ=<MHz>` 可覆盖）

### 快速开始

```sh
# 1. 安装宿主依赖（Ubuntu/Debian x86_64）
sudo apt-get install make gcc g++ sed gawk wget patch pkg-config bison flex \
  ntp libssl-dev libxml2-dev zlib1g-dev libncurses-dev bc rsync zip unzip \
  imagemagick default-jre-headless xsltproc device-tree-compiler git lz4 \
  zstd libparse-yapp-perl rdfind
# （或用构建系统自查：  ./scripts/checkdeps）

# 2. 克隆本分支
git clone -b lubancat https://github.com/raidenkl/Lakka-LibreELEC.git
cd Lakka-LibreELEC

# 3. 选板构建，产物在 target/
./projects/Rockchip/tools/build-board.sh                        # 菜单选板
# ./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5    # 直接指定（RK3588）
# ./projects/Rockchip/tools/build-board.sh RK3576 lubancat-3    # 直接指定（RK3576）
# ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2    # 直接指定（RK3568）
# ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1    # 直接指定（RK3566）

# 国内网络不稳时，先执行一次（用户级配置，可 -u 撤销）
./projects/Rockchip/tools/setup-cn-network.sh
```

**刷写**（一律用 `update.img`；`build-board.sh` 构建成功后会自动打包，无需手动跑）：
- **SD 卡**：Rockchip 官方 `SD_Firmware_Tool` → 选「SD启动」→ 选 `target/*-update.img`
- **eMMC**：`RKDevTool` →「升级固件」→ 选同一个 `target/*-update.img`

> ⚠️ `target/*.img.gz` 是构建中间产物，不含 Rockchip 的打包元数据。实测同一个镜像用官方工具刷
> `update.img` 一切正常，所以只使用 `update.img`。

**SSH 默认开启**：`projects/Rockchip/options` 里 `SSH_ENABLED_DEFAULT="yes"` 会让 openssh 包
删掉 `sshd.service` 的 `Condition*` 启动守卫（服务本身已 enable），开机即监听 22 端口、root 登录。
想关掉就删掉这一行（或运行时 `systemctl mask sshd`）。注意这个开关在 openssh 的 install 阶段生效，
改了之后要先 `./scripts/clean openssh` 再构建，否则会命中旧的安装缓存。

> 刷完请**彻底断电 10 秒再上电**：RKDevTool 的「重启设备」不是真正断电，个别情况下首次启动会卡在
> eMMC 初始化（HDMI/串口都没输出），断电重启即恢复。


## 音频（喇叭 / 耳机）

### 为什么刷完默认没有声音

Rockchip 板卡的 codec 输出级默认是**关闭**的，而 Lakka/LibreELEC 的 udev `soundconfig`
只处理 `Master` / `PCM` / `Speaker` / `Headphone` 这类通用控件，不认识下面两个厂商私有开关：

| codec | 板卡 | 必须打开 | 默认值 |
| --- | --- | --- | --- |
| **RK809 / RK817** | 鲁班猫 0 / 1 / 1N（RK3566）、2 / 2-V1..V3 / 2N（RK3568） | `Playback Path` = `SPK` 或 `SPK_HP` | **OFF** |
| **ES8388 / ES8323** | 鲁班猫 3 / 3IO（RK3576）、4 / 5 / 5-V2 / 5IO（RK3588） | `OUT1 Switch`、`OUT2 Switch` = on | **off** |

另外 RetroArch 自己还有一层音量（`audio_volume`），它和 ALSA 是独立的两套开关，
排查时不要混在一起判断。

### 临时修复

RK809 板（RK3566 / RK3568）：

```sh
amixer -c 0 sset 'Playback Path' SPK_HP   # 喇叭 + 耳机同时输出
# 只开喇叭用 SPK，只开耳机用 HP
```

ES8388 板（RK3576 / RK3588）—— 这两个不是 *simple* 控件，`sset` 会报
`Unable to find simple control`，必须用 `cset`：

```sh
amixer -c 0 cset name='OUT1 Switch' 1     # 喇叭 / 线路输出
amixer -c 0 cset name='OUT2 Switch' 1     # 耳机
# 等价的按编号写法：amixer -c 0 cset numid=80 1 / numid=81 1
```

然后播放测试（`retroarch` 会独占设备，先停掉）：

```sh
systemctl stop retroarch
speaker-test -D plughw:0,0 -c 2 -t sine -l 2
```

> **RK809 的一个坑**：`Playback Path` 的驱动实现里，值没变化就直接返回、不写寄存器
> （`rk817_playback_path_put()` 的同值短路）。而 DAPM 每次 PCM 上电都会把输出级写回
> class-D off / DACD down，所以如果你设过一次 `SPK_HP` 之后又没声音了，**先设 `OFF`
> 再设回去**即可重新上电：
>
> ```sh
> amixer -c 0 sset 'Playback Path' OFF
> amixer -c 0 sset 'Playback Path' SPK_HP
> ```
>
> 本分支的镜像已经通过内核补丁从根本上修掉这个问题（见下）。

### 永久生效（不改镜像）

```sh
mkdir -p /storage/.config
alsactl store -f /storage/.config/sound.conf
```

`/storage/.config/sound.conf` 会被 udev 的 `90-alsa-restore.rules` 在每次声卡出现时
`alsactl restore`，所以重启后仍然有效。

RetroArch 音量单独改（改之前先 `systemctl stop retroarch`，否则退出时会被写回）：

```sh
sed -i 's/^audio_volume = .*/audio_volume = "1.000000"/' /storage/.config/retroarch/retroarch.cfg
systemctl start retroarch
```

### 镜像内已内置的默认初始化

本分支包含 `projects/Rockchip/packages/rk-audio-default/`：

- `rk-audio-default.service`（oneshot，`After=sound.target`）在声卡注册后执行
  `/usr/bin/rk-audio-default`；
- 脚本遍历 `/proc/asound/card[0-9]*`，跳过 HDMI/DP 声卡，然后按 codec 名称设置：
  RK809 → `Playback Path=SPK_HP`，ES8388 → `OUT1/OUT2 Switch=1`，
  控件不存在时静默跳过，所以同一个镜像服务所有板卡；
- 配套内核补丁 `rockchip-9006-audio-rk817-reapply-playback-path.patch`：
  在 `rk817_codec_power_up()` 的 playback 分支末尾按当前 `playback_path`
  重新应用一次，解决"只有第一次播放有声"。

四个芯片的 `options` 都已把 `rk-audio-default` 加进 `ADDITIONAL_PACKAGES`，
正常情况下**刷完即有声音**，不需要手动 `amixer`。

### 硬件提醒

RK809 内置 class-D 是按 **8Ω** 负载设计的。接 4Ω 3W 这类喇叭属于超规格，
可能出现音量偏小、失真或触发过流保护（表现为断续/无声）。优先用 8Ω 2W 的喇叭；
如果只能用低阻喇叭，建议把 `DAC Playback Volume` 控制在 200 左右（约 -10dB）以内。

## 游戏机核心（libretro cores）配置

Lakka 的每个「游戏机」对应一个 libretro 核心（源码目录 `packages/lakka/libretro_cores/<核心名>/`），
编译出的 `<核心名>_libretro.so` 随 SYSTEM 分区一起打进镜像（镜像内路径 `/usr/lib/libretro/`）。
**没进镜像就玩不了对应机种**，所以核心清单就是「镜像体积 / 编译时间」和「能玩的机种」之间的取舍。

本分支默认沿用「主流现代机种 + 少量按需保留」的清单，剔掉老式电脑、上古主机、自研小游戏等编译耗时长、
实际又用不到的核心。

### 当前规模

| 项 | 数量 |
| --- | --- |
| 上游核心全集 | **182**（`packages/lakka/libretro_cores/package.mk` 的 `LIBRETRO_CORES`） |
| 设备 `options` 排除 | **84**（`EXCLUDE_LIBRETRO_CORES="…"`） |
| Rockchip 项目追加排除 | **1**（`lr_moonlight`，`libretro_cores/package.mk` 里按 `${PROJECT}` = Rockchip 追加） |
| 正式镜像内实际核心 | 约 **97** |

RK3588 / RK3576 / RK3566 / RK3568 四个芯片共用**同一份**排除清单（内容逐字相同）。

### 清单在哪、怎么改

| 位置 | 作用 |
| --- | --- |
| `projects/Rockchip/devices/<CHIP>/options` 的 `EXCLUDE_LIBRETRO_CORES="…"` | 唯一生效的排除清单，空格分隔，写核心目录名 |
| `packages/lakka/libretro_cores/package.mk` 的 `LIBRETRO_CORES` | 上游全集；文件末尾按排除清单逐项 `LIBRETRO_CORES//" ${core} "/` 剔除，结果作为 `PKG_DEPENDS_TARGET` |
| `projects/Rockchip/devices/<CHIP>/CORES.md` | 逐核心对照表（机种分类 / 建议保留或裁掉 / 备注），挑核心先看它 |
| `projects/Rockchip/tools/cores-subset.sh` | 小工具：不带参数列出全部核心名；带保留名单时输出「除保留项之外」的清单 |

**增 / 减一个机种**：

1. 在 `CORES.md` 里查到核心名（与目录名、package 名一致，例如 `flycast`、`beetle_pce`）；
2. 编辑该芯片 `options` 的 `EXCLUDE_LIBRETRO_CORES`：要**加回来**就从清单里删掉这个名字，要**裁掉**就加进去；
3. 重新构建 —— 清单参与构建计划生成，**必须走 `make image`**（`build-board.sh` 就是），
   不能只重打 `update.img`。

```sh
# 例：把 Dreamcast（flycast）加回来、把 PC Engine（beetle_pce）去掉之后
./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5
```

### 只想编少量核心（移植验证 / 快速迭代）

`options` 里这份清单的写法是 `${EXCLUDE_LIBRETRO_CORES:-} …`（**保留继承值**），所以可以从命令行**追加**
排除项，配合 `cores-subset.sh` 生成「除保留名单之外的全部核心」：

```sh
# 只留 3 个轻量核心：首次全量构建约 6h → 约 3.5h（4 核构建机实测）
EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
  ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1

# 只砍最重的几个（实测 mame 单包约 2h；其余重核按构建目录体积排：ppsspp 2.7G / citra 2.1G / scummvm 1.7G …）
EXCLUDE_LIBRETRO_CORES="mame mame2015 mame2010 ppsspp citra scummvm panda3ds flycast" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2
```

> 这种「冒烟镜像」只用于验证移植链路（开机 / HDMI / 串口 / 手柄 / 扩容），**不要当正式版发布**；
> 去掉该环境变量再跑一次 `make image`，缺的核心会增量补回来（其余包命中缓存，不用重编）。

### 注意

- 裁剪只影响镜像里带哪些核心；RetroArch 本体、界面、缩略图 / 金手指等资源不受影响。
- 核心名写错**不会报错**（只是没生效）。核对镜像里真实装进去的核心：

  ```sh
  unsquashfs -ll target/*.system | grep 'usr/lib/libretro/'
  # 数个数
  unsquashfs -ll target/*.system | grep -c 'usr/lib/libretro/.*\.so'
  ```

  不要用 `ls $BUILD/image/system/usr/lib/libretro/` 判断 —— `image/system` 里是绝对符号链接，
  会穿透到宿主机上的同名路径，结果不可信。
- 想要**全部机种**：把该芯片 `options` 的 `EXCLUDE_LIBRETRO_CORES` 置成空串（`EXCLUDE_LIBRETRO_CORES=""`）即可；
  但 A53 / A72 这类平台跑全量核心意义不大，构建时间也会明显拉长。

## 设备树配置

Lakka的`/flash`目录存储着当前使用的设备树，而`/flash/extlinux/extlinux.conf`则配置了当前正在使用的设备树。要修改的话需要先执行`mount -o remount,rw /flash`令`/flash`分区可写。`/usr/share/bootloader`存放了编译好的设备树，他们不一定被使用。

## Support

* [FAQ](https://github.com/libretro/Lakka-LibreELEC/wiki/FAQ)
* #lakkatv on irc.libera.chat
* [Discord](https://discord.gg/BNFR4hM)
* [Forums](https://forums.libretro.com/c/libretro/lakka-tv-general)
