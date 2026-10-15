#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# build-board.sh — 选芯片 + 选板卡，构建对应的一张 Lakka/LibreELEC 镜像
#
# 在 LibreELEC 里「芯片」是 DEVICE（对应 projects/<P>/devices/<DEVICE>/ 目录），
# 「板卡」是 UBOOT_SYSTEM（没有独立目录，只在 scripts/uboot_helper 里一条 entry）。
# 本脚本的板卡清单**从 uboot_helper 现取**，所以新增板卡（甚至新增芯片）后
# 不需要改这个脚本 —— 只要 uboot_helper 里有:
#     ./scripts/uboot_helper <PROJECT>
#     ./scripts/uboot_helper <PROJECT> <DEVICE>
#
# 用法:
#   build-board.sh                      # 菜单：选芯片 → 选板卡 → 确认 → 构建
#   build-board.sh RK3588 lubancat-4    # 直接构建（仍会做白名单校验）
#   build-board.sh --list               # 列出所有 (芯片, 板卡)
#   build-board.sh --list-boards RK3588 # 只列某芯片的板卡
#
# 选项:
#   -p, --project <P>   默认 Rockchip
#   -j, --jobs <N>      默认 nproc
#   --no-clean          不清理 u-boot 构建树（默认清理，见下）
#   --force             磁盘不足也继续
#   -y, --yes           菜单模式下不再交互确认
#   -h, --help
#
# 环境变量:
#   DDR_FREQ=<MHz>      覆盖该板的 DDR blob 频率（实验用，见 packages/u-boot/package.mk）
#   BUILD_LOG=<path>    日志路径，默认 /tmp/lakka-build-<board>.log
#
# 为什么要清 u-boot 构建树：
#   厂商 u-boot 的 make.sh 不做 distclean，同一棵源码树换板只跑
#   `make <board>_defconfig`，会带上上一块板留下的对象文件。多板构建时这会
#   产生难以解释的失败，所以默认 ./scripts/clean u-boot（源码包已缓存，不联网）。

set -u

PROJECT="${PROJECT:-Rockchip}"
ARCH="${ARCH:-aarch64}"
THREADCOUNT="${THREADCOUNT:-$(nproc 2>/dev/null || echo 4)}"
CLEAN_UBOOT=yes
FORCE=no
ASSUME_YES=no

CHIP=""
BOARD=""
LIST_ALL=no
LIST_BOARDS=""

# ------------------------------------------------------------------ helpers --
die()  { echo "错误: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

# 定位仓库根（脚本可能在仓库外被调用）
find_repo() {
  local d
  d="$(cd "$(dirname "$0")" && pwd)"
  while [ "$d" != "/" ]; do
    if [ -f "$d/scripts/uboot_helper" ] && [ -f "$d/Makefile" ]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  # 兜底：常见位置
  for d in "$HOME/Lakka-LibreELEC" "$HOME/libreelec"; do
    [ -f "$d/scripts/uboot_helper" ] && { echo "$d"; return 0; }
  done
  return 1
}

REPO="$(find_repo)" || die "找不到仓库根目录（需要 scripts/uboot_helper + Makefile）"
cd "$REPO" || die "无法进入 $REPO"

# 宿主兜底（非交互 shell 不读 ~/.bashrc）：zstd/rdfind/perl 垫片 + wget 包装器
export PATH="$HOME/bin:$PATH"
export PERL5LIB="$HOME/perl5${PERL5LIB:+:$PERL5LIB}"

uh() { "$REPO/scripts/uboot_helper" "$@"; }
socs()       { uh "$PROJECT"; }
boards_of()  { uh "$PROJECT" "$1"; }
dtb_of()     { uh "$PROJECT" "$1" "$2" dtb; }
cfg_of()     { uh "$PROJECT" "$1" "$2" config; }

# 板卡 → 期望的 dtb model 字符串（用于产物断言；未登记的板卡只打印不校验）
expected_model() {
  case "$1" in
    lubancat-5)    echo "Embedfire LubanCat-5" ;;
    lubancat-5-v2) echo "Embedfire LubanCat-5 V2" ;;
    lubancat-5io)  echo "Embedfire LubanCat-5IOB" ;;
    lubancat-5iob) echo "Embedfire LubanCat-5IOB" ;;
    lubancat-4)    echo "Embedfire LubanCat-4" ;;
    lubancat-4-v1) echo "Embedfire LubanCat-4 V1" ;;
    *)             echo "" ;;
  esac
}

# -------------------------------------------------------------------- 解析参数 --
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--project)   PROJECT="$2"; shift 2 ;;
    -j|--jobs)      THREADCOUNT="$2"; shift 2 ;;
    --no-clean)     CLEAN_UBOOT=no; shift ;;
    --force)        FORCE=yes; shift ;;
    -y|--yes)       ASSUME_YES=yes; shift ;;
    -h|--help)      usage; exit 0 ;;
    --list)         LIST_ALL=yes; shift ;;
    --list-boards)  LIST_BOARDS="$2"; shift 2 ;;
    -*)             die "未知选项: $1（-h 看用法）" ;;
    *)              if [ -z "$CHIP" ]; then CHIP="$1"; elif [ -z "$BOARD" ]; then BOARD="$1"; else die "多余参数: $1"; fi; shift ;;
  esac
done

ALL_SOCS="$(socs)"
[ -n "$ALL_SOCS" ] || die "uboot_helper 没返回任何芯片（PROJECT=$PROJECT）"

# ------------------------------------------------------------------- --list --
if [ "$LIST_ALL" = yes ]; then
  for s in $ALL_SOCS; do
    printf '%-8s : %s\n' "$s" "$(boards_of "$s")"
  done
  exit 0
fi
if [ -n "$LIST_BOARDS" ]; then
  b="$(boards_of "$LIST_BOARDS")"
  [ -n "$b" ] || die "芯片 '$LIST_BOARDS' 下没有已注册的板卡"
  echo "$b"
  exit 0
fi

# ---------------------------------------------------------------- 菜单 / 校验 --
have_menu() { [ -t 0 ] && [ -t 1 ] && command -v whiptail >/dev/null 2>&1; }

choose_menu() {  # $1=提示，其余=选项
  local prompt="$1"; shift
  local n=$#
  [ "$n" -gt 0 ] || die "没有可选项：$prompt"
  if have_menu; then
    local args=() it
    for it in "$@"; do args+=("$it" ""); done
    whiptail --title "Lakka 构建" --menu "$prompt" 20 66 12 "${args[@]}" 3>&1 1>&2 2>&3
    return
  fi
  # 回退：编号选择
  echo "$prompt" >&2
  local i=1 it
  for it in "$@"; do printf '  %d) %s\n' "$i" "$it" >&2; i=$((i+1)); done
  local sel
  while :; do
    printf '请输入编号 [1-%d]: ' "$n" >&2
    read -r sel || die "读取输入失败"
    case "$sel" in
      ''|*[!0-9]*) warn "请输入数字" ;;
      *) if [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then break; else warn "超出范围"; fi ;;
    esac
  done
  shift $((sel-1))
  echo "$1"
}

if [ -z "$CHIP" ]; then
  # 只列出真正有板卡的芯片，避免菜单里出现空目录
  CHIPS_WITH_BOARDS=""
  for s in $ALL_SOCS; do
    [ -n "$(boards_of "$s")" ] && CHIPS_WITH_BOARDS="$CHIPS_WITH_BOARDS $s"
  done
  CHIP="$(choose_menu "选择芯片 (DEVICE)" $CHIPS_WITH_BOARDS)" || exit 1
fi

case " $ALL_SOCS " in *" $CHIP "*) ;; *) die "芯片 '$CHIP' 不在 uboot_helper 里。可用: $ALL_SOCS" ;; esac

SOC_BOARDS="$(boards_of "$CHIP")"
[ -n "$SOC_BOARDS" ] || die "芯片 '$CHIP' 下没有已注册的板卡"

if [ -z "$BOARD" ]; then
  BOARD="$(choose_menu "选择 $CHIP 的板卡 (UBOOT_SYSTEM)" $SOC_BOARDS)" || exit 1
fi
case " $SOC_BOARDS " in *" $BOARD "*) ;; *) die "板卡 '$BOARD' 不属于 $CHIP。可用: $SOC_BOARDS" ;; esac

DTB="$(dtb_of "$CHIP" "$BOARD")"
UCFG="$(cfg_of "$CHIP" "$BOARD")"
[ -n "$DTB" ]  || die "uboot_helper 没给出 '$BOARD' 的 dtb"
[ -n "$UCFG" ] || die "uboot_helper 没给出 '$BOARD' 的 u-boot defconfig"

LOG="${BUILD_LOG:-/tmp/lakka-build-${BOARD}.log}"

echo
info "芯片 (DEVICE)        : $CHIP"
info "板卡 (UBOOT_SYSTEM)  : $BOARD"
info "内核 dtb             : $DTB"
info "u-boot defconfig     : $UCFG"
[ -n "${DDR_FREQ:-}" ] && info "DDR blob 覆盖         : ${DDR_FREQ}MHz"
info "产物（预计）          : target/Lakka-${CHIP}.*-${BOARD}.img.gz"
info "日志                 : $LOG"
echo

# ---------------------------------------------------------------- 磁盘预检 --
FREE_KB="$(df -Pk "$REPO" | awk 'NR==2{print $4}')"
FREE_G=$(( FREE_KB / 1024 / 1024 ))
EXISTING="$(du -sh target 2>/dev/null | awk '{print $1}')"
info "磁盘: $REPO 可用 ${FREE_G}G；target/ 现占 ${EXISTING:-0}"
if [ "$FREE_G" -lt 8 ] && [ "$FORCE" != yes ]; then
  die "可用空间不足 ${FREE_G}G（单块板约需 6-7G）。清理旧产物或加 --force"
fi
if [ "$FREE_G" -lt 20 ]; then
  warn "可用空间 ${FREE_G}G 偏少，多块板连着构建建议先清理 target/ 旧产物"
fi

# ------------------------------------------------------------------ 确认 --
if [ "$ASSUME_YES" != yes ] && have_menu; then
  MSG="将执行：

  cd $REPO
  PROJECT=$PROJECT DEVICE=$CHIP ARCH=$ARCH UBOOT_SYSTEM=$BOARD \\
    make image        # -j$THREADCOUNT
$([ "$CLEAN_UBOOT" = yes ] && echo "
前置：scripts/clean u-boot（换板必须清，厂商 make.sh 不做 distclean）")

产物：target/Lakka-${CHIP}.*-${BOARD}.img.gz

继续？"
  whiptail --title "确认构建" --yesno "$MSG" 22 76 || { echo "已取消"; exit 0; }
fi

export PROJECT DEVICE="$CHIP" ARCH UBOOT_SYSTEM="$BOARD" THREADCOUNT

# --------------------------------------------------------------- 构建 ------
t0="$(date +%s)"

if [ "$CLEAN_UBOOT" = yes ]; then
  info "清理 u-boot 构建树（./scripts/clean u-boot）"
  ./scripts/clean u-boot > "$LOG" 2>&1 || warn "clean u-boot 返回非零，继续"
else
  : > "$LOG"
fi

info "开始构建（$(date '+%F %T')）"
{
  echo "== build-board.sh: DEVICE=$CHIP UBOOT_SYSTEM=$BOARD dtb=$DTB ucfig=$UCFG =="
  echo "== 开始 $(date '+%F %T') =="
} >> "$LOG"

if ! make image >> "$LOG" 2>&1; then
  echo
  warn "构建失败，日志: $LOG"
  L="$(grep -n 'FAILED COMMAND' "$LOG" | head -1 | cut -d: -f1)"
  if [ -n "$L" ]; then
    start=$(( L > 45 ? L - 45 : 1 ))
    sed -n "${start},$(( L + 5 ))p" "$LOG" | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g'
  else
    tail -45 "$LOG" | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g'
  fi
  echo
  echo "排查提示（详见 devices/RK3588/tools/NETWORK_BUILD.md / BUILD_GUIDE.md）:"
  echo "  - 网络类报错（gnutls_handshake / SSL_ERROR_SYSCALL）→ 先跑 tools/fix-build-env.sh"
  echo "  - u-boot 链接/配置报错                              → 检查 packages/u-boot/package.mk 与 bootloader/config"
  exit 1
fi

t1="$(date +%s)"
info "构建成功，用时 $(( (t1 - t0) / 60 ))m$(( (t1 - t0) % 60 ))s（$(date '+%F %T')）"
echo "  最后进度: $(grep -oE '\[[0-9]+/[0-9]+\]' "$LOG" | tail -1)"
grep -m1 'u-boot: .*DDR blob ->' "$LOG" | sed 's/^/  /'

# --------------------------------------------------------------- 产物断言 --
IMG="$(ls -t target/Lakka-${CHIP}.*-${BOARD}.img.gz 2>/dev/null | head -1)"
[ -n "$IMG" ] || die "构建完成但找不到 target/Lakka-${CHIP}.*-${BOARD}.img.gz"

echo
info "校验产物: $IMG"
FAIL=0

# 1) sha256
sha256sum "$IMG" | sed 's/^/  /'

# 2) 引导布局魔数（32KiB = "LDR " idblock；8MiB = FIT uboot.img）
WORK="$(mktemp -d /tmp/build-board.XXXXXX)"
gzip -dc "$IMG" > "$WORK/img" || { warn "解压失败"; exit 1; }
printf '  32KiB loader : %s (期望 4c445220)\n' "$(dd if="$WORK/img" bs=1 skip=32768 count=4 status=none | xxd -p)"
printf '  8MiB  FIT    : %s (期望 d00dfeed)\n' "$(dd if="$WORK/img" bs=1 skip=8388608 count=4 status=none | xxd -p)"
[ "$(dd if="$WORK/img" bs=1 skip=32768 count=4 status=none | xxd -p)" = "4c445220" ] || { warn "32KiB 处不是 idblock"; FAIL=1; }
[ "$(dd if="$WORK/img" bs=1 skip=8388608 count=4 status=none | xxd -p)" = "d00dfeed" ] || { warn "8MiB 处不是 FIT"; FAIL=1; }

# 3) boot 分区：只有该板的 dtb + extlinux.conf 指向它
echo "  --- boot 分区 ---"
mdir -i "$WORK/img@@16777216" :: 2>/dev/null | sed 's/^/  /'
N_DTB="$(mdir -i "$WORK/img@@16777216" :: 2>/dev/null | grep -c '\.dtb$')"
[ "$N_DTB" = "1" ] || { warn "boot 分区里 dtb 数量=$N_DTB（期望 1）"; FAIL=1; }
CONF="$(mtype -i "$WORK/img@@16777216" ::/extlinux/extlinux.conf 2>/dev/null)"
echo "  --- extlinux.conf ---"
echo "$CONF" | sed 's/^/  /'
echo "$CONF" | grep -q "FDT /${DTB}$" || { warn "extlinux.conf 的 FDT 不是 /${DTB}"; FAIL=1; }
echo "$CONF" | grep -q 'LINUX /KERNEL'  || { warn "extlinux.conf 没有 LINUX /KERNEL"; FAIL=1; }

# 4) dtb 内容：model + HDMI 通路
if mcopy -o -i "$WORK/img@@16777216" "::/${DTB}" "$WORK/chk.dtb" 2>/dev/null && [ -s "$WORK/chk.dtb" ]; then
  dtc -I dtb -O dts -o "$WORK/chk.dts" "$WORK/chk.dtb" 2>/dev/null
  MODEL="$(grep -m1 -o 'model = "[^"]*"' "$WORK/chk.dts" | sed 's/model = "//; s/"$//')"
  HDST="$(grep -A30 -m1 'hdmi@fde80000 {' "$WORK/chk.dts" | grep -m1 -o 'status = "[^"]*"' | cut -d'"' -f2)"
  RTST="$(grep -A8 -m1 'route-hdmi0 {' "$WORK/chk.dts" | grep -m1 -o 'status = "[^"]*"' | cut -d'"' -f2)"
  SND="$(grep -c 'rockchip-hdmi0' "$WORK/chk.dts")"
  printf '  dtb model     : %s\n' "$MODEL"
  printf '  hdmi@fde80000 : %s\n' "${HDST:-?}"
  printf '  route-hdmi0   : %s\n' "${RTST:-?}"
  printf '  rockchip-hdmi0: %s\n' "$SND"
  WANT="$(expected_model "$BOARD")"
  if [ -n "$WANT" ]; then
    [ "$MODEL" = "$WANT" ] || { warn "dtb model 期望 '$WANT'，实际 '$MODEL'"; FAIL=1; }
  else
    warn "uboot_helper 里这个板卡没在 expected_model() 表里，跳过 model 断言"
  fi
  [ "$HDST" = "okay" ] || { warn "hdmi@fde80000 不是 okay（显示补丁没生效？）"; FAIL=1; }
  [ "$RTST" = "okay" ] || { warn "route-hdmi0 不是 okay"; FAIL=1; }
  [ "$SND" -ge 1 ]     || { warn "找不到 rockchip-hdmi0 声卡节点"; FAIL=1; }
else
  warn "无法从 boot 分区取出 $DTB"
  FAIL=1
fi

rm -rf "$WORK"

echo
if [ "$FAIL" = "0" ]; then
  info "全部校验通过：$IMG"
  echo
  echo "下一步:"
  echo "  # 刷机（SD 直写）"
  echo "  gzip -dc $IMG | dd of=/dev/sdX bs=4M status=progress conv=fsync"
  echo "  # 或打成 RKDevTool 用的 update.img"
  echo "  ./projects/Rockchip/devices/RK3588/tools/mk-rockchip-update.sh --board $BOARD"
  echo "  # 上机后先看串口（1500000 8N1）里 DDR 那行，确认内存频率与 DDR blob 匹配"
  exit 0
else
  warn "校验发现问题（见上），镜像可能不可启动：$IMG"
  exit 2
fi
