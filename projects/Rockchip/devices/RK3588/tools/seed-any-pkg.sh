#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# seed-any-pkg.sh — 当上游主机不可达时（典型：github.com 在国内被阻断），
# 为一个 LibreELEC 包预置「源码缓存」，让构建系统直接命中、不需要联网。
#
#   ./seed-any-pkg.sh <包名>          # 例: ./seed-any-pkg.sh flycast
#
# 自动识别两种源类型：
#   * git 源    -> 走真正的 git fetch（git 会校验每个对象与锁定 commit SHA 一致，
#                  所以即使传输经过镜像，内容也不可能被篡改），github.com 自动经镜像；
#                  并执行 `git submodule update --init --recursive`（漏了子模块会导致
#                  「No targets specified and no makefile found」这类怪错）
#   * 归档源    -> 下载 + 与 recipe 的 PKG_SHA256 比对，再写 `.url` / `.sha256` 戳
#
# 缓存格式（两者不同，不能混用）：
#   git   : sources/<pkg>/<pkg>-<sha>.tar.xz  +  <pkg>-<sha>.tar.xz.gitstamp
#           其中 .gitstamp 内容为 "<PKG_URL>|<PKG_VERSION>"，PKG_URL 必须是**原始非镜像 URL**
#   归档  : sources/<pkg>/<PKG_SOURCE_NAME>  +  <PKG_SOURCE_NAME>.url  +  .sha256
#
# 环境变量：MIRROR_BASE（默认 https://gh-proxy.com）、MIRROR_FALLBACK（默认 https://ghfast.top）
#
set -uo pipefail

PKG="${1:-}"
[ -z "$PKG" ] && { echo "用法: $0 <包名>" >&2; exit 2; }

MIRROR_BASE="${MIRROR_BASE:-https://gh-proxy.com}"
MIRROR_FALLBACK="${MIRROR_FALLBACK:-https://ghfast.top}"
PROXY_PREFIX="$MIRROR_BASE/"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ] && { REPO_ROOT="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$REPO_ROOT" ] && { echo "错误：找不到仓库根目录" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

f="$(find packages -maxdepth 5 -path "*/$PKG/package.mk" | head -1)"
[ -z "$f" ] && { echo "错误：找不到 $PKG 的 package.mk" >&2; exit 1; }
gv() { grep -h "^$1=" "$f" | head -1 | sed "s/^$1=//; s/^\"//; s/\"$//"; }

PKG_NAME="$(gv PKG_NAME)"; PKG_NAME="${PKG_NAME:-$PKG}"
PKG_VERSION="$(gv PKG_VERSION)"
PKG_SITE="$(gv PKG_SITE)"
PKG_SHA256="$(gv PKG_SHA256)"
URL="$(gv PKG_URL)"
for v in PKG_SITE PKG_VERSION PKG_NAME; do
  eval "val=\$$v"
  URL="${URL//\$\{$v\}/$val}"; URL="${URL//\$$v/$val}"
done

echo "== $PKG  (name=$PKG_NAME ver=$PKG_VERSION)"
echo "   url=$URL"
if [ -z "$URL" ]; then echo "   （该包没有 PKG_URL，可能只是元包，无需源码）"; exit 0; fi

SRC="$REPO_ROOT/sources/$PKG"
mkdir -p "$SRC"

HOST="$(printf '%s' "$URL" | sed 's|^[a-z]*://||; s|/.*||')"
if [ "$HOST" = "github.com" ]; then FETCH_URL="${PROXY_PREFIX}${URL}"; else FETCH_URL="$URL"; fi
echo "   host=$HOST  传输=$([ "$HOST" = github.com ] && echo "镜像 $MIRROR_BASE" || echo 直连)"

case "$URL" in
# ============================== git 源 ==============================
*.git)
  WORK="/tmp/seed-$PKG"; CLONE="$WORK/clone"; PACK="$WORK/pack"
  rm -rf "$WORK"; mkdir -p "$CLONE"
  git -C "$CLONE" init -q .
  git -C "$CLONE" remote add origin "$FETCH_URL"
  ok=0
  for i in 1 2 3 4; do
    echo "-- fetch 尝试 $i/4"
    if timeout 600 git -C "$CLONE" fetch --depth 1 origin "$PKG_VERSION" </dev/null; then ok=1; break; fi
    echo "   失败，10s 后重试"; sleep 10
  done
  [ "$ok" = 1 ] || { echo "!! fetch 失败（镜像 $MIRROR_BASE 也拿不到，可试 MIRROR_BASE=$MIRROR_FALLBACK）"; exit 1; }
  git -C "$CLONE" checkout -q FETCH_HEAD </dev/null
  got="$(git -C "$CLONE" rev-parse HEAD)"
  echo "   got=$got"
  [ "$got" = "$PKG_VERSION" ] || { echo "!! commit 不匹配，拒绝写缓存"; exit 1; }

  SKIP_SUB="$(gv PKG_GIT_SKIP_SUBMODULE)"
  if [ -f "$CLONE/.gitmodules" ] && [ "$SKIP_SUB" != "yes" ]; then
    echo "   含 .gitmodules -> 拉取子模块（递归，github 子模块自动走镜像）"
    git -C "$CLONE" config --file .gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null \
    | while read -r key val; do
        name="${key#submodule.}"; name="${name%.url}"
        case "$val" in https://github.com/*) new="${PROXY_PREFIX}${val}" ;; *) new="$val" ;; esac
        git -C "$CLONE" config "submodule.${name}.url" "$new"
      done
    # -c 配置会传给子进程，因此嵌套子模块（如 flycast -> glslang -> SPIRV-Tools）也能走镜像
    if ! timeout 1800 git -C "$CLONE" \
           -c url."${PROXY_PREFIX}https://github.com/".insteadOf="https://github.com/" \
           submodule update --init --recursive --depth 1 </dev/null; then
      echo "!! 子模块拉取失败"; exit 1
    fi
    echo "   子模块完成"
  fi

  DEST="$PACK/${PKG}-${PKG_VERSION}"
  rm -rf "$PACK"; mkdir -p "$DEST"
  ( cd "$CLONE" && tar -cf - --exclude=.git . ) | tar -xf - -C "$DEST"
  rm -f "$SRC"/${PKG}-*.tar.xz "$SRC"/${PKG}-*.tar.xz.gitstamp
  tar --create --file "$SRC/${PKG}-${PKG_VERSION}.tar.xz" --xz --directory="$PACK" "${PKG}-${PKG_VERSION}"
  printf '%s|%s\n' "$URL" "$PKG_VERSION" > "$SRC/${PKG}-${PKG_VERSION}.tar.xz.gitstamp"
  ;;

# ============================== 归档源 ==============================
*)
  base="${URL##*/}"
  case "$base" in
    ${PKG_NAME}-${PKG_VERSION}.*)            NAME="$base" ;;
    *.tar.bz2|*.tar.gz|*.tar.xz|*.tar.zst)   NAME="${PKG_NAME}-${PKG_VERSION}.tar.${base##*.}" ;;
    *.tar|*.tbz|*.tgz|*.txz|*.tzst|*.7z|*.zip) NAME="${PKG_NAME}-${PKG_VERSION}.${base##*.}" ;;
    *)                                        NAME="${PKG_NAME}-${PKG_VERSION}.${base##*.}" ;;
  esac
  echo "   source-name=$NAME"

  TMP="/tmp/seed-$PKG-dl"; rm -f "$TMP"
  ok=0
  for u in "$FETCH_URL" "$URL" "${MIRROR_FALLBACK}/${URL}"; do
    [ "$HOST" != "github.com" ] && [ "$u" = "${MIRROR_FALLBACK}/${URL}" ] && continue
    echo "-- 下载 $u"
    if timeout 900 curl -fsSL --retry 3 --retry-delay 5 -o "$TMP" "$u" </dev/null; then ok=1; break; fi
    echo "   失败，试下一个"
  done
  [ "$ok" = 1 ] || { echo "!! 下载失败"; exit 1; }

  sz="$(stat -c %s "$TMP")"; got_sum="$(sha256sum "$TMP" | cut -d' ' -f1)"
  echo "   size=$sz  sha256=$got_sum"
  if [ -n "$PKG_SHA256" ]; then
    if [ "$PKG_SHA256" != "$got_sum" ]; then
      echo "!! SHA256 与 recipe 不符（recipe=$PKG_SHA256）—— 拒绝写缓存"; exit 1
    fi
    echo "   SHA256 与 recipe 一致 ✓"
  else
    echo "   注意：recipe 没有 PKG_SHA256，无法自动校验；建议用第二个镜像交叉比对"
  fi

  mv -f "$TMP" "$SRC/$NAME"
  printf '%s\n' "$URL"     > "$SRC/$NAME.url"
  printf '%s\n' "$got_sum" > "$SRC/$NAME.sha256"
  ;;
esac

echo "== 缓存就绪"
ls -l "$SRC"/
echo "== 验证：env PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 ./scripts/get $PKG  (期望 rc=0)"
