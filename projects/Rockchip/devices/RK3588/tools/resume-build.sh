#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# resume-build.sh — 一键（继续）构建 Lakka RK3588 / 鲁班猫5 镜像
#
#   ./resume-build.sh              # 前台跑，日志同时写 /tmp/rk3588-build-image.log
#   ./resume-build.sh &            # 后台跑，之后 tail -f /tmp/rk3588-build-image.log
#
# 幂等：已完成的包走 stamp 直接复用，源码已缓存的不会重新下载。
# 失败时自动把「第一处 FAILED COMMAND 往前 60 行」打印出来，省得手动翻日志。
#
set -u

# ------------------------------ 可调参数 ------------------------------
export PROJECT="${PROJECT:-Rockchip}"
export DEVICE="${DEVICE:-RK3588}"
export ARCH="${ARCH:-aarch64}"
export UBOOT_SYSTEM="${UBOOT_SYSTEM:-lubancat-5}"
export THREADCOUNT="${THREADCOUNT:-4}"     # 4 核机器；内存紧张就降到 2
export GIT_RETRIES="${GIT_RETRIES:-8}"     # scripts/get_git 的网络重试次数

LOG="${BUILD_LOG:-/tmp/rk3588-build-image.log}"

# ------------------------------ 定位仓库 ------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ] && { REPO="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$REPO" ] && { echo "错误：找不到仓库根目录" >&2; exit 1; }

# 宿主兜底（必须显式设置：非交互 shell 不读 ~/.bashrc）
#   ~/bin/{zstd,zstdcat,unzstd}   解 .tar.zst
#   ~/bin/{rdfind,yapp} ~/perl5/  checkdeps / samba 需要的 perl 依赖
#   ~/bin/wget                    GitHub 走镜像、非 GitHub 主机 https->http 兜底
export PATH="$HOME/bin:$PATH"
export PERL5LIB="$HOME/perl5${PERL5LIB:+:$PERL5LIB}"

cd "$REPO" || exit 1

echo "== 开始 $(date '+%F %T') =="
echo "== 仓库 $(basename "$REPO") / 分支 $(git rev-parse --abbrev-ref HEAD 2>/dev/null) / 剩余磁盘 $(df -h . | awk 'NR==2{print $4}') =="

make image > "$LOG" 2>&1
rc=$?

echo "== 最后进度：$(grep -oE '\[[0-9]+/[0-9]+\]' "$LOG" | tail -1) =="

if [ "$rc" -ne 0 ]; then
  echo "== 构建失败（rc=$rc），定位第一处 FAILED COMMAND =="
  L="$(grep -n "FAILED COMMAND" "$LOG" | head -1 | cut -d: -f1)"
  if [ -n "$L" ]; then
    start=$(( L > 60 ? L - 60 : 1 ))
    sed -n "${start},$(( L - 1 ))p" "$LOG" | tail -45
  else
    tail -45 "$LOG"
  fi
  echo
  echo "排查提示（详见 tools/NETWORK_BUILD.md）:"
  echo "  - gnutls_handshake / Connection timed out / SSL_ERROR_SYSCALL → 先跑 tools/fix-build-env.sh 装网络垫片"
  echo "  - 仍有个别包拉不下来                                          → tools/audit-missing-sources.sh + tools/seed-missing-sources.sh"
  echo "  - 'No targets specified and no makefile found'                → 源码缓存的子模块缺失，用 seed-any-pkg.sh 重灌并清 build/<pkg>-*"
  echo "  - 'Incorrect checksum ... on downloaded file'                 → snapshot 哈希过期，别直接改哈希，先交叉验证"
  exit "$rc"
fi

echo "== 完成 $(date '+%F %T') =="
ls -lh target/Lakka-"$DEVICE".*.img* 2>/dev/null
