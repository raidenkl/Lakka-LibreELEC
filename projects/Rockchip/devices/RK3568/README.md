# RK3568 / LubanCat 2 / 2N / 2-V1 / 2-V2 / 2-V3 (野火鲁班猫2)（Lakka）

> 芯片 = 目录名（DEVICE=`RK3568`）；板卡 = `UBOOT_SYSTEM`，板卡表在仓库 `scripts/uboot_helper`。
> 与 RK3576（鲁班猫3）/ RK3588 共用同一套 vendor 链：LubanCat u-boot 2017.09 + vendor BSP 内核 6.1 + rkbin + libmali G52 blob。

## 关键参数

| 项 | 值 | 说明 |
| --- | --- | --- |
| SoC | 4× Cortex-A55 | `TARGET_CPU="cortex-a55"`（`config/arch.aarch64` 白名单已含） |
| GPU | Mali-G52 Bifrost g13p0 | `libmali-bifrost-g52-g13p0-gbm_1.9-1`，无 Vulkan |
| 内核 | 6.1.99 `-rk356x` | 配置源 `lubancat_linux_rk356x_defconfig`，只补 zstd / 关 WERROR |
| 引导 | Rockchip FIT 链 | loader@32KiB（idblock）+ uboot.img@8MiB（FIT，内含 BL31/BL32） |
| 串口 | UART2 `0xFE660000` → `/dev/ttyFIQ0` | 1500000 8N1，开箱就是 root shell |
| DDR | `rk3568_ddr_1560MHz_v1.23.bin` | 默认 1560MHz（厂商 ini 原值），`DDR_FREQ=` 可覆盖（920 / 1056 / 1332 / 1560） |
| BL31/BL32 | `RK3568TRUST.ini` | 直接用 `RK3568TRUST.ini` |
| HDMI | `hdmi@fe0a0000` / `route-hdmi` / `hdmi-sound` | 板级 dts 里已是 okay，**不需要像 RK3588 那样打补丁** |

## 板卡

| UBOOT_SYSTEM | 型号 | 内核 dtb | u-boot defconfig |
| --- | --- | --- | --- |
| `lubancat-2` | 鲁班猫 2 | `rk3568-lubancat-2.dtb` | `lubancat-rk3568-pcie_defconfig` |
| `lubancat-2-v1` | 鲁班猫 2 V1 | `rk3568-lubancat-2-v1.dtb` | `lubancat-rk3568-pcie_defconfig` |
| `lubancat-2-v2` | 鲁班猫 2 V2 | `rk3568-lubancat-2-v2.dtb` | `lubancat-rk3568-pcie_defconfig` |
| `lubancat-2-v3` | 鲁班猫 2 V3 | `rk3568-lubancat-2-v3.dtb` | `lubancat-rk3568-pcie_defconfig` |
| `lubancat-2n` | 鲁班猫 2N | `rk3568-lubancat-2n.dtb` | `lubancat-rk3568-pcie_defconfig` |

u-boot 侧厂商只提供 `rk3568-lubancat-2.dts`，同芯片各板共用（u-boot 只用到 DDR/MMC/串口）；内核 dtb 仍按板区分。

## 构建

```sh
# 首次为全量构建（约 6-7h）；同一芯片换板约 13 分钟
./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2

# update.img 会在构建成功后自动打包；也可单独重打：
#   ./projects/Rockchip/devices/RK3568/tools/mk-rockchip-update.sh --board lubancat-2
# 刷写：SD 卡用 Rockchip SD_Firmware_Tool（「SD启动」），eMMC 用 RKDevTool（「升级固件」）
# 注意：img.gz 只是构建中间产物，别把 .gz 原样写到卡上（会得到一张不启动的卡）
```

快速验证可以用核心裁剪缩短首次构建（详见仓库根 `projects/Rockchip/tools/cores-subset.sh`）：

```sh
EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2
```

## 上机注意

- 刷完请**彻底断电 10 秒再上电**（RKDevTool 的「重启设备」不是真正断电，个别情况下首次启动会卡在 eMMC 初始化）。
- 串口应依次看到：DDR 频点行 → `U-Boot 2017.09` → `Found /extlinux/extlinux.conf` → `Machine model: 鲁班猫 2` → `bound fe0a0000.hdmi` → `Lakka (community) …`。
- `/storage` 首次启动自动扩容（`fs-resize` 已适配 Rockchip 的 p3 布局）。
