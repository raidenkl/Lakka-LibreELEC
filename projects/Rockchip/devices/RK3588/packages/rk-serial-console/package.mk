# SPDX-License-Identifier: GPL-2.0
# Serial console on /dev/ttyFIQ0 (Rockchip FIQ debugger, UART2)
#
# Why this package exists
# -----------------------
# * The LubanCat vendor BSP kernel hands UART2 to the Rockchip fiq_debugger
#   driver, so the port shows up as /dev/ttyFIQ0 - there is no usable ttyS2 on
#   this kernel.  It is the only debugging channel before the network is up.
# * LibreELEC deliberately ships no getty at all: packages/sysutils/systemd/
#   package.mk removes getty@.service, serial-getty@.service,
#   console-getty.service and getty.target.  Nothing ever offers a shell.
# * There is also no agetty binary to call: packages/sysutils/util-linux is
#   built with --disable-all-programs and a whitelist that does not contain
#   --enable-agetty (verified: /usr/sbin/agetty is absent from the SYSTEM
#   squashfs).  Do not "fix" this by pointing a unit at /sbin/agetty - the
#   build host's $BUILD/image/system/bin and /sbin are absolute symlinks
#   (bin -> /usr/bin, sbin -> /usr/sbin), so on the host such a path silently
#   resolves to the HOST's x86_64 binary and the unit will fail on the board
#   with "Unable to locate executable '/sbin/agetty'".
#
# What it does
# ------------
# Runs a root login shell directly on the port, using the same mechanism as
# systemd's own early-boot debug-shell.service (ExecStart=-/bin/sh,
# StandardInput=tty-force, TTYPath=...).  /bin/sh is a symlink to busybox ash
# and -l makes it a login shell, so /etc/profile (PATH, LibreELEC banner) is
# read.  Physical UART access equals root - that is a deliberate trade-off for
# a debug console on a development port.
#
# To disable: drop "rk-serial-console" from ADDITIONAL_PACKAGES in
# projects/Rockchip/devices/RK3588/options, or mask the unit at runtime with
# "systemctl mask ttyFIQ0-console.service".

PKG_NAME="rk-serial-console"
PKG_VERSION="1.1"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://libreelec.tv"
PKG_LONGDESC="Root login shell on /dev/ttyFIQ0 (Rockchip FIQ debugger UART2)"
PKG_TOOLCHAIN="manual"

post_install() {
  enable_service ttyFIQ0-console.service
}
