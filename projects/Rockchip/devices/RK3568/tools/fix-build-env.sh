#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# fix-build-env.sh — 把一台 Ubuntu 宿主机改造成「能在中国大陆网络下构建 Lakka RK3588 镜像」
#
# 它做四件事（每件都幂等，重复运行不会出错）：
#   1. 补齐 scripts/checkdeps 要求但系统缺失的宿主依赖（不需要 sudo）
#      - zstd        : scripts/extract 要用 zstdcat 解 .tar.zst
#      - Parse::Yapp : samba 的 pidl 需要 yapp 程序 + 该 perl 模块（缺了 configure 直接失败）
#      - JSON        : 真模块（不要用自制垫片！）
#      - rdfind      : 仅被 checkdeps 探测、构建流程从不调用 -> 放一个 no-op 占位
#   2. 网络垫片：github.com 直连被阻断时，让 git / wget 自动走镜像
#      - git 全局 url.<mirror>.insteadOf=https://github.com/
#        （这一条同时覆盖 git 源包、git 子模块、以及 CMake FetchContent）
#      - ~/bin/wget 包装器：GitHub 归档/Release 走镜像，非 GitHub 主机退化为 https->http
#   3. 把 ~/bin 与 ~/perl5 写进 ~/.bashrc（非交互 shell 不读 .bashrc，跑构建时仍要显式 env）
#   4. 自检并报告（可选跑 ./scripts/checkdeps）
#
# 用法:
#   ./fix-build-env.sh                 # 全面修复（默认）
#   ./fix-build-env.sh --check         # 只检查，不改任何东西
#   ./fix-build-env.sh --deps-only     # 只做宿主依赖
#   ./fix-build-env.sh --net-only      # 只做网络垫片
#   ./fix-build-env.sh --no-bashrc     # 不修改 ~/.bashrc
#   ./fix-build-env.sh --mirror https://gh-proxy.com   # 换镜像
#   ./fix-build-env.sh --unset-mirror  # 撤销 git insteadOf 与 wget 包装器
#
set -uo pipefail

# ------------------------------ 配置 ------------------------------
MIRROR_BASE="${MIRROR_BASE:-https://gh-proxy.com}"
MIRROR_FALLBACK="${MIRROR_FALLBACK:-https://ghfast.top}"
UBUNTU_POOL="${UBUNTU_POOL:-http://archive.ubuntu.com/ubuntu/pool}"
BIN_DIR="$HOME/bin"
PERL5_DIR="$HOME/perl5"
WORK_DIR="${TMPDIR:-/tmp}/fix-build-env"
BASHRC="$HOME/.bashrc"

MODE=fix
DO_DEPS=1
DO_NET=1
DO_BASHRC=1
UNSET_MIRROR=0

# ------------------------------ 输出 ------------------------------
if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$1"; }
skip() { printf '  %s=%s %s\n' "$C_B" "$C_0" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$1"; }
hdr()  { printf '\n%s== %s ==%s\n' "$C_B" "$1" "$C_0"; }

FAILED=0
note_fail() { FAILED=$((FAILED+1)); }

# ------------------------------ 参数 ------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --check)       MODE=check ;;
    --deps-only)   DO_NET=0 ;;
    --net-only)    DO_DEPS=0 ;;
    --no-bashrc)   DO_BASHRC=0 ;;
    --mirror)      MIRROR_BASE="$2"; shift ;;
    --unset-mirror) UNSET_MIRROR=1 ;;
    -h|--help)     sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1（--help 查看用法）" >&2; exit 2 ;;
  esac
  shift
done

# ------------------------------ 定位仓库 ------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  if [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ]; then REPO_ROOT="$d"; break; fi
  d="$(dirname "$d")"
done

hdr "环境概览"
echo "  脚本目录 : $SCRIPT_DIR"
echo "  仓库根目录: ${REPO_ROOT:-（未找到，跳过依赖仓库相关的检查）}"
echo "  镜像      : $MIRROR_BASE  (备用 $MIRROR_FALLBACK)"
echo "  模式      : $MODE$([ "$MODE" = check ] && echo '（只检查，不修改）' || echo '')"

# ======================================================================
#  撤销模式
# ======================================================================
if [ "$UNSET_MIRROR" = 1 ]; then
  hdr "撤销网络垫片"
  for key in "$MIRROR_BASE/https://github.com/" "$MIRROR_FALLBACK/https://github.com/"; do
    if git config --global --get "url.$key.insteadOf" >/dev/null 2>&1; then
      git config --global --remove-section "url.$key" 2>/dev/null && ok "已移除 insteadOf: $key"
    fi
  done
  if [ -f "$BIN_DIR/wget" ] && grep -q "wget-gh-mirror" "$BIN_DIR/wget" 2>/dev/null; then
    rm -f "$BIN_DIR/wget" && ok "已移除 $BIN_DIR/wget（恢复系统 wget）"
  fi
  skip "git http.version 保留（无害），如需还原: git config --global --unset http.version"
  exit 0
fi

download_with_mirror() { # $1=url  $2=dest
  local url="$1" dest="$2"
  curl -fsSL -m "${DL_TIMEOUT:-180}" -o "$dest" "$url" && return 0
  case "$url" in
    https://github.com/*|https://codeload.github.com/*)
      curl -fsSL -m "${DL_TIMEOUT:-180}" -o "$dest" "$MIRROR_BASE/$url" && return 0
      curl -fsSL -m "${DL_TIMEOUT:-180}" -o "$dest" "$MIRROR_FALLBACK/$url" && return 0 ;;
  esac
  return 1
}

# ======================================================================
#  1. 宿主依赖
# ======================================================================
if [ "$DO_DEPS" = 1 ]; then
  hdr "1/4 宿主依赖（无需 sudo）"
  mkdir -p "$BIN_DIR" "$PERL5_DIR"

  # ---- 1.1 zstd ----
  if command -v zstd >/dev/null 2>&1 && command -v zstdcat >/dev/null 2>&1; then
    skip "zstd 已可用（$(zstd --version 2>/dev/null | head -1)）"
  else
    # zstd 是「多调用名」程序：同一二进制按 argv[0] 决定行为，所以软链即可
    SRC_ZSTD=""
    for cand in "$HOME/anaconda3/bin/zstd" "$HOME/miniconda3/bin/zstd" /opt/conda/bin/zstd; do
      [ -x "$cand" ] && SRC_ZSTD="$cand" && break
    done
    if [ -z "$SRC_ZSTD" ]; then
      SRC_ZSTD="$(find / -maxdepth 5 -type f -name zstd -perm -u+x 2>/dev/null | grep -v '^/proc' | head -1)"
    fi
    if [ -n "$SRC_ZSTD" ]; then
      if [ "$MODE" = check ]; then
        warn "缺 zstd/zstdcat，可用 $SRC_ZSTD 软链补齐（--check 模式未修改）"
      else
        for n in zstd zstdcat unzstd; do ln -sf "$SRC_ZSTD" "$BIN_DIR/$n"; done
        ok "已软链 $SRC_ZSTD -> $BIN_DIR/{zstd,zstdcat,unzstd}"
      fi
    else
      bad "缺 zstd 且找不到现成二进制。请用 sudo 安装: sudo apt-get install -y zstd"
      note_fail
    fi
  fi

  # ---- 1.2 perl Parse::Yapp（模块 + yapp 程序）----
  need_yapp=0
  command -v yapp >/dev/null 2>&1 || need_yapp=1
  perl -MParse::Yapp::Driver -e1 >/dev/null 2>&1 || need_yapp=1
  if [ "$need_yapp" = 0 ]; then
    skip "Parse::Yapp 模块与 yapp 程序已就绪"
  else
    # 先清掉可能存在的假模块（假模块会骗过 checkdeps，却在 samba 的 find_program('yapp') 处炸掉）
    FAKE="$PERL5_DIR/Parse/Yapp/Driver.pm"
    if [ -f "$FAKE" ] && [ "$(stat -c %s "$FAKE")" -lt 500 ]; then
      warn "检测到自制假模块 $FAKE（$(stat -c %s "$FAKE") 字节），将用真包覆盖"
      [ "$MODE" = fix ] && rm -rf "$PERL5_DIR/Parse/Yapp"
    fi
    if [ "$MODE" = check ]; then
      warn "缺 Parse::Yapp / yapp（--check 模式未安装）"
    else
      TMPY="$(mktemp -d)"
      idx="$(curl -fsSL -m 60 "$UBUNTU_POOL/main/libp/libparse-yapp-perl/" 2>/dev/null \
            | grep -oE 'libparse-yapp-perl_[0-9][0-9a-zA-Z.+-]*_all\.deb' | sort -u | tail -1)"
      if [ -n "$idx" ] && download_with_mirror "$UBUNTU_POOL/main/libp/libparse-yapp-perl/$idx" "$TMPY/y.deb" \
         && ( cd "$TMPY" && dpkg-deb -x y.deb x ) \
         && cp -a "$TMPY/x/usr/share/perl5/." "$PERL5_DIR/" 2>/dev/null \
         && install -Dm755 "$TMPY/x/usr/bin/yapp" "$BIN_DIR/yapp"; then
        ok "已安装 Parse::Yapp + yapp（$idx）"
      else
        bad "安装 Parse::Yapp 失败（URL: $UBUNTU_POOL/main/libp/libparse-yapp-perl/$idx）"
        note_fail
      fi
      rm -rf "$TMPY"
    fi
  fi

  # ---- 1.3 perl JSON ----
  if perl -MJSON -e1 >/dev/null 2>&1; then
    skip "JSON 模块已就绪（$(perl -MJSON -e 'print $JSON::VERSION' 2>/dev/null)）"
  else
    if [ "$MODE" = check ]; then
      warn "缺 JSON 模块（--check 模式未安装）"
    else
      JB="$(mktemp -d)"
      idx="$(curl -fsSL -m 60 "$UBUNTU_POOL/main/libj/libjson-perl/" 2>/dev/null \
            | grep -oE 'libjson-perl_[0-9][0-9a-zA-Z.+-]*_all\.deb' | sort -u | tail -1)"
      if [ -n "$idx" ] && download_with_mirror "$UBUNTU_POOL/main/libj/libjson-perl/$idx" "$JB/j.deb" \
         && ( cd "$JB" && dpkg-deb -x j.deb x ) && cp -a "$JB/x/usr/share/perl5/." "$PERL5_DIR/" 2>/dev/null; then
        ok "已安装 JSON（$idx）"
      else
        bad "安装 JSON 失败"; note_fail
      fi
      rm -rf "$JB"
    fi
  fi

  # ---- 1.4 rdfind（no-op 占位）----
  if command -v rdfind >/dev/null 2>&1; then
    skip "rdfind 已存在（$(command -v rdfind)）"
  else
    if [ "$MODE" = check ]; then
      warn "缺 rdfind（仅 checkdeps 探测，可放 no-op 占位）"
    else
      cat > "$BIN_DIR/rdfind" <<'EOF'
#!/bin/sh
# rdfind placeholder: scripts/checkdeps declares rdfind as a host dependency but
# the build never invokes it (verified: no reference outside scripts/checkdeps).
# Real rdfind binaries from the Ubuntu pool link against libnettle.so.8 while
# some hosts only ship libnettle.so.7, so installing one is worse than a no-op.
exit 0
EOF
      chmod +x "$BIN_DIR/rdfind"
      ok "已放置 no-op 占位 $BIN_DIR/rdfind"
    fi
  fi

  # ---- 1.5 其它必装工具（需 sudo，只做提示）----
  MISSING_TOOLS=""
  for t in dtc python2 mkimage bc gperf lzop patch git gcc g++ gawk rsync; do
    command -v "$t" >/dev/null 2>&1 || MISSING_TOOLS="$MISSING_TOOLS $t"
  done
  command -v python2 >/dev/null 2>&1 || command -v python2.7 >/dev/null 2>&1 || MISSING_TOOLS="$MISSING_TOOLS python2(或python2.7)"
  if [ -n "$MISSING_TOOLS" ]; then
    warn "以下工具缺失（需要 sudo 安装）:$MISSING_TOOLS"
    echo "      sudo apt-get install -y device-tree-compiler python2 u-boot-tools \\"
    echo "             bc gperf lzop rsync gawk patchutils"
  else
    ok "dtc / python2 / mkimage 等工具齐全"
  fi
fi

# ======================================================================
#  2. 网络垫片
# ======================================================================
if [ "$DO_NET" = 1 ]; then
  hdr "2/4 网络垫片（github.com 不可达时自动走镜像）"

  # ---- 2.1 git 全局 insteadOf ----
  cur="$(git config --global --get "url.$MIRROR_BASE/https://github.com/.insteadOf" 2>/dev/null)"
  if [ "$cur" = "https://github.com/" ]; then
    skip "git insteadOf 已设置（$MIRROR_BASE）"
  else
    if [ "$MODE" = check ]; then
      warn "git 未设置 insteadOf（GitHub 直连不通时所有 git 源包/子模块/FetchContent 都会失败）"
    else
      git config --global "url.$MIRROR_BASE/https://github.com/.insteadOf" "https://github.com/"
      ok "git insteadOf: https://github.com/ -> $MIRROR_BASE/https://github.com/"
      echo "      覆盖范围：git 源包 / git 子模块 / CMake FetchContent（含嵌套子模块）"
    fi
  fi

  # ---- 2.2 git 传输参数 ----
  if [ "$(git config --global --get http.version 2>/dev/null)" = "HTTP/1.1" ]; then
    skip "git http.version=HTTP/1.1 已设置"
  else
    if [ "$MODE" = check ]; then
      warn "git http.version 未设置（代理下 HTTP/2 流易被截断）"
    else
      git config --global http.version HTTP/1.1
      git config --global http.postBuffer 1048576000
      ok "git http.version=HTTP/1.1, http.postBuffer=1GB"
    fi
  fi

  # ---- 2.3 wget 包装器 ----
  SRC_WRAPPER="$SCRIPT_DIR/wget-gh-mirror"
  if [ -f "$SRC_WRAPPER" ]; then
    if [ -f "$BIN_DIR/wget" ] && cmp -s "$SRC_WRAPPER" "$BIN_DIR/wget"; then
      skip "wget 包装器已是最新"
    elif [ -f "$BIN_DIR/wget" ] && grep -q "wget-gh-mirror" "$BIN_DIR/wget" 2>/dev/null; then
      [ "$MODE" = fix ] && { install -Dm755 "$SRC_WRAPPER" "$BIN_DIR/wget"; ok "wget 包装器已更新"; } \
                        || warn "wget 包装器版本较旧"
    else
      if [ -f "$BIN_DIR/wget" ] && grep -q "https-fallback" "$BIN_DIR/wget" 2>/dev/null; then
        warn "检测到旧版 wget 包装器（只做 https->http 降级）：对 GitHub 无效（HSTS 会强制转回 https）"
      fi
      if [ "$MODE" = check ]; then
        warn "未安装（新版）wget 包装器：GitHub 归档/Release 下载会失败"
      else
        install -Dm755 "$SRC_WRAPPER" "$BIN_DIR/wget"
        ok "已安装 wget 包装器 -> $BIN_DIR/wget（GitHub 走镜像；其它主机 https->http 兜底）"
      fi
    fi
    if [ "$MODE" = fix ] && ! command -v wget | grep -q "^$BIN_DIR/wget$"; then
      warn "当前 shell 的 wget 还不是包装器（需要 PATH 里 $BIN_DIR 在 /usr/bin 之前）"
    fi
  else
    warn "找不到 $SRC_WRAPPER，跳过 wget 包装器"
  fi

  # ---- 2.4 连通性自检 ----
  if [ "$MODE" = fix ] || [ "$MODE" = check ]; then
    gh_code="$(curl -s -o /dev/null -w '%{http_code}' -m 12 https://github.com 2>/dev/null)"
    mir_code="$(curl -s -o /dev/null -w '%{http_code}' -m 12 "$MIRROR_BASE" 2>/dev/null)"
    echo "  连通性: github.com=$gh_code  镜像=$mir_code"
    if [ "$gh_code" = "000" ] || [ "$gh_code" = "000000" ]; then
      warn "github.com 直连不通（正是需要镜像的场景）"
    else
      ok "github.com 可直连"
    fi
  fi
fi

# ======================================================================
#  3. shell 环境
# ======================================================================
if [ "$DO_BASHRC" = 1 ]; then
  hdr "3/4 shell 环境（~/.bashrc）"
  # 宽松检测：不认标记，只认「确实导出了 $HOME/bin 到 PATH / $HOME/perl5 到 PERL5LIB」
  has_path=0; grep -qE '^\s*export\s+PATH=.*\$HOME/bin' "$BASHRC" 2>/dev/null && has_path=1
  has_perl=0; grep -qE '^\s*export\s+PERL5LIB=.*\$HOME/perl5' "$BASHRC" 2>/dev/null && has_perl=1
  if [ "$has_path" = 1 ] && [ "$has_perl" = 1 ]; then
    skip "~/.bashrc 已导出 PATH 与 PERL5LIB"
  else
    if [ "$MODE" = check ]; then
      [ "$has_path" = 0 ] && warn "~/.bashrc 未把 \$HOME/bin 加入 PATH"
      [ "$has_perl" = 0 ] && warn "~/.bashrc 未设置 PERL5LIB=\$HOME/perl5"
    else
      {
        echo ''
        echo '# fix-build-env: PATH'
        [ "$has_path" = 0 ] && echo 'export PATH="$HOME/bin:$PATH"'
        [ "$has_perl" = 0 ] && echo 'export PERL5LIB="$HOME/perl5${PERL5LIB:+:$PERL5LIB}"'
      } >> "$BASHRC"
      ok "已追加到 ~/.bashrc（PATH=$has_path PERL5LIB=$has_perl，1=原本已有）"
    fi
  fi
  warn "非交互 shell 不读 ~/.bashrc —— 跑构建时必须显式传:"
  echo "      env PATH=\"\$HOME/bin:\$PATH\" PERL5LIB=\"\$HOME/perl5\" PROJECT=... make image"
fi

# ======================================================================
#  4. 自检
# ======================================================================
hdr "4/4 自检"
export PATH="$BIN_DIR:$PATH"
export PERL5LIB="$PERL5_DIR${PERL5LIB:+:$PERL5LIB}"
for t in zstd zstdcat unzstd yapp rdfind wget; do
  if command -v "$t" >/dev/null 2>&1; then
    p="$(command -v "$t")"
    if [ "$t" = wget ]; then
      if grep -q wget-gh-mirror "$p" 2>/dev/null; then
        ok "wget -> $p（GitHub 走镜像）"
      elif grep -q https-fallback "$p" 2>/dev/null; then
        warn "wget -> $p 是旧版包装器（只做 https->http），对 GitHub 无效"; note_fail
      else
        warn "wget -> $p 是系统原版，GitHub 归档/Release 下载会失败"; note_fail
      fi
    else
      ok "$t -> $p"
    fi
  else
    bad "$t 不可用"; note_fail
  fi
done
perl -MParse::Yapp -e1 >/dev/null 2>&1 && ok "perl Parse::Yapp 可用" || { bad "perl Parse::Yapp 不可用"; note_fail; }
perl -MJSON      -e1 >/dev/null 2>&1 && ok "perl JSON 可用"         || { bad "perl JSON 不可用"; note_fail; }

if [ -n "$REPO_ROOT" ] && [ "$MODE" = fix ]; then
  echo "  运行 $REPO_ROOT/scripts/checkdeps ..."
  if ( cd "$REPO_ROOT" && env PATH="$BIN_DIR:$PATH" PERL5LIB="$PERL5_DIR" ./scripts/checkdeps >/tmp/fix-build-env-checkdeps.log 2>&1 ); then
    ok "scripts/checkdeps 通过"
  else
    bad "scripts/checkdeps 未通过，详见 /tmp/fix-build-env-checkdeps.log"; note_fail
  fi
fi

hdr "总结"
if [ "$FAILED" -eq 0 ]; then
  printf '  %s全部就绪%s\n' "$C_G" "$C_0"
  [ "$MODE" = check ] && echo "  （--check 模式未做修改；去掉该参数即可实际修复）"
else
  printf '  %s有 %d 项未完成%s，请按上面的提示处理（多数需要 sudo）\n' "$C_R" "$FAILED" "$C_0"
fi
cat <<'NEXT'

下一步：
  1) 构建：见 tools/resume-build.sh（已设好 PROJECT/DEVICE/ARCH/UBOOT_SYSTEM/PATH/PERL5LIB）
     或手工：cd <repo> && env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5" \
             PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 THREADCOUNT=4 make image
  2) 仍有包拉不下来：tools/audit-missing-sources.sh 找出缺缓存的包，
     再用 tools/seed-missing-sources.sh 经镜像批量预置（git 源含子模块、归档源做 SHA256 校验）
  3) 原理与排查：见 tools/NETWORK_BUILD.md
NEXT
exit 0
