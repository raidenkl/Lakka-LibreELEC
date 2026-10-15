#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# One-time network setup for building this tree from mainland China.
#
# Why this exists
# ---------------
# Every pinned source of the RK3588/LubanCat port is fetched at build time:
#   u-boot/kernel/rkbin  github.com/LubanCat/*
#   libmali              github.com/tsukumijima/libmali-rockchip
#   libretro cores & co  mostly github.com, plus ftp.gnu.org, www.kernel.org, ...
# The build system downloads archives with plain `wget` (scripts/get_archive)
# and git sources with `git clone/fetch` (scripts/get_git).  When github.com is
# unreachable/slow, both paths stall with confusing retry loops.
#
# What it configures (all user-level, nothing in the repo changes):
#   1) git url.insteadOf rewrite: https://github.com/ -> <mirror>/https://github.com/
#      (covers scripts/get_git; mirrors must support the git protocol)
#   2) a wget wrapper at ~/.local/bin/wget that retries GitHub archive downloads
#      through the same mirror prefix, and falls back https -> http for other
#      hosts with broken TLS (e.g. www.kernel.org).  Integrity is unaffected:
#      every download is still verified against PKG_SHA256.
#
# Usage:
#   ./setup-cn-network.sh                 install (default mirror: gh-proxy.com)
#   ./setup-cn-network.sh -m https://ghfast.top [more mirrors...]
#   ./setup-cn-network.sh -u              undo everything
# If you have a real proxy, you don't need this script at all - just export
# http_proxy/https_proxy and git will honour them.

set -eu

MIRRORS="https://gh-proxy.com"
UNDO="no"
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--mirrors) shift; MIRRORS="$*"; break ;;
    -u|--undo)    UNDO="yes"; shift ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

WRAPPER="${HOME}/.local/bin/wget"

# the first mirror is used for both git and wget
FIRST="${MIRRORS%% *}"

if [ "$UNDO" = "yes" ]; then
  git config --global --unset-all "url.${FIRST}/https://github.com/.insteadof" 2>/dev/null || true
  rm -f "$WRAPPER"
  echo "undone: git insteadOf for ${FIRST} removed, $WRAPPER removed"
  exit 0
fi

# ---------------------------------------------------------------- 1) git ----
# mirrors must support git clone/fetch; drop ones that don't (kept simple: use
# the first mirror for git).
git config --global "url.${FIRST}/https://github.com/.insteadOf" "https://github.com/"
echo "git:    https://github.com/  ->  ${FIRST}/https://github.com/"

# --------------------------------------------------------------- 2) wget ----
mkdir -p "$(dirname "$WRAPPER")"
cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/bin/bash
# wget wrapper (installed by setup-cn-network.sh) for unreachable hosts.
# GitHub is retried through mirror prefixes; other hosts get an https->http
# retry (GitHub enforces HSTS so the downgrade only helps non-GitHub hosts).
# LibreELEC verifies PKG_SHA256 afterwards, so mirrors cannot corrupt anything.

REAL_WGET="${REAL_WGET:-/usr/bin/wget}"
LOG="${WGET_MIRROR_LOG:-/tmp/wget-gh-mirror.log}"
MIRRORS="${WGET_MIRRORS:-__MIRRORS__}"
GH_HOSTS="github.com codeload.github.com raw.githubusercontent.com objects.githubusercontent.com gist.githubusercontent.com"

args=("$@")
idx=-1
for i in "${!args[@]}"; do
  case "${args[$i]}" in http://*|https://*) idx=$i; break ;; esac
done
[ "$idx" -lt 0 ] && exec "$REAL_WGET" "$@"

url="${args[$idx]}"
host="$(printf '%s' "$url" | sed 's|^[a-z]*://||; s|/.*||')"

outfile=""
for i in "${!args[@]}"; do
  case "${args[$i]}" in -O|--output-document) outfile="${args[$((i+1))]}" ;; esac
done

log() { printf '%s  %s  %s\n' "$(date '+%F %T')" "$1" "$2" >>"$LOG" 2>/dev/null; }

args_nocont=()
for a in "${args[@]}"; do
  case "$a" in -c|--continue) ;; *) args_nocont+=("$a") ;; esac
done

attempt() { # $1 = url, $2 = "" | "nocont"
  local u="$1" a=()
  if [ "$2" = "nocont" ]; then a=("${args_nocont[@]}"); else a=("${args[@]}"); fi
  a[$idx]="$u"
  "$REAL_WGET" "${a[@]}"
}

is_gh=0
for h in $GH_HOSTS; do [ "$host" = "$h" ] && is_gh=1 && break; done

if [ "$is_gh" = 1 ]; then
  for m in $MIRRORS; do
    log "MIRROR" "$m/$url"
    [ -n "$outfile" ] && rm -f "$outfile"
    attempt "$m/$url" nocont && exit 0
  done
  log "DIRECT" "$url"
  [ -n "$outfile" ] && rm -f "$outfile"
  attempt "$url" nocont && exit 0
  echo "wget wrapper: all attempts failed for $url" >&2
  exit 1
fi

attempt "$url" "" && exit 0
case "$url" in
  https://*)
    http_url="${url/https:/http:}"
    log "HTTP-FALLBACK" "$http_url"
    [ -n "$outfile" ] && rm -f "$outfile"
    attempt "$http_url" nocont && exit 0
    ;;
esac
echo "wget wrapper: all attempts failed for $url" >&2
exit 1
WRAPPER_EOF
sed -i "s#__MIRRORS__#${MIRRORS}#" "$WRAPPER"
chmod +x "$WRAPPER"
echo "wget:   $WRAPPER installed (mirrors: ${MIRRORS})"

# ------------------------------------------------------------- 3) PATH ------
case ":${PATH}:" in
  *":$(dirname "$WRAPPER"):") ;;
  *) echo "note:   add this to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

cat <<'HINT'

done.  Verify with:
  git config --global --get-regexp insteadof
  PATH="$HOME/.local/bin:$PATH" wget -O /tmp/t https://raw.githubusercontent.com/git/git/v2.39.0/README.md && head -1 /tmp/t

Undo anytime with:  ./setup-cn-network.sh -u
HINT
