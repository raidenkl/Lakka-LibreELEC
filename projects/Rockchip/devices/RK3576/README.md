# Lakka for Rockchip RK3576 — 野火鲁班猫 3 / 3IO

本目录是 **RK3576** 设备定义。构建系统按 `DEVICE=RK3576` 自动发现它，并使用独立的构建目录
`build.Lakka-RK3576.aarch64/`（与 RK3588 设备完全隔离，可共存）。

| 项 | 值 |
| --- | --- |
| SoC | RK3576，**4× Cortex-A72 + 4× Cortex-A53**（big.LITTLE） |
| GPU | Mali-G52（Bifrost），Rockchip libmali 闭源 blob（g13p0 / gbm 变体） |
| 内核 | LubanCat vendor BSP 6.1（`LubanCat/kernel` @ `1bc19c52`，与 RK3588 同一棵统一内核） |
| 引导 | Rockchip FIT 链：SPL loader @32 KiB + `uboot.img`(U-Boot + BL31/BL32) @8 MiB |
| 串口 | UART2 → `/dev/ttyFIQ0`（fiq_debugger），**1500000 8N1**，内置 root shell |

## 支持的板卡

| 板卡（UBOOT_SYSTEM） | dtb | u-boot defconfig | dtb model |
| --- | --- | --- | --- |
| `lubancat-3` | `rk3576-lubancat-3.dtb` | `lubancat-rk3576-msata_defconfig` | `EmbedFire LubanCat-3` |
| `lubancat-3io` | `rk3576-lubancat-3io.dtb` | 同上（共用） | `EmbedFire LubanCat-3IO` |

## 快速开始

```sh
# 宿主依赖（首次使用请先跑一次）
./scripts/checkdeps

# 选板构建（产物在 target/）
./projects/Rockchip/tools/build-board.sh RK3576 lubancat-3
./projects/Rockchip/tools/build-board.sh RK3576 lubancat-3io   # 同核不同 dtb，增量很快

# 打成 RKDevTool / upgrade_tool 用的 update.img（eMMC 刷写）
./projects/Rockchip/devices/RK3576/tools/mk-rockchip-update.sh --board lubancat-3
```

`build-board.sh` 会在构建结束后自动做产物断言：dtb 的 `model`、`hdmi@27da0000` /
`route-hdmi` 是否 `okay`、`rockchip-hdmi` 声卡节点、引导布局魔数（32 KiB `4c445220`、
8 MiB `d00dfeed`）与 sha256。任何一项不符会明确报错。

## 相对 RK3588 设备的差异（为何不能直接套用）

| 项 | RK3588（鲁班猫 4/5） | RK3576（鲁班猫 3） |
| --- | --- | --- |
| `TARGET_CPU` | `cortex-a76.cortex-a55` | **`cortex-a72.cortex-a53`**（同样是 big.LITTLE） |
| `MALI_FAMILY` / blob | `g610`（Valhall / g24p0） | **`g52`（Bifrost / g13p0）** |
| GPU 固件 | 需要 `mali_csffw.bin`（CSF 架构） | **不需要**（Bifrost 固件内置于 kbase 驱动） |
| libmali shim | 含 `libMaliVulkan` | **无 Vulkan**（该 blob 早于 Vulkan） |
| 显示路由 | 板级 dts 里被注释，需补丁 9000–9002 | **开箱即用，无需补丁**（`rk3576-lubancat-3.dts` 已 `okay`） |
| HDMI 节点名 | `hdmi@fde80000` / `route-hdmi0` / `rockchip-hdmi0` | **`hdmi@27da0000` / `route-hdmi` / `rockchip-hdmi`**（无 `0` 后缀） |
| debug UART | `0xFEB50000` | **`0x2ad40000`**（vendor defconfig 自带，`bootloader/config` 里**不要**覆盖） |
| DDR 默认 | **全系 1848 MHz** | **1560 MHz**（`package.mk` 里 sed ini；`DDR_FREQ` 可覆盖） |

libmali 取的是 tsukumijima `v1.9-1-20260312-bd33ee2` 的
`libmali-bifrost-g52-g13p0-gbm`（与 LubanCat SDK 给 G52 板卡配的 DDK 版本一致）。
注意**不要**改用最新 release 的 g13p0 资产——那里只有 `dummy-*` 变体。该 deb 不含
`usr/include`，Khronos 头文件（EGL/GLES/GLES2/GLES3/KHR）已随包 vendor 在
`packages/libmali/include/`；`unpack()` 用 `dpkg-deb -x` 解包（LibreELEC 的
`scripts/extract` 不认 `.deb`）。

## DDR 频率（默认 1560MHz）

`packages/u-boot/package.mk` 会把 `RK3576MINIALL.ini` 里的 DDR blob 切到
`rk3576_ddr_lp4_1560MHz_lp5_2736MHz_v1.09.bin`。ini 的原始值 1848MHz 在鲁班猫3 上也能
训练并启动（已上机验证），但不是这块板的舒适频点，故不做默认。改频点不用动代码：

```sh
DDR_FREQ=1848 projects/Rockchip/tools/build-board.sh RK3576 lubancat-3
```

备选 bin 顺序（只有上电串口**完全没有 DDR 打印** = loader 没跑时才需要试）：

```
1560（默认） → 1848 → 2112 → 2112-eyescan → 2112-ultra
```

## 刷机

```sh
# SD 卡直写
gzip -dc target/Lakka-RK3576.aarch64-*-lubancat-3.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# eMMC：RKDevTool「升级固件」加载 update.img，或
sudo upgrade_tool uf target/Lakka-RK3576.aarch64-*-lubancat-3-update.img
```

## 上机验证清单

1. **串口（1500000 8N1）**：出现 DDR 初始化打印（含频率）→ 与所烧 bin 一致
2. `U-Boot 2017.09 … lubancat-rk3576-msata` 出现，**5 秒 `Hit any key to stop autoboot`** 可中断
3. 内核起来后串口直接是 **root shell**（`ttyFIQ0-console.service`，见 `packages/rk-serial-console`）
4. **HDMI 出图**（Lakka 主界面）；`ls /dev/dri/card0` 存在；dmesg 无 `No crtc register`
5. **GPU**：`dmesg | grep -i mali` 无 probe 失败；跑一个 3D 核心或 `es2_info` 确认 libmali 加载
6. **首启自动扩容**：`df -h /storage` 应吃满 SD/eMMC（`fs-resize` 已适配 p3 布局）
7. SSH 可用（Lakka 里打开 SSH 后）
8. HDMI 音频（`rockchip-hdmi` 声卡已 enable）

## 相关文档

- 通用构建/排错手段（网络、依赖、串口、update.img、缓存预置等）与 RK3588 完全共用：
  见 [`../RK3588/README.md`](../RK3588/README.md) 与 [`../RK3588/BUILD_GUIDE.md`](../RK3588/BUILD_GUIDE.md)
- 国内网络一键配置：`./projects/Rockchip/tools/setup-cn-network.sh`
- 核心裁剪说明与完整核心对照表：同目录 `CORES.md`（与 RK3588 同表）
