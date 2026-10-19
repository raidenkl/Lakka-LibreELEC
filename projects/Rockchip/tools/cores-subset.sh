#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# cores-subset.sh — 打印「除保留名单之外的全部 libretro 核心」，用于快速验证构建
#
# 用法（冒烟构建：只留 3 个轻量核心）：
#   EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
#     ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1
#
# 用法（只砍最慢的重核，保留其余全部）：
#   EXCLUDE_LIBRETRO_CORES="mame mame2015 mame2010 ppsspp citra scummvm panda3ds flycast" \
#     ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1
#
# 不带参数时列出全部核心名（方便挑保留名单）。
#
# 原理：设备 options 里 EXCLUDE_LIBRETRO_CORES 用 ${EXCLUDE_LIBRETRO_CORES:-} 前缀
# 保留继承值，packages/lakka/libretro_cores/package.mk 末尾再逐项从 LIBRETRO_CORES
# 中剔除 —— 所以从命令行追加排除项即可，不需要改共享文件。裁剪只影响镜像里带哪些
# 核心，去掉该环境变量重跑 `make image` 就会增量补回来。

set -eu

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CORES_DIR="$REPO/packages/lakka/libretro_cores"

[ -d "$CORES_DIR" ] || { echo "错误: 找不到 $CORES_DIR" >&2; exit 1; }

list_cores() {
  local d
  for d in "$CORES_DIR"/*/; do
    [ -f "$d/package.mk" ] || continue
    basename "$d"
  done
}

if [ "$#" -eq 0 ]; then
  # 无参数：列出全部核心，一行一个
  list_cores | sort
  exit 0
fi

keep=" $* "
out=""
while read -r core; do
  case "$keep" in
    *" $core "*) ;;
    *) out="$out $core" ;;
  esac
done <<EOF
$(list_cores)
EOF

# 去掉行首空格后输出（供 EXCLUDE_LIBRETRO_CORES 使用）
echo "${out# }"
