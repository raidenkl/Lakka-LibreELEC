#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# configure-cores.sh — 交互式配置 Lakka 镜像要打包哪些 libretro 游戏机核心
#
# 原理：`packages/lakka/libretro_cores/package.mk` 内置了官方排除机制
#
#     for core in ${EXCLUDE_LIBRETRO_CORES}; do
#       LIBRETRO_CORES="${LIBRETRO_CORES// ${core} /}"     # 纯字符串替换
#     done
#
# 所以只要往 `projects/<PROJECT>/devices/<DEVICE>/options` 里写一行
# EXCLUDE_LIBRETRO_CORES="core1 core2 …" 就能裁剪核心。注意两点：
#   * **写错名字会被静默忽略**（不报错）→ 本脚本只允许从真实名单里选
#   * 改完 options 必须**重启构建 job** 才生效（已在运行中的 job 用旧计划）
#
# 用法:
#   ./configure-cores.sh                  # 交互式（dialog 两级菜单）
#   ./configure-cores.sh --list           # 打印当前配置（不改动）
#   ./configure-cores.sh --preset a       # 直接套用方案 A「只留主流现代机种」
#   ./configure-cores.sh --preset b       # 方案 B（A + 砍掉编译最慢的大件）
#   ./configure-cores.sh --preset none    # 全部保留（只排除系统自动管理的）
#   ./configure-cores.sh --dry-run        # 配合 --preset，只打印将写入的内容
#   ./configure-cores.sh --no-verify      # 写入后不重新生成构建计划做对比
#
# 依赖：dialog（首选）或 whiptail；都没有时退化为纯文本编号菜单。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_FILE="$SCRIPT_DIR/cores-data.tsv"

# ------------------------------ 定位仓库 ------------------------------
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ] && { REPO_ROOT="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$REPO_ROOT" ] && { echo "错误：找不到仓库根目录（需包含 scripts/build 与 Makefile）" >&2; exit 1; }

PROJECT="${PROJECT:-Rockchip}"
DEVICE="${DEVICE:-RK3588}"
OPTIONS="$REPO_ROOT/projects/$PROJECT/devices/$DEVICE/options"
CORES_PKG="$REPO_ROOT/packages/lakka/libretro_cores/package.mk"
[ -f "$OPTIONS" ]   || { echo "错误：找不到 $OPTIONS" >&2; exit 1; }
[ -f "$CORES_PKG" ] || { echo "错误：找不到 $CORES_PKG" >&2; exit 1; }

# 系统自动管理的核心：不作为用户可选项
MANAGED_CORES="kronos lr_moonlight"
# 重新勾选会死在 LLVM 下载（国内拉不动）的核心
RUST_CORES="rustation_ng boytacean doukutsu_rs"

# ------------------------------ 输出 ------------------------------
if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$1"; }
info() { printf '  %s·%s %s\n' "$C_B" "$C_0" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$1"; }
err()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$1"; }

# ------------------------------ 读取数据 ------------------------------
# 1) 真实核心名单：从 LIBRETRO_CORES 的各个赋值段里收集，剔除 ${VAR} 之类的引用
read_live_cores() {
  python3 - "$CORES_PKG" <<'PYEOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
# 只取「变量名恰好是 LIBRETRO_CORES」的赋值；负向后视排除 EXCLUDE_LIBRETRO_CORES
# （否则会把 RPi 等分支的排除清单当成核心名单）
chunks = re.findall(r'(?<![A-Za-z0-9_])LIBRETRO_CORES\+?="([^"]*)"', s)
words = []
for c in chunks:
    words += c.replace("\\", " ").split()
bad = re.compile(r'[\$\{\}/]')
names = sorted({w for w in words if not bad.search(w) and w not in ("core1", "core2")})
print("\n".join(names))
PYEOF
}
LIVE_CORES="$(read_live_cores)"
[ -z "$LIVE_CORES" ] && { echo "错误：无法从 $CORES_PKG 解析核心名单" >&2; exit 1; }
LIVE_COUNT="$(printf '%s\n' "$LIVE_CORES" | grep -c .)"

# 2) 当前排除名单：读 options 里那一行
read_current_excluded() {
  sed -n 's/^[[:space:]]*EXCLUDE_LIBRETRO_CORES="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$OPTIONS" \
    | tr ' ' '\n' | grep -v '^$' | sort -u
}
EXCLUDED_FILE="$(mktemp /tmp/configure-cores.XXXXXX)"
trap 'rm -f "$EXCLUDED_FILE"' EXIT
read_current_excluded > "$EXCLUDED_FILE"

is_excluded() { grep -qxF "$1" "$EXCLUDED_FILE"; }
exclude()     { is_excluded "$1" || echo "$1" >> "$EXCLUDED_FILE"; }
include()     { grep -vxF "$1" "$EXCLUDED_FILE" > "$EXCLUDED_FILE.t" || true; mv "$EXCLUDED_FILE.t" "$EXCLUDED_FILE"; }
is_managed()  { for m in $MANAGED_CORES; do [ "$1" = "$m" ] && return 0; done; return 1; }
is_rust()     { for m in $RUST_CORES;    do [ "$1" = "$m" ] && return 0; done; return 1; }

# 3) 元数据：分类 / 推荐 / 备注
meta_field() { # $1=core  $2=列号(2..4)
  awk -F'\t' -v c="$1" -v n="$2" '$1==c {print $n; exit}' "$DATA_FILE" 2>/dev/null
}
categories() { awk -F'\t' '!/^#/ {print $2}' "$DATA_FILE" 2>/dev/null | awk '!seen[$0]++'; }
cores_in_category() { awk -F'\t' -v c="$1" '!/^#/ && $2==c {print $1}' "$DATA_FILE"; }
recommended_remove() { awk -F'\t' '!/^#/ && ($3=="remove" || $3=="remove-heavy") {print $1}' "$DATA_FILE"; }
recommended_heavy()  { awk -F'\t' '!/^#/ && $3=="remove-heavy" {print $1}' "$DATA_FILE"; }

# ------------------------------ 交互前端 ------------------------------
if command -v dialog >/dev/null 2>&1; then
  UI=dialog
elif command -v whiptail >/dev/null 2>&1; then
  UI=whiptail
else
  UI=text
fi

ui_msg()   { # $1=标题 $2=内容
  case "$UI" in
    dialog)   dialog --title "$1" --msgbox "$2" 20 76 ;;
    whiptail) whiptail --title "$1" --msgbox "$2" 20 76 ;;
    *)        printf '\n== %s ==\n%s\n（回车继续）' "$1" "$2"; read -r _ ;;
  esac
}
ui_yesno() { # $1=标题 $2=内容
  case "$UI" in
    dialog)   dialog --title "$1" --yesno "$2" 20 76 ;;
    whiptail) whiptail --title "$1" --yesno "$2" 20 76 ;;
    *)        printf '\n== %s ==\n%s\n[y/N] ' "$1" "$2"; read -r a; [ "$a" = y ] || [ "$a" = Y ] ;;
  esac
}
ui_menu() { # $1=标题 $2=提示 $3..= tag desc 对 ; 输出选中的 tag
  local title="$1" prompt="$2"; shift 2
  case "$UI" in
    dialog)   dialog --title "$title" --menu "$prompt" 22 76 14 "$@" 3>&1 1>&2 2>&3 ;;
    whiptail) whiptail --title "$title" --menu "$prompt" 22 76 14 "$@" 3>&1 1>&2 2>&3 ;;
    *)        local i=1; local tags=()
               printf '\n== %s ==\n%s\n' "$title" "$prompt"
               while [ $# -gt 0 ]; do printf '  %2d) %s  %s\n' "$i" "$1" "$2"; tags+=("$1"); shift 2; i=$((i+1)); done
               printf '选择编号（空=返回）: '; read -r n
               [ -z "$n" ] && return 1
               printf '%s\n' "${tags[$((n-1))]}" ;;
  esac
}
ui_checklist() { # $1=标题 $2=提示 $3..= tag desc on/off ; 输出勾选的 tag（每行一个）
  local title="$1" prompt="$2"; shift 2
  case "$UI" in
    dialog)   dialog --title "$title" --separate-output --checklist "$prompt" 24 78 16 "$@" 3>&1 1>&2 2>&3 ;;
    whiptail) whiptail --title "$title" --separate-output --checklist "$prompt" 24 78 16 "$@" 3>&1 1>&2 2>&3 ;;
    *)        # 纯文本：以逗号/空格输入要「保留」的核心编号
               local i=1; local tags=()
               printf '\n== %s ==\n%s\n' "$title" "$prompt"
               while [ $# -gt 0 ]; do
                 local st="保留"; [ "$3" = off ] && st="排除"
                 printf '  %3d) %-26s [%s]\n' "$i" "$1" "$st"
                 tags+=("$1"); i=$((i+1)); shift 3
               done
               printf '输入要「保留」的编号（空格分隔，空=全部保留，直接回车=不动）: '; read -r sel
               for x in $sel; do printf '%s\n' "${tags[$((x-1))]}"; done ;;
  esac
}

# ------------------------------ 核心动作 ------------------------------
count_managed() { # 名单里由构建系统自动排除的核心数
  local n=0 m
  for m in $MANAGED_CORES; do
    printf '%s\n' "$LIVE_CORES" | grep -qxF "$m" && n=$((n+1))
  done
  echo "$n"
}
MANAGED_COUNT="$(count_managed)"
SELECTABLE_COUNT=$(( LIVE_COUNT - MANAGED_COUNT ))
count_excluded() { grep -c . "$EXCLUDED_FILE" 2>/dev/null || true; }
count_included() { echo $(( SELECTABLE_COUNT - $(count_excluded) )); }

show_state() {
  local exc inc
  exc="$(count_excluded)"
  inc="$(count_included)"
  {
    echo "设备        : $PROJECT/$DEVICE"
    echo "options     : $OPTIONS"
    echo "核心名单总数: $LIVE_COUNT（其中 $MANAGED_COUNT 个由构建系统自动排除）"
    echo "用户可选    : $SELECTABLE_COUNT"
    echo "排除        : $exc"
    echo "进镜像      : $inc"
    echo "系统自动管理: $MANAGED_CORES"
    echo
    echo "── 当前排除的核心 ──"
    sort "$EXCLUDED_FILE" | paste -sd' ' -
    echo
    echo "── 当前保留的核心（含系统管理的 $MANAGED_CORES，它们最终不会进镜像） ──"
    comm -23 <(printf '%s\n' "$LIVE_CORES" | sort) <(sort "$EXCLUDED_FILE") | paste -sd' ' -
  }
}

apply_preset() { # $1 = a | b | none
  case "$1" in
    a)    : > "$EXCLUDED_FILE"; recommended_remove | while read -r c; do exclude "$c"; done
          info "方案 A：只留主流现代机种" ;;
    b)    : > "$EXCLUDED_FILE"; recommended_remove | while read -r c; do exclude "$c"; done
          recommended_heavy  | while read -r c; do exclude "$c"; done
          info "方案 B：方案 A + 砍掉编译最慢的大件" ;;
    none) : > "$EXCLUDED_FILE"; info "全部保留（不排除任何核心）" ;;
    *)    err "未知预设: $1"; return 1 ;;
  esac
  # 系统管理的核心不写进排除名单
  for m in $MANAGED_CORES; do include "$m"; done
  return 0
}

edit_category() { # $1 = 分类名
  local cat="$1" args=() c note on
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    is_managed "$c" && continue
    note="$(meta_field "$c" 4)"
    on=on; is_excluded "$c" && on=off
    [ ${#note} -gt 34 ] && note="${note:0:33}…"
    args+=("$c" "$note" "$on")
  done < <(cores_in_category "$cat")
  [ ${#args[@]} -eq 0 ] && { ui_msg "提示" "分类「$cat」下没有可配置的核心"; return 0; }

  local picked
  picked="$(ui_checklist "配置：$cat" "空格=切换，回车=确认。勾选=打进镜像" "${args[@]}")" || return 0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    is_managed "$c" && continue
    if printf '%s\n' "$picked" | grep -qxF "$c"; then include "$c"; else exclude "$c"; fi
  done < <(cores_in_category "$cat")
}

check_rust_kept() {
  local kept=""
  for r in $RUST_CORES; do is_excluded "$r" || kept="$kept $r"; done
  [ -n "$kept" ] && { echo "$kept"; return 0; }
  return 1
}

write_options() { # 返回 0=已写入
  local list newline stamp bak
  list="$(sort "$EXCLUDED_FILE" | paste -sd' ' -)"
  newline="    EXCLUDE_LIBRETRO_CORES=\"$list\""

  # 写前校验：名单里的每个名字都必须真实存在（防静默忽略）
  local bad=""
  while read -r c; do
    [ -z "$c" ] && continue
    printf '%s\n' "$LIVE_CORES" | grep -qxF "$c" || bad="$bad $c"
  done < "$EXCLUDED_FILE"
  if [ -n "$bad" ]; then err "以下名字不在真实名单里，拒绝写入:$bad"; return 1; fi

  stamp="$(date +%Y%m%d-%H%M%S)"; bak="$OPTIONS.bak.$stamp"
  cp -a "$OPTIONS" "$bak"
  info "已备份: $(basename "$bak")"

  awk -v new="$newline" '
    /^[[:space:]]*EXCLUDE_LIBRETRO_CORES=/ { print new; found=1; next }
    { print }
    END { if (!found) { print ""; print "  # libretro 核心裁剪（configure-cores.sh 写入）"; print new } }
  ' "$OPTIONS" > "$OPTIONS.tmp" && mv "$OPTIONS.tmp" "$OPTIONS"

  ok "已写入 $OPTIONS"
  info "$newline"
  return 0
}

verify_plan() {
  ui_yesno "验证" "是否重新生成构建计划并与当前对比？\n\n（只重算依赖，不触发编译；约 10-30 秒）" || return 0
  local newplan=/tmp/configure-cores-plan-new.txt
  if ! ( cd "$REPO_ROOT" && env PROJECT="$PROJECT" DEVICE="$DEVICE" ARCH="${ARCH:-aarch64}" \
         UBOOT_SYSTEM="${UBOOT_SYSTEM:-lubancat-5}" bash -c \
         '. config/options ""; set -o pipefail; ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' \
         > "$newplan" 2>/dev/null ); then
    err "生成构建计划失败"; return 1
  fi
  local old=/tmp/configure-cores-plan-old.txt
  if [ -f "$old" ]; then
    local o n
    o="$(grep -c . "$old")"; n="$(grep -c . "$newplan")"
    info "任务总数: $o -> $n"
    diff "$old" "$newplan" | grep '^[<>]' | grep -oE 'install [a-z0-9_.+-]+' | sort -u | head -30
  fi
  local cnt
  cnt="$(grep -oE '^install libretro_cores.*' "$newplan" | sed 's/^install libretro_cores *(wants: //; s/)$//' | tr ',' '\n' | grep -c .)"
  ok "新计划里核心数: $((cnt-1))（含 toolchain 一行，已减）"
  cp -f "$newplan" "$old" 2>/dev/null || true
  return 0
}

remind_restart() {
  ui_msg "写入完成" "配置已写入 options。\n\n生效方式（二选一）：\n  • 构建没在跑    :  tools/resume-build.sh\n  • 构建正在跑     :  先停掉旧 job，再续跑\n\n    停旧 job 用 :  pkill -f pkgbuilder\n    切勿使用    :  pkill -f \"scripts/build\"   ← 会自匹配杀掉你当前的 ssh shell\n\n注意：已在运行中的 job 用的是生成时的计划，改 options 不会回溯。"
}

# ------------------------------ 主流程 ------------------------------
MODE=interactive
PRESET=""
DRY_RUN=0
DO_VERIFY=1
while [ $# -gt 0 ]; do
  case "$1" in
    --list)      MODE=list ;;
    --preset)    MODE=preset; PRESET="$2"; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --no-verify) DO_VERIFY=0 ;;
    -h|--help)   sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = list ]; then
  show_state
  exit 0
fi

if [ "$MODE" = preset ]; then
  apply_preset "$PRESET" || exit 1
  echo
  show_state
  echo
  if [ "$DRY_RUN" = 1 ]; then
    list="$(sort "$EXCLUDED_FILE" | paste -sd' ' -)"
    warn "dry-run：将写入下面这一行（未改动文件）"
    echo "    EXCLUDE_LIBRETRO_CORES=\"$list\""
    exit 0
  fi
  if k="$(check_rust_kept)"; then
    warn "注意：Rust 核心仍在勾选中（$k）—— 它们会拉入 llvm:host（130 MB，国内下载会失败）"
  fi
  write_options || exit 1
  [ "$DO_VERIFY" = 1 ] && verify_plan
  echo
  ok "完成。生效需重启构建 job（pkill -f pkgbuilder 后 tools/resume-build.sh）"
  exit 0
fi

# ---- 交互模式 ----
if [ "$UI" = text ]; then
  warn "未找到 dialog/whiptail，退化为纯文本菜单"
fi

while :; do
  exc="$(count_excluded)"
  inc="$(count_included)"
  choice="$(ui_menu "Lakka 核心配置（$PROJECT/$DEVICE）" \
    "名单 $LIVE_COUNT（系统自动排除 $MANAGED_COUNT）· 可选 $SELECTABLE_COUNT · 排除 $exc · 进镜像 $inc
用 ↑↓ 选择，回车确认" \
    "preset-a"   "预设 A：只留主流现代机种（去 $(recommended_remove | grep -c .) 个老机种/冷门平台）" \
    "preset-b"   "预设 B：A + 砍掉编译最慢的大件（再 +$(recommended_heavy | grep -c .) 个，构建时间收益最大）" \
    "categories" "按分类逐项配置（9 大类，勾选=打进镜像）" \
    "view"       "查看当前配置" \
    "reset"      "全部保留（清空排除名单）" \
    "write"      "写入 options 并验证" \
    "quit"       "退出（放弃未写入的改动）" )" || break

  case "$choice" in
    preset-a) apply_preset a ;;
    preset-b) apply_preset b ;;
    reset)    apply_preset none ;;
    categories)
      while :; do
        c="$(ui_menu "按分类配置" "选择要编辑的分类（返回=回到主菜单）" \
              cat_all "全部核心逐个勾选（较长）" \
              $(for x in $(categories); do echo "$x"; echo "$x"; done) )" || break
        case "$c" in
          cat_all)
            args=()
            while IFS= read -r core; do
              is_managed "$core" && continue
              note="$(meta_field "$core" 4)"; [ ${#note} -gt 34 ] && note="${note:0:33}…"
              on=on; is_excluded "$core" && on=off
              args+=("$core" "$note" "$on")
            done <<< "$LIVE_CORES"
            picked="$(ui_checklist "全部核心" "勾选=打进镜像" "${args[@]}")" || continue
            while IFS= read -r core; do
              is_managed "$core" && continue
              if printf '%s\n' "$picked" | grep -qxF "$core"; then include "$core"; else exclude "$core"; fi
            done <<< "$LIVE_CORES" ;;
          *) edit_category "$c" ;;
        esac
      done ;;
    view)
      show_state > /tmp/configure-cores-view.txt
      if [ "$UI" = text ]; then cat /tmp/configure-cores-view.txt; printf '（回车继续）'; read -r _
      else "$UI" --title "当前配置" --textbox /tmp/configure-cores-view.txt 26 84; fi ;;
    write)
      if k="$(check_rust_kept)"; then
        ui_yesno "警告：Rust 核心被勾选" "以下 Rust 核心将被打进镜像:$k

它们依赖 llvm:host（LLVM 源码 130 MB），在国内网络下几乎必然下载失败，
会让你反复卡在构建的 llvm 阶段。建议排除（有更好的替代：GB 用 gambatte/sameboy，
PS1 用 beetle_psx/pcsx_rearmed/swanstation）。

仍要继续写入吗？" || continue
      fi
      write_options || continue
      [ "$DO_VERIFY" = 1 ] && verify_plan
      remind_restart
      break ;;
    *) break ;;
  esac
done

echo
info "未写入的改动已丢弃（如需保存请在上一步选择「写入 options 并验证」）"
