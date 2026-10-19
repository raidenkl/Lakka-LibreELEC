#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# mk-rockchip-update.sh -- package a built Lakka/LibreELEC RK3588 (LubanCat 5)
# image into a *Rockchip standard* firmware package (update.img / RKFW), so it
# can be flashed with the vendor tooling instead of hand-written LBA tables:
#
#   RKDevTool  -> [Upgrade Firmware] (升级固件) -> 打开 update.img -> 执行
#   upgrade_tool uf update.img            (Linux, maskrom)
#
# Why this exists
#   RKDevTool's "Download Image" page needs manual LBA bookkeeping and its
#   "Boot" row defaults to 0x00004000 (= 8 MiB), which is exactly where our
#   uboot.img (FIT) has to live - an easy way to silently clobber it.  Its
#   "Upgrade Firmware" page only accepts a Rockchip packed image (RKFW), which
#   LibreELEC/Lakka never produces.  This script bridges that gap by reusing
#   the partitions of the normal Lakka image plus Rockchip's packing tools
#   afptool / rkImageMaker.  Those are Rockchip's closed-source but freely
#   redistributed binaries (statically linked x86-64, no library dependencies);
#   a copy is vendored in tools/rkfw/ next to this script, so no Firefly /
#   LubanCat SDK is required.  Pass --sdk to use an SDK's own copies instead.
#
#   Modeled on the SDK's own device/rockchip/common/scripts/mk-updateimg.sh and
#   Linux_Pack_Firmware/rockdev/rk3588-mkupdate.sh:
#
#     afptool -pack ./ Image/update.img
#     rkImageMaker -RK3588 Image/MiniLoaderAll.bin Image/update.img update.img \
#                  -os_type:androidos
#
# Resulting layout - identical to the Lakka raw image *and* to the vendor's
# device/rockchip/.chips/rk3588/parameter-extboot.txt:
#
#   LBA 0x40   (32 KiB)  MiniLoaderAll.bin  DDR + SPL      (written by flasher)
#   0x00004000 (8 MiB)   uboot.img          FIT (u-boot + BL31/BL32)
#   0x00008000 (16 MiB)  boot               FAT32: extlinux.conf/KERNEL/SYSTEM/dtb
#   ...                  rootfs             ext4:  STORAGE (grow to fill device)
#
# The loader and the FIT are taken from the build tree, so simply re-run this
# script after rebuilding u-boot (see --loader / --uboot to override).

set -euo pipefail

DEVICE="${DEVICE:-RK3576}"
BOARD="${UBOOT_SYSTEM:-}"       # UBOOT_SYSTEM, e.g. lubancat-4 (see --board)
ROCKCHIP_CHIP="${ROCKCHIP_CHIP:-}"   # resolved after argument parsing, see below

SELF="$(basename "$0")"

# ------------------------------------------------------------------ helpers --
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $SELF [options]

  --img <file>      source Lakka image (.img.gz).  Default: newest
                    target/Lakka-${DEVICE}.aarch64-*.img.gz
                    (see --board to pick one board's image explicitly)
  --board <name>    board / UBOOT_SYSTEM the image was built for, e.g.
                    lubancat-5-v2, lubancat-5io, lubancat-4.
                    Default: newest image of any board.  Several boards of one
                    chip share target/, so always pass this when more than one
                    board has been built, otherwise the newest *.img.gz wins.
  --model <name>    Rockchip chip name for the RKFW header (-RK3588) and for
                    MACHINE_MODEL in parameter.txt.  Default: derived from
                    DEVICE (RK3566/RK3568 -> RK3568, otherwise DEVICE).
  --loader <file>   MiniLoaderAll / SPL loader (DDR+SPL).  Default: newest
                    <build>/install_pkg/u-boot-*/usr/share/bootloader/*_loader_*.bin
  --uboot <file>    uboot.img (FIT).  Default: same directory as --loader
  --sdk <dir>       LubanCat SDK root, to use its own afptool/rkImageMaker
                    instead of the copy vendored in tools/rkfw/.  Optional -
                    the vendored tools are statically linked and need no SDK.
  --out <dir>       output directory.  Default: <repo>/target
  --work <dir>      scratch directory.  Default: <repo>/target/.rkupdate
  --keep            keep the scratch directory (useful for debugging)
  -h | --help       this text

Rebuild u-boot, then just re-run this script: the loader and uboot.img are
picked up from the build tree automatically.

Flash the result with RKDevTool's [Upgrade Firmware] page, or on Linux:
    sudo <sdk>/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool uf <update.img>
EOF
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
newest()   { ls -1t $1 2>/dev/null | head -1 || true; }

# ------------------------------------------------------------- locate repo --
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  [ -f "$d/scripts/build" ] && [ -f "$d/Makefile" ] && { REPO="$d"; break; }
  d="$(dirname "$d")"
done
[ -n "$REPO" ] || die "cannot locate the LibreELEC/Lakka repository root above $SCRIPT_DIR"
cd "$REPO"

# 多 build 目录并存时按 DEVICE 定位，否则会取到别的芯片的 loader/uboot.img
BUILD_DIR="build.Lakka-${DEVICE}.aarch64"
[ -d "${BUILD_DIR}" ] || BUILD_DIR="$(ls -d build.Lakka-*.aarch64 2>/dev/null | head -1 || true)"
[ -n "$BUILD_DIR" ] || die "no build.Lakka-*.aarch64 directory - build the image first"

IMG=""; LOADER=""; UBOOT=""; SDK_DIR=""   # --sdk overrides the vendored tools
OUT_DIR=""; WORK_DIR=""; KEEP="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --img)    IMG="$2"; shift 2 ;;
    --board)  BOARD="$2"; shift 2 ;;
    --model)  ROCKCHIP_CHIP="$2"; shift 2 ;;
    --loader) LOADER="$2"; shift 2 ;;
    --uboot)  UBOOT="$2"; shift 2 ;;
    --sdk)    SDK_DIR="$2"; shift 2 ;;
    --out)    OUT_DIR="$2"; shift 2 ;;
    --work)   WORK_DIR="$2"; shift 2 ;;
    --keep)   KEEP="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# Rockchip chip name used for the RKFW header (-RK3588) and for MACHINE_MODEL in
# parameter.txt.  RK3566 and RK3568 share one vendor chip directory and the
# vendor parameter-extboot.txt there says RK3568, so normalise that pair; every
# other chip uses its own name.  --model / $ROCKCHIP_CHIP override this.
if [ -z "$ROCKCHIP_CHIP" ]; then
  case "$DEVICE" in
    RK3566|RK3568) ROCKCHIP_CHIP="RK3568" ;;
    *)             ROCKCHIP_CHIP="$DEVICE" ;;
  esac
fi

# ------------------------------------------------------------- resolve in --
if [ -n "$IMG" ]; then
  [ -f "$IMG" ] || die "source image not found: $IMG"
elif [ -n "$BOARD" ]; then
  IMG="$(newest "$REPO/target/Lakka-${DEVICE}.aarch64-*-${BOARD}.img.gz")"
  [ -n "$IMG" ] || die "no image for board '$BOARD' (expected target/Lakka-${DEVICE}.aarch64-*-${BOARD}.img.gz)"
else
  IMG="$(newest "$REPO/target/Lakka-${DEVICE}.aarch64-*.img.gz")"
  [ -n "$IMG" ] || die "no source image found (use --img or --board)"
  if [ "$(ls -1 "$REPO"/target/Lakka-${DEVICE}.aarch64-*-lubancat-*.img.gz 2>/dev/null | wc -l)" -gt 1 ]; then
    warn "several boards' images exist - consider --board <name> to avoid picking the newest one"
  fi
fi

if [ -z "$LOADER" ]; then
  LOADER="$(newest "$BUILD_DIR/install_pkg/u-boot-*/usr/share/bootloader/*_loader_*.bin")"
fi
[ -n "$LOADER" ] && [ -f "$LOADER" ] || die "no loader found (use --loader)"

[ -n "$UBOOT" ] || UBOOT="$(dirname "$LOADER")/uboot.img"
[ -f "$UBOOT" ] || die "uboot.img not found: $UBOOT (use --uboot)"

# ------------------------------------------------- packing tools ------------
# Default: the copy vendored in tools/rkfw/ (statically linked x86-64).  An SDK
# passed via --sdk wins, for people who prefer their vendor tree's copies.
AFPT=""; RKIMM=""
if [ -n "$SDK_DIR" ]; then
  if [ -x "$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/afptool" ] && \
     [ -x "$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/rkImageMaker" ]; then
    AFPT="$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/afptool"
    RKIMM="$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/rkImageMaker"
  else
    warn "SDK has no afptool/rkImageMaker under $SDK_DIR - falling back to the vendored copy"
  fi
fi
if [ -z "$AFPT" ]; then
  AFPT="$SCRIPT_DIR/rkfw/afptool"
  RKIMM="$SCRIPT_DIR/rkfw/rkImageMaker"
fi
[ -x "$AFPT" ]  || die "afptool not found/executable: $AFPT (tools/rkfw/ missing from the checkout?)"
[ -x "$RKIMM" ] || die "rkImageMaker not found/executable: $RKIMM (tools/rkfw/ missing from the checkout?)"

OUT_DIR="${OUT_DIR:-$REPO/target}"
WORK_DIR="${WORK_DIR:-$REPO/target/.rkupdate}"
mkdir -p "$OUT_DIR" "$WORK_DIR"

STEM="$(basename "$IMG")"; STEM="${STEM%.img.gz}"
UPDATE_OUT="$OUT_DIR/${STEM}-update.img"

need_cmd gzip; need_cmd dd; need_cmd python3; need_cmd sha256sum; need_cmd strings

# ------------------------------------------------------------------ report --
log "Lakka RK3588 -> Rockchip firmware package"
info "repo        : $REPO"
info "source image: $(basename "$IMG")  ($(stat -c%s "$IMG") B)"
info "loader      : $(basename "$LOADER")  ($(stat -c%s "$LOADER") B, sha256 $(sha256sum "$LOADER" | cut -c1-16)..)"
info "uboot.img   : $(basename "$UBOOT")  ($(stat -c%s "$UBOOT") B, $(date -r "$UBOOT" '+%F %T'))"
info "pack tools : $AFPT"
info "output      : $UPDATE_OUT"

# --------------------------------------------------------- read partition --
log "reading the partition table of the source image"
MBR="$WORK_DIR/mbr.bin"
# dd stops after `count` blocks, so gzip exits with SIGPIPE (141).  That is
# expected, but pipefail would abort the script - hence `|| true` plus a size
# check instead of relying on the pipeline status.
gzip -dc "$IMG" | dd of="$MBR" bs=512 count=2 status=none || true
[ "$(stat -c%s "$MBR")" -eq 1024 ] || die "cannot read the first 1 KiB of the source image"

cat > "$WORK_DIR/mbr.py" <<'PY'
import struct, sys
raw = open(sys.argv[1], 'rb').read()
if raw[510:512] != b'\x55\xaa':
    sys.exit("no MBR signature - not a DOS disk image")
parts = []
for i in range(4):
    e = raw[446 + 16 * i: 446 + 16 * (i + 1)]
    ptype, start, count = e[4], struct.unpack('<I', e[8:12])[0], struct.unpack('<I', e[12:16])[0]
    if ptype and count:
        parts.append((start, count, ptype))
if len(parts) != 2:
    sys.exit("expected exactly 2 partitions, found %d" % len(parts))
(p1s, p1c, p1t), (p2s, p2c, p2t) = parts
if p1s != 0x8000:
    sys.exit("partition 1 starts at LBA 0x%x, expected 0x8000 (16 MiB)" % p1s)
if p1t not in (0x0b, 0x0c):
    sys.exit("partition 1 type is 0x%02x, expected FAT32" % p1t)
print(p1s, p1c, p2s, p2c)
PY

GEOM="$(python3 "$WORK_DIR/mbr.py" "$MBR")" || die "cannot parse the source image partition table"
read -r P1_START P1_COUNT P2_START P2_COUNT <<< "$GEOM"

P1_BYTES=$(( P1_COUNT * 512 ))
P2_BYTES=$(( P2_COUNT * 512 ))
info "boot   : LBA 0x$(printf '%x' "$P1_START")  +$P1_COUNT sectors ($(( P1_BYTES / 1024 / 1024 )) MiB)"
info "rootfs : LBA 0x$(printf '%x' "$P2_START")  +$P2_COUNT sectors ($(( P2_BYTES / 1024 / 1024 )) MiB)"

FREE_KB=$(df -Pk "$WORK_DIR" | awk 'NR==2{print $4}')
NEED_KB=$(( (P1_BYTES + P2_BYTES) * 3 / 1024 ))
[ "$FREE_KB" -gt "$NEED_KB" ] || warn "only ${FREE_KB} KiB free in $WORK_DIR (about ${NEED_KB} KiB recommended)"

# --------------------------------------------------------------- extract ---
IMG_DIR="$WORK_DIR/rockdev/Image"
rm -rf "$WORK_DIR/rockdev"
mkdir -p "$IMG_DIR"

# Decompress once and carve the partitions out of the plain file.  Piping
# `gzip -dc` into several independent readers would decompress the image
# repeatedly (and a reader that stops early makes gzip die on SIGPIPE).
FULL="$WORK_DIR/full.img"
log "decompressing the source image (~$(( (P2_START + P2_COUNT) * 512 / 1024 / 1024 )) MiB)"
gzip -dc "$IMG" > "$FULL"
FULL_BYTES=$(stat -c%s "$FULL")
EXPECT_BYTES=$(( (P2_START + P2_COUNT) * 512 ))
[ "$FULL_BYTES" -ge "$EXPECT_BYTES" ] \
  || die "decompressed image is only $FULL_BYTES B, expected at least $EXPECT_BYTES B (truncated?)"

extract_range() {
  local skip="$1" count="$2" dest="$3" got
  dd if="$FULL" of="$dest" bs=1M iflag=skip_bytes,count_bytes skip="$skip" count="$count" status=none
  got="$(stat -c%s "$dest")"
  [ "$got" -eq "$count" ] || die "short read: $dest has $got bytes, expected $count"
}

log "extracting boot.img and rootfs.img"
extract_range $(( P1_START * 512 )) "$P1_BYTES" "$IMG_DIR/boot.img"
extract_range $(( P2_START * 512 )) "$P2_BYTES" "$IMG_DIR/rootfs.img"

log "copying loader and uboot.img"
cp -f "$LOADER" "$IMG_DIR/MiniLoaderAll.bin"
cp -f "$UBOOT"  "$IMG_DIR/uboot.img"

# ---------------------------------------------------------------- uuids ----
if command -v mtype >/dev/null 2>&1; then
  CONF="$(mtype -i "$IMG_DIR/boot.img" ::/extlinux/extlinux.conf 2>/dev/null || true)"
  UUID_SYSTEM="$(printf '%s\n' "$CONF" | sed -n 's/.*boot=UUID=\([^ ]*\).*/\1/p' | head -1 || true)"
  UUID_STORAGE="$(printf '%s\n' "$CONF" | sed -n 's/.*disk=UUID=\([^ ]*\).*/\1/p' | head -1 || true)"
else
  UUID_SYSTEM=""; UUID_STORAGE=""
  warn "mtools not found - UUIDs not read back from extlinux.conf"
fi
info "uuid:boot   (FAT volume serial) = ${UUID_SYSTEM:-unknown}"
info "uuid:rootfs (ext4)             = ${UUID_STORAGE:-unknown}"

# ------------------------------------------------------- board integrity ----
# Several boards of one chip share target/, so make sure the image really is the
# board the caller asked for: its extlinux.conf must point at that board's dtb.
if [ -n "$BOARD" ] && [ -x "$REPO/scripts/uboot_helper" ]; then
  WANT_DTB="$(PROJECT="${PROJECT:-Rockchip}" "$REPO/scripts/uboot_helper" "${PROJECT:-Rockchip}" "$DEVICE" "$BOARD" dtb 2>/dev/null || true)"
  if [ -n "$WANT_DTB" ]; then
    if printf '%s\n' "$CONF" | grep -q "FDT /${WANT_DTB}$"; then
      info "board check: image uses ${WANT_DTB} (matches --board $BOARD)"
    else
      info "  $CONF"
      die "image is not for board '$BOARD': extlinux.conf has no 'FDT /${WANT_DTB}'"
    fi
  fi
fi

# ------------------------------------------------------------ parameter ----
BOOT_SZ="$(printf '0x%08x' "$P1_COUNT")"
ROOTFS_OFF="$(printf '0x%08x' "$(( P1_START + P1_COUNT ))")"

log "writing parameter.txt (GPT)"
{
  echo "FIRMWARE_VER: 1.0"
  echo "MACHINE_MODEL: ${ROCKCHIP_CHIP}"
  echo "MACHINE_ID: 007"
  echo "MANUFACTURER: ${ROCKCHIP_CHIP}"
  echo "MAGIC: 0x5041524B"
  echo "ATAG: 0x00200800"
  echo "MACHINE: 0xffffffff"
  echo "CHECK_MASK: 0x80"
  echo "PWR_HLD: 0,0,A,0,1"
  echo "TYPE: GPT"
  echo "GROW_ALIGN: 0"
  echo "CMDLINE: mtdparts=:0x00004000@0x00004000(uboot),${BOOT_SZ}@0x00008000(boot:bootable),-@${ROOTFS_OFF}(rootfs:grow)"
  # GPT PARTUUIDs only: Lakka locates the partitions by filesystem UUID, which
  # is baked into extlinux.conf, so these values are informational.
  case "$UUID_STORAGE" in
    *-*-*-*-*) echo "uuid:rootfs=${UUID_STORAGE}" ;;
  esac
  echo "uuid:boot=7A3F0000-0000-446A-8000-702F00006273"
} > "$IMG_DIR/parameter.txt"

log "writing package-file"
cat > "$WORK_DIR/rockdev/package-file" <<'EOF'
# NAME		PATH
package-file	package-file
parameter	Image/parameter.txt
bootloader	Image/MiniLoaderAll.bin
uboot		Image/uboot.img
boot		Image/boot.img
rootfs		Image/rootfs.img
EOF

info "parameter CMDLINE:"
info "  $(grep '^CMDLINE' "$IMG_DIR/parameter.txt" | cut -d' ' -f2-)"

# ------------------------------------------------------------------ pack ---
log "afptool -pack (RKAF)"
( cd "$WORK_DIR/rockdev" && "$AFPT" -pack ./ Image/update.img )
[ -f "$WORK_DIR/rockdev/Image/update.img" ] || die "afptool did not produce Image/update.img"

log "rkImageMaker (RKFW, loader baked into the header)"
rm -f "$UPDATE_OUT"
( cd "$WORK_DIR/rockdev" && "$RKIMM" "-${ROCKCHIP_CHIP}" Image/MiniLoaderAll.bin \
    Image/update.img "$UPDATE_OUT" -os_type:androidos )
[ -f "$UPDATE_OUT" ] || die "rkImageMaker did not produce $UPDATE_OUT"

# -------------------------------------------------------------- verify -----
log "verifying"
MAGIC="$(dd if="$UPDATE_OUT" bs=1 count=4 status=none)"
[ "$MAGIC" = "RKFW" ] || die "output does not start with the RKFW magic (got '$MAGIC')"
# The RKFW container holds loader + RKAF, whose RKAF carries all the payload, so
# the file must be at least as big as the sum of its parts.
SUM_BYTES=$(( $(stat -c%s "$LOADER") + $(stat -c%s "$UBOOT") + P1_BYTES + P2_BYTES ))
OUT_BYTES="$(stat -c%s "$UPDATE_OUT")"
[ "$OUT_BYTES" -ge "$SUM_BYTES" ] || die "output is smaller than its payload ($OUT_BYTES < $SUM_BYTES)"
info "RKFW magic ok; payload covered ($OUT_BYTES B >= $SUM_BYTES B)"
info "flash addresses used (see the afptool output above):"
info "  uboot  0x00004000  uboot.img   (FIT)"
info "  boot   0x00008000  boot.img    (FAT32, $(( P1_BYTES / 1024 / 1024 )) MiB)"
info "  rootfs ${ROOTFS_OFF}  rootfs.img  (ext4, grow)"

echo
log "done"
info "source   : $IMG"
if [ -n "$BOARD" ]; then info "board    : $BOARD (UBOOT_SYSTEM)"; fi
info "chip     : $ROCKCHIP_CHIP (RKFW header / MACHINE_MODEL)"
info "firmware : $UPDATE_OUT"
info "size     : $(stat -c%s "$UPDATE_OUT") B ($(( $(stat -c%s "$UPDATE_OUT") / 1024 / 1024 )) MiB)"
info "sha256   : $(sha256sum "$UPDATE_OUT" | cut -d' ' -f1)"
echo
info "flash it with:"
info "  RKDevTool -> [Upgrade Firmware] (升级固件) -> open the .img above -> Run"
if [ -n "$SDK_DIR" ] && [ -x "$SDK_DIR/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool" ]; then
  info "  or: sudo $SDK_DIR/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool uf $UPDATE_OUT"
else
  info "  or (Linux, maskrom): sudo upgrade_tool uf $UPDATE_OUT   # Rockchip's flasher, if installed"
fi
echo

if [ "$KEEP" = "yes" ]; then
  info "scratch dir kept at: $WORK_DIR"
else
  rm -rf "$WORK_DIR/rockdev" "$FULL" "$MBR" "$WORK_DIR/mbr.py"
  rmdir "$WORK_DIR" 2>/dev/null || true
fi
