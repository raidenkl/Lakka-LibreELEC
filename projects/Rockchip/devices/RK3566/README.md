# RK3566 / LubanCat 0 / 1 / 1N (野火鲁班猫 Zero / 1 / 1N)（Lakka）

> 芯片 = 目录名（DEVICE=`RK3566`）；板卡 = `UBOOT_SYSTEM`，板卡表在仓库 `scripts/uboot_helper`。
> 与 RK3576（鲁班猫3）/ RK3588 共用同一套 vendor 链：LubanCat u-boot 2017.09 + vendor BSP 内核 6.1 + rkbin + libmali G52 blob。

## 关键参数

| 项 | 值 | 说明 |
| --- | --- | --- |
| SoC | 4× Cortex-A55 | `TARGET_CPU="cortex-a55"`（`config/arch.aarch64` 白名单已含） |
| GPU | Mali-G52 Bifrost g13p0 | `libmali-bifrost-g52-g13p0-gbm_1.9-1`，无 Vulkan |
| 内核 | 6.1.99 `-rk356x` | 配置源 `lubancat_linux_rk356x_defconfig`，只补 zstd / 关 WERROR |
| 引导 | Rockchip FIT 链 | loader@32KiB（idblock）+ uboot.img@8MiB（FIT，内含 BL31/BL32） |
| 串口 | UART2 `0xFE660000` → `/dev/ttyFIQ0` | 1500000 8N1，开箱就是 root shell |
| DDR | `rk3566_ddr_1056MHz_v1.23.bin` | 默认 1056MHz（厂商 ini 原值），`DDR_FREQ=` 可覆盖（528 / 780 / 920 / 1056） |
| BL31/BL32 | 借用 `RK3568TRUST.ini` | rkbin 里没有 `RK3566TRUST.ini`，一律回落到 `RK3568TRUST.ini`（同一颗 vendor 芯片族，厂商也只用这一份 BL31/BL32） |
| HDMI | `hdmi@fe0a0000` / `route-hdmi` / `hdmi-sound` | 板级 dts 里已是 okay，**不需要像 RK3588 那样打补丁** |

## 板卡

| UBOOT_SYSTEM | 型号 | 内核 dtb | u-boot defconfig |
| --- | --- | --- | --- |
| `lubancat-0` | 鲁班猫 0 / Zero | `rk3566-lubancat-0.dtb` | `lubancat-rk3566-msata_defconfig` |
| `lubancat-1` | 鲁班猫 1 | `rk3566-lubancat-1.dtb` | `lubancat-rk3566-msata_defconfig` |
| `lubancat-1n` | 鲁班猫 1N | `rk3566-lubancat-1n.dtb` | `lubancat-rk3566-msata_defconfig` |

u-boot 侧厂商只提供 `rk3566-lubancat-1-msata.dts`，同芯片各板共用（u-boot 只用到 DDR/MMC/串口）；内核 dtb 仍按板区分。

## 构建

```sh
# 首次为全量构建（约 6-7h）；同一芯片换板约 13 分钟
./projects/Rockchip/tools/build-board.sh RK3566 lubancat-0

# update.img 会在构建成功后自动打包；也可单独重打：
#   ./projects/Rockchip/devices/RK3566/tools/mk-rockchip-update.sh --board lubancat-0
# 刷写：SD 卡用 Rockchip SD_Firmware_Tool（「SD启动」），eMMC 用 RKDevTool（「升级固件」）
# 注意：img.gz 只是构建中间产物，别把 .gz 原样写到卡上（会得到一张不启动的卡）
```

快速验证可以用核心裁剪缩短首次构建（详见仓库根 `projects/Rockchip/tools/cores-subset.sh`）：

```sh
EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
  ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-0
```

## 上机注意

- 刷完请**彻底断电 10 秒再上电**（RKDevTool 的「重启设备」不是真正断电，个别情况下首次启动会卡在 eMMC 初始化）。
- 串口应依次看到：DDR 频点行 → `U-Boot 2017.09` → `Found /extlinux/extlinux.conf` → `Machine model: 鲁班猫 0 / Zero` → `bound fe0a0000.hdmi` → `Lakka (community) …`。
- `/storage` 首次启动自动扩容（`fs-resize` 已适配 Rockchip 的 p3 布局）。
