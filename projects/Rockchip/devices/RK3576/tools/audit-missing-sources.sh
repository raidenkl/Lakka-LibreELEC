#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# audit-missing-sources.sh — 找出「当前构建计划里，源码缓存还没准备好」的包
#
#   ./audit-missing-sources.sh [plan文件]
#
# 不带参数时会先按当前 options **只读**重新生成一份构建计划（不触发编译）。
# 输出 TSV：type<TAB>pkg<TAB>host<TAB>url<TAB>version
#   type = git（缓存看 .gitstamp）| archive（缓存看 .url + .sha256）
#
# 用途：构建被网络卡住时，先跑它看清「还差哪些包」，再用 seed-missing-sources.sh 批量补齐。
#
set -uo pipefail

MIRROR_BASE="${MIRROR_BASE:-https://gh-proxy.com}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ] && { REPO_ROOT="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$REPO_ROOT" ] && { echo "错误：找不到仓库根目录" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

PLAN="${1:-}"
if [ -z "$PLAN" ]; then
  PLAN=/tmp/audit-plan.txt
  echo "== 生成构建计划（只读，不触发编译）..."
  env PROJECT="${PROJECT:-Rockchip}" DEVICE="${DEVICE:-RK3588}" ARCH="${ARCH:-aarch64}" \
      UBOOT_SYSTEM="${UBOOT_SYSTEM:-lubancat-5}" bash -c \
      '. config/options ""; set -o pipefail; ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' \
      > "$PLAN" 2>/dev/null || { echo "错误：生成计划失败" >&2; exit 1; }
  echo "   -> $PLAN ($(grep -c . "$PLAN") 个任务)"
fi

grep -oE "^install [a-z0-9_.+-]+" "$PLAN" | awk '{print $2}' | sort -u > /tmp/audit-pkgs.txt

OUT=/tmp/audit-missing.tsv
: > "$OUT"
while read -r p; do
  [ -z "$p" ] && continue
  f="$(find packages -maxdepth 5 -path "*/$p/package.mk" | head -1)"
  [ -z "$f" ] && continue
  url="$(grep -h '^PKG_URL=' "$f" | head -1 | sed 's/^PKG_URL=//; s/"//g')"
  ver="$(grep -h '^PKG_VERSION=' "$f" | head -1 | sed 's/^PKG_VERSION=//; s/"//g')"
  site="$(grep -h '^PKG_SITE=' "$f" | head -1 | sed 's/^PKG_SITE=//; s/"//g')"
  [ -z "$url" ] && continue
  url="${url//\$\{PKG_SITE\}/$site}"; url="${url//\$PKG_SITE/$site}"

  # 已有缓存则跳过
  ls sources/"$p"/*.gitstamp >/dev/null 2>&1 && continue
  if ls sources/"$p"/*.url >/dev/null 2>&1 && ls sources/"$p"/*.sha256 >/dev/null 2>&1; then continue; fi

  host="$(printf '%s' "$url" | sed 's|^[a-z]*://||; s|/.*||')"
  case "$url" in
    *.git)    printf 'git\t%s\t%s\t%s\t%s\n'     "$p" "$host" "$url" "$ver" >> "$OUT" ;;
    *)        printf 'archive\t%s\t%s\t%s\t%s\n' "$p" "$host" "$url" "$ver" >> "$OUT" ;;
  esac
done < /tmp/audit-pkgs.txt

echo
echo "== 仍缺源码缓存的包：$(grep -c . "$OUT" || true) 个"
if [ -s "$OUT" ]; then
  echo "--- 按类型 ---"; awk -F'\t' '{print $1}' "$OUT" | sort | uniq -c
  echo "--- 按主机 ---"; awk -F'\t' '{print $1"  "$3}' "$OUT" | sort | uniq -c | sort -rn
  echo "--- 明细 ---"; cat "$OUT"
  echo
  echo "下一步：./seed-missing-sources.sh $OUT"
else
  echo "   （全部就绪，不需要预置）"
fi
