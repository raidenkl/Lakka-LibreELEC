# Lakka（RK3588 / 鲁班猫5）镜像内 libretro 核心对照表

本设备当前进镜像的核心 **172 个**（数据来源：`build.Lakka-RK3588.aarch64/.threads/plan` 里  
`install libretro_cores` 的 wants；说明取自各包的 `PKG_LONGDESC`）。

去掉核心的方法（详见 `BUILD_GUIDE.md` §11.6）：在 `projects/Rockchip/devices/RK3588/options` 里加一行

```sh
EXCLUDE_LIBRETRO_CORES="core1 core2 core3"
```

> **核心名必须精确**：写错的名字会被静默忽略、不报错。删完务必重新生成清单并 `diff` 核对  
> （方法见 BUILD_GUIDE §11.4）。核心之间**互不依赖**，删任何一个都不会破坏别的。

---

## 1. 任天堂系

| 核心名                  | 机种 / 说明                    | 备注          |
| -------------------- | -------------------------- | ----------- |
| `fceumm`             | NES / Famicom（FCEUmm）      |             |
| `nestopia`           | NES / Famicom（NEStopia）    |             |
| `quicknes`           | NES / Famicom（QuickNES，轻量） | 与上两条重复实现    |
| `bnes`               | NES / Famicom（bNES/higan）  | 与上三条重复实现    |
| `mesen`              | NES / Famicom（Mesen，高精度）   |             |
| `snes9x`             | SNES / Super Famicom（主力）   | 建议保留        |
| `snes9x2010`         | SNES（2010 版，快）             |             |
| `snes9x2005`         | SNES（2005 版，ARM 优化）        |             |
| `snes9x2005_plus`    | SNES（2005 版 + BLARGG APU）  |             |
| `snes9x2002`         | SNES（2002 版，最轻）            |             |
| `bsnes`              | SNES（bsnes，精确）             |             |
| `bsnes2014`          | SNES（bsnes 2014 分支）        |             |
| `bsnes_hd`           | SNES（bsnes + HD 视频特性）      |             |
| `bsnes_jg`           | SNES（cycle-accurate）       |             |
| `bsnes_mercury`      | SNES（恢复 HLE DSP）           |             |
| `beetle_bsnes`       | SNES（Mednafen bSNES）       |             |
| `beetle_supafaust`   | SNES（面向 ARM 多核优化）          |             |
| `higan_sfc`          | SNES（higan 多机种）            |             |
| `higan_sfc_balanced` | SNES（higan 平衡分支）           |             |
| `mesen_s`            | SNES（Mesen-S）              |             |
| `mupen64plus_next`   | N64（GLideN64 + RSP-HLE）    | 建议保留        |
| `parallel_n64`       | N64（重写优化版）                 |             |
| `dolphin`            | GameCube / Wii             | **大件，编译很慢** |
| `gambatte`           | GB / GBC（主力）               | 建议保留        |
| `sameboy`            | GB / GBC（高精度）              |             |
| `gearboy`            | GB / GBC                   |             |
| `tgbdual`            | GB / GBC（支持联机）             |             |
| `doublecherrygb`     | GB（最多 16 人 + 宝可梦配信）        |             |
| `boytacean`          | GB（Rust 实现）                |             |
| `mgba`               | GBA（主力）                    | 建议保留        |
| `mgba_fork`          | GBA（mGBA 分支）               |             |
| `gpsp`               | GBA（gpSP，快）                |             |
| `skyemu`             | GBA / GB / GBC / NDS（多合一）  |             |
| `vbam`               | GBA（VBA-M）                 |             |
| `desmume`            | NDS                        |             |
| `desmume_2015`       | NDS（2015 版分支）              |             |
| `melonds`            | NDS（melonDS）               | 建议保留        |
| `melondsds`          | NDS（melonDS 重制）            |             |
| `noods`              | NDS（NooDS）                 |             |
| `citra`              | 3DS                        | **大件**      |
| `azahar`             | 3DS（Citra 后继）              | **大件**      |
| `panda3ds`           | 3DS（HLE）                   | **大件**      |
| `beetle_vb`          | Virtual Boy                | 极冷门         |
| `pokemini`           | Pokémon Mini               | 极冷门（无彩色）    |

## 2. 世嘉系

| 核心名                    | 机种 / 说明                                 | 备注   |
| ---------------------- | --------------------------------------- | ---- |
| `genesis_plus_gx`      | MD/Genesis + SMS/GG/SG-1000/Sega CD（主力） | 建议保留 |
| `genesis_plus_gx_wide` | 同上（宽屏版）                                 |      |
| `picodrive`            | MD/Genesis/SMS/GG/Sega CD/32X           |      |
| `blastem`              | MD/Genesis（fast & accurate）             |      |
| `gearsystem`           | SMS / Game Gear / SG-1000               |      |
| `emux_sms`             | 多机种（Emux）                               |      |
| `clownmdemu`           | MD（ClownMDEmu 前端）                       | 冷门   |
| `beetle_saturn`        | Sega Saturn（Mednafen）                   | 建议保留 |
| `yabause`              | Sega Saturn（老实现）                        |      |
| `yabasanshiro`         | Sega Saturn（YabaSanshiro）               |      |
| `flycast`              | Dreamcast（含 Naomi 街机）                   | 建议保留 |

## 3. 索尼系

| 核心名            | 机种 / 说明                 | 备注              |
| -------------- | ----------------------- | --------------- |
| `beetle_psx`   | PlayStation 1（Mednafen） | 建议保留            |
| `pcsx_rearmed` | PS1（ARM 优化，性能好）         | 建议保留            |
| `swanstation`  | PS1（DuckStation）        |                 |
| `rustation_ng` | PS1（Rust 实现）            | 冷门              |
| `lrps2`        | PlayStation 2（PCSX2 移植） | **大件、可能要 BIOS** |
| `play`         | PlayStation 2（Play!）    | **大件**          |
| `ppsspp`       | PSP                     | **大件**          |

## 4. 雅达利系

| 核心名             | 机种 / 说明                          | 备注       |
| --------------- | -------------------------------- | -------- |
| `stella`        | Atari 2600                       | 极老（1977） |
| `stella2014`    | Atari 2600（2014 移植）              | 与上重复     |
| `a5200`         | Atari 5200                       | 极老（1982） |
| `prosystem`     | Atari 7800（注意：包名不叫 atari7800）    | 极老（1986） |
| `virtualjaguar` | Atari Jaguar                     | 冷门       |
| `handy`         | Atari Lynx（掌机）                   | 极冷门      |
| `beetle_lynx`   | Atari Lynx（Mednafen）             |          |
| `gearlynx`      | Atari Lynx（含调试器）                 |          |
| `atari800`      | Atari 8-bit 电脑（400/800/XL/XE）    | 极老       |
| `hatari`        | Atari ST / STE / TT / Falcon（电脑） |          |

## 5. 其他家用机 / 街机

| 核心名                 | 机种 / 说明                                 | 备注           |
| ------------------- | --------------------------------------- | ------------ |
| `beetle_pce`        | PC Engine / TurboGrafx-16 / CD-ROM²     | 建议保留         |
| `beetle_pce_fast`   | PC Engine（快版）                           |              |
| `beetle_supergrafx` | SuperGrafx                              |              |
| `geargrafx`         | PCE / TG-16 / SuperGrafx / CD-ROM²      |              |
| `beetle_pcfx`       | PC-FX                                   | 极冷门          |
| `geolith`           | Neo Geo AES / MVS（高精度）                  |              |
| `neocd`             | Neo Geo CD                              |              |
| `mame`              | 街机（MAME 当前版）                            | **大件，编译极慢**  |
| `mame2010`          | 街机（MAME 0.139）                          | **大件**       |
| `mame2015`          | 街机（MAME 0.160）                          | **大件**       |
| `mame2003_plus`     | 街机（MAME 2003-Plus，最常用）                  | 建议保留（中等）     |
| `mame2000`          | 街机（MAME 0.37b5，极老 ROM 集）                |              |
| `fbneo`             | 街机（FinalBurn Neo，最常用）                   | 建议保留         |
| `fbalpha2012`       | 街机（FinalBurn Alpha 2012）                |              |
| `same_cdi`          | Philips CD-i                            | 冷门           |
| `opera`             | 3DO                                     |              |
| `gearcoleco`        | ColecoVision                            | 老（1982）      |
| `jollycv`           | ColecoVision / CreatiVision / My Vision | 冷门           |
| `freeintv`          | Mattel Intellivision                    | 极老（1979）     |
| `freechaf`          | Fairchild Channel F                     | 极老（1976）     |
| `o2em`              | Magnavox Odyssey² / Videopac            | 极老（1978）     |
| `vecx`              | Vectrex                                 | 极老（1982）     |
| `amiarcadia`        | Signetics 2650 平台（Arcadia 2001 等）       | 极冷门；本包刚做过源修复 |
| `pd777`             | Epoch Cassette Vision                   | 极冷门          |
| `daphne`            | 激光影碟游戏（含大量 ROM 依赖）                      |              |
| `dirksimple`        | Dragon's Lair 播放器                       | 冷门           |
| `cannonball`        | OutRun 街机（引擎重制）                         |              |
| `dice`              | 无 CPU 的离散逻辑游戏（Pong 类）                   | 极冷门          |

## 6. 掌机（非任/世嘉）

| 核心名            | 机种 / 说明                | 备注       |
| -------------- | ---------------------- | -------- |
| `beetle_wswan` | Bandai WonderSwan      |          |
| `beetle_ngp`   | Neo Geo Pocket         | 建议保留     |
| `race`         | Neo Geo Pocket / Color |          |
| `potator`      | Watara Supervision     | 极冷门      |
| `gw_libretro`  | Game & Watch           | 极老（1980） |
| `tamalibretro` | Tamagotchi P1（电子宠物）    | 玩具       |
| `sameduck`     | Mega Duck              | 极冷门      |
| `ardens`       | Arduboy FX（模拟器/调试器）    | 小众       |
| `mu`           | Palm OS                | 冷门       |

## 7. 老式电脑

| 核心名             | 机种 / 说明                                     | 备注       |
| --------------- | ------------------------------------------- | -------- |
| `fuse_libretro` | ZX Spectrum                                 | 老（1982）  |
| `81`            | ZX81（EightyOne）                             | 极老（1981） |
| `cap32`         | Amstrad CPC（caprice32）                      | 老（1984）  |
| `crocods`       | Amstrad CPC                                 | 重复实现     |
| `vice`          | Commodore 8-bit（C64 / VIC20 / PET / Plus4…） | 建议保留     |
| `bluemsx`       | MSX / MSX2                                  |          |
| `fmsx`          | MSX                                         | 重复实现     |
| `puae`          | Amiga                                       | 建议保留     |
| `puae2021`      | Amiga（旧版分支，性能更好）                            | 重复实现     |
| `uae4arm`       | Amiga（ARM 优化）                               | 重复实现     |
| `amiberry`      | Amiga（优化版）                                  | 重复实现     |
| `dosbox`        | DOS（libretro 包装）                            |          |
| `dosbox_pure`   | DOS（易用、兼容性好）                                | 建议保留     |
| `dosbox_core`   | DOS（core 版）                                 | 重复实现     |
| `dosbox_svn`    | DOS（上游移植）                                   | 重复实现     |
| `px68k`         | Sharp X68000                                | 极冷门（日本）  |
| `np2kai`        | NEC PC-98                                   | 冷门（日本）   |
| `meowpc98`      | NEC PC-98（Neko Project 2 移植）                | 重复实现     |
| `quasi88`       | NEC PC-8800                                 | 极冷门（日本）  |
| `xmil`          | Sharp X1                                    | 极冷门（日本）  |
| `m2000`         | Philips P2000                               | 极冷门      |
| `theodore`      | Thomson MO/TO                               | 极冷门（法国）  |
| `ep128emu`      | Enterprise 128                              | 极冷门（匈牙利） |
| `virtualxt`     | IBM PC/XT                                   |          |
| `b2`            | BBC Micro                                   | 老（1981）  |
| `applewin`      | Apple II                                    | 老（1977）  |
| `gam4980`       | 文曲星/BBK 4980 电子词典                           | 玩具       |

## 8. 游戏引擎 / 自研游戏（不是模拟器，按需取舍）

| 核心名            | 说明                              | 备注          |
| -------------- | ------------------------------- | ----------- |
| `prboom`       | Doom                            | 建议保留        |
| `boom3`        | Doom 3                          | 大件          |
| `tyrquake`     | Quake 1                         |             |
| `vitaquake2`   | Quake II                        |             |
| `vitaquake3`   | Quake III                       |             |
| `ecwolf`       | Wolfenstein 3D                  | （官方描述为空）    |
| `openlara`     | 古墓丽影（引擎重制）                      |             |
| `reminiscence` | Flashback                       |             |
| `doukutsu_rs`  | 洞窟物语（Rust 重制）                   |             |
| `nxengine`     | 洞窟物语（引擎克隆）                      | 重复实现        |
| `xrick`        | Rick Dangerous                  |             |
| `scummvm`      | 经典点击式冒险游戏引擎（LucasArts/Sierra 等） | **大件，建议保留** |
| `easyrpg`      | RPG Maker 2000/2003 游戏          |             |
| `dinothawr`    | 推箱子解谜（Lakka 自带）                 | 自带          |
| `mrboom`       | 炸弹人克隆（最多 8 人）                   |             |
| `jumpnbump`    | Jump 'n Bump                    |             |
| `superbroswar` | Super Bros War（对战）              |             |
| `thepowdertoy` | The Powder Toy（物理沙盒）            |             |
| `craft`        | Minecraft 克隆（C + 现代 OpenGL）     |             |
| `anarch`       | 极简 FPS                          |             |
| `2048`         | 2048 益智游戏                       |             |
| `lutro`        | Lua 游戏框架                        |             |
| `chailove`     | ChaiLove 2D 游戏框架                |             |
| `pzretro`      | PuzzleScript 游戏                 |             |
| `mojozork`     | Z-Machine 文字冒险解释器               |             |

## 9. 幻想主机 / 可编程平台 / 玩具

| 核心名         | 说明                        | 备注   |
| ----------- | ------------------------- | ---- |
| `tic80`     | TIC-80 幻想主机               |      |
| `wasm4`     | WASM-4（WebAssembly 幻想主机）  |      |
| `vircon32`  | Vircon32 虚拟主机             |      |
| `lowres_nx` | LowRes NX（BASIC 可编程）      |      |
| `uzem`      | Uzebox（ATMega644 开源主机）    |      |
| `retro8`    | PICO-8 实现                 |      |
| `fake_08`   | PICO-8 播放器/模拟器            | 重复实现 |
| `jaxe`      | CHIP-8 / S-CHIP / XO-CHIP |      |
| `pocketcdg` | CD+G 卡拉OK 播放器             |      |
| `gme`       | 游戏音乐播放（Game_Music_Emu）    |      |
| `numero`    | TI-83 图形计算器               |      |

---

## 快速裁剪建议

**A. 「只要主流现代机种」**（去掉 1970–80 年代老机种 + 冷门电脑 + 小众平台）

```sh
EXCLUDE_LIBRETRO_CORES="\
stella stella2014 a5200 prosystem virtualjaguar handy beetle_lynx gearlynx atari800 \
freeintv freechaf o2em vecx amiarcadia pd777 gearcoleco jollycv \
fuse_libretro 81 cap32 crocods bluemsx fmsx b2 applewin m2000 theodore ep128emu \
xmil quasi88 np2kai meowpc98 px68k gam4980 \
potator gw_libretro tamalibretro sameduck mu ardens \
beetle_vb pokemini \
tic80 wasm4 vircon32 lowres_nx uzem retro8 fake_08 jaxe pocketcdg gme numero \
2048 dinothawr mrboom jumpnbump superbroswar thepowdertoy craft anarch lutro chailove \
pzretro mojozork xrick dirksimple dice cannonball clownmdemu emux_sms"
```

**B. 顺带砍掉编译最慢的大件**（构建时间收益最大，但功能损失也明显）

```sh
EXCLUDE_LIBRETRO_CORES+=" mame mame2010 mame2015 dolphin lrps2 play ppsspp citra azahar panda3ds boom3"
```

> 另外 `mame2003_plus` / `fbneo` 是绝大多数街机 ROM 的实际主力，建议**留着**；  
> 若删 `mame`，`same_cdi`（CD-i）仍可独立工作（核心之间无依赖，已实测）。

**C. 只去掉某个具体机种**（最安全）

```sh
EXCLUDE_LIBRETRO_CORES="atari800 a5200 prosystem vecx o2em handy"
```

## 验证（改完必做）

```bash
cd /home/dev/Lakka-LibreELEC
env PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
  bash -c '. config/options ""; set -o pipefail;
           ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' > /tmp/plan-new.txt
wc -l /tmp/plan-new.txt                    # 基线 432 行
diff /tmp/plan-test.txt /tmp/plan-new.txt  # 确认要删的都消失、没误删
```

---

## 已应用的裁剪（2026-10-13）

`projects/Rockchip/devices/RK3588/options` 里已写入 **82 个核心**的排除名单：
「方案 A（只留主流现代机种）」+ 用户指定项（`lrps2` `play` `boom3` `tyrquake` `vitaquake2`
`vitaquake3` `ecwolf` `openlara`）+ 3 个 Rust 核心（`rustation_ng` `boytacean` `doukutsu_rs`）。

实测结果：

| 指标 | 裁剪前 | 裁剪后 |
| --- | --- | --- |
| 任务总数 | 432 | **347** |
| 核心数 | 172 | **90** |

排除 3 个 Rust 核心的额外收益：依赖链 `llvm:host → rust:host → cargo:host` 整条消失，
**130 MB 的 LLVM 源码不用下载、数小时的 LLVM 编译也省掉**（本网络下 LLVM 的 GitHub
release 资产本来也下不来，见 BUILD_GUIDE §6.1 与 §11.6.1）。

保留的 90 个核心：任天堂全系、世嘉全系、索尼 PS1×3 + PSP、街机 `mame` 系 5 个 +
`fbneo`/`fbalpha2012`、PC Engine 系、PC-FX、Neo Geo（AES/CD）、CD-i、3DO、ColecoVision、
Amiga×4、DOS×4、Commodore/C64、MSX、Atari ST、IBM PC/XT、`scummvm`/`prboom`/`reminiscence`/
`nxengine` 等。

### 第二批追加（2026-10-13 下午）

再排除 **2 个**核心：`azahar`（任天堂 3DS）、`dolphin`（GameCube / Wii）。

| 指标 | 第一批后 | 第二批后 |
| --- | --- | --- |
| 任务总数 | 347 | **345** |
| 核心数 | 90 | **88** |

`EXCLUDE_LIBRETRO_CORES` 现共 **84** 个。校验结果：三项必查全部为"无"
（无拼写错误、无未生效、无误删），`dolphin`/`azahar` 已从计划中消失。

**重启必要性**：`dolphin` 在改配置前已编译完成并装入镜像，而正在运行的 job 用的是生成时的 plan，
新增排除不会回溯 → 必须停掉旧 job 再续跑。另外 `scripts/image:131` 有 `rm -rf ${INSTALL}`，
镜像目录每次重新组装，所以已装入的残留会自动清除，无需手工删。
停旧 job 用 `pkill -f pkgbuilder`（**不要**用 `pkill -f "scripts/build"`，会自匹配杀掉自己所在的 ssh shell）。
