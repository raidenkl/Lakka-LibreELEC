# SPDX-License-Identifier: GPL-2.0
# RK3588 device override of the shared rkbin package.
#
# The LubanCat fork carries the RK3588 DDR/SPL/BL31/BL32 binaries and the ini files
# that the vendor U-Boot make.sh/fit.sh consume (RKBOOT/RK3588MINIALL.ini,
# RKTRUST/RK3588TRUST.ini).  The commit below is the one validated by the LubanCat SDK.

PKG_NAME="rkbin"
PKG_VERSION="58a39b47f77a26a1e110fa1a1ce80bcfcb0b3505"
PKG_SHA256="78c2047370161a1eff6884a88323b533bfbdeb55347440e77f9ca8aaa5a67c5a"
PKG_SOURCE_NAME="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_URL="https://github.com/LubanCat/rkbin/archive/${PKG_VERSION}.tar.gz"
PKG_SITE="https://github.com/LubanCat/rkbin"
PKG_LICENSE="nonfree"
PKG_ARCH="arm aarch64"
PKG_LONGDESC="Rockchip Firmware and Tool Binaries (LubanCat fork)"
PKG_TOOLCHAIN="manual"
