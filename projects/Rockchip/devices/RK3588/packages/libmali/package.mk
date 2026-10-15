# SPDX-License-Identifier: GPL-2.0
# RK3588 device override of the shared libmali package.
#
# The LubanCat vendor kernel (6.1) ships the ARM Mali kbase driver and has no
# panthor/panfrost, so the Mali-G610 (Valhall) userspace has to come from the
# Rockchip closed source blob.  The source is a locally assembled tarball
# (see tools/ or the port notes): libmali blob + wrappers + mali_csffw.bin from
# libmali-valhall-g610-g24p0-gbm, plus EGL/GLES/KHR headers for the sysroot.
#
# Lakka runs KMS/GBM only (no X11, no Wayland) -> the plain "gbm" variant is used;
# its blob only depends on libdrm/libc/libstdc++.

PKG_NAME="libmali"
PKG_VERSION="1.9-1"
PKG_SHA256="9b68e764ce31dd88742157088597f7e6a38edb92299a29db24b7e9192c16776f"
PKG_SOURCE_NAME="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_URL="https://github.com/tsukumijima/libmali-rockchip/releases/download/v1.9-1-20260923-ec78b74/libmali-valhall-g610-g24p0-gbm_1.9-1_arm64.deb"
PKG_SITE="https://github.com/tsukumijima/libmali-rockchip"
PKG_LICENSE="nonfree"
PKG_ARCH="aarch64"
PKG_LONGDESC="Rockchip Mali-G610 (Valhall) userspace blob for RK3588, KMS/GBM"
PKG_TOOLCHAIN="manual"
PKG_DEPENDS_TARGET="toolchain libdrm"
PKG_STAMP="${MALI_FAMILY}"

# versioned wrapper libraries shipped in the package (flat layout in /usr/lib)
MALI_VERSIONED="libEGL.so.1 libGLESv1_CM.so.1 libGLESv2.so.2 libgbm.so.1 libMaliOpenCL.so.1 libMaliVulkan.so.1"
MALI_PLAIN="libEGL.so libGLESv1_CM.so libGLESv2.so libgbm.so libMaliOpenCL.so libMaliVulkan.so"

install_mali() {
  local dest="$1"

  mkdir -p "${dest}/usr/lib"
    cp -av  ${PKG_BUILD}/lib/aarch64-linux-gnu/libmali.so.1.9.0       "${dest}/usr/lib/"
    cp -av  ${PKG_BUILD}/lib/aarch64-linux-gnu/libmali-hook.so.1.9.0  "${dest}/usr/lib/"

    ln -sfv /usr/lib/libmali.so.1.9.0      "${dest}/usr/lib/libmali.so.1"
    ln -sfv /usr/lib/libmali.so.1.9.0      "${dest}/usr/lib/libmali.so"
    ln -sfv /usr/lib/libmali-hook.so.1.9.0 "${dest}/usr/lib/libmali-hook.so.1"

    for lib in ${MALI_VERSIONED} ${MALI_PLAIN}; do
      cp -av ${PKG_BUILD}/lib/aarch64-linux-gnu/mali/${lib} "${dest}/usr/lib/${lib}"
    done
}

make_target() {
  : # prebuilt blob, nothing to compile
}

makeinstall_target() {
  # build time: libraries and Khronos headers for RetroArch, SDL and the cores
  install_mali "${SYSROOT_PREFIX}"

    # The mali/*.so.1 files shipped in the blob are hook shims with an EMPTY dynamic
    # symbol table (DT_NEEDED libmali-hook.so.1 + libmali.so.1, no exports), so linking
    # plain -lEGL / -lGLESv2 / -lgbm fails with undefined references to the real API.
    # The implementation lives in libmali.so.1.9.0 (SONAME libmali.so.1), which exports
    # the full EGL/GLES/GBM entry points.  Point the plain linker names (build time only)
    # at it; consumers then record libmali.so.1 as DT_NEEDED, which exists on the device.
    # The runtime layout (the .so.1 shims as shipped by Rockchip) is left untouched.
    for lib in libEGL libGLESv1_CM libGLESv2 libgbm libMaliOpenCL libMaliVulkan; do
      ln -sfv libmali.so.1.9.0 "${SYSROOT_PREFIX}/usr/lib/${lib}.so"
    done
  mkdir -p ${SYSROOT_PREFIX}/usr/include
    cp -a ${PKG_BUILD}/include/. ${SYSROOT_PREFIX}/usr/include/
    # Mesa normally installs <gbm.h>; this device replaces Mesa with the libmali blob,
    # so RetroArch (gfx/drivers_context/drm_ctx.c) fails with "gbm.h: No such file or
    # directory".  The header is taken verbatim from libgbm-dev 26.0.3 (MIT, same
    # version as mesa in this tree) and lives next to this package so it is reviewable
    # and versioned with the port.
    cp -av ${PKG_DIR}/gbm.h ${SYSROOT_PREFIX}/usr/include/gbm.h
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/pkgconfig
    cp -av ${PKG_BUILD}/lib/aarch64-linux-gnu/pkgconfig/mali.pc ${SYSROOT_PREFIX}/usr/lib/pkgconfig/ 2>/dev/null || true

    # Mesa normally ships egl.pc / gbm.pc / glesv2.pc, but this device replaces Mesa with
    # the libmali blob, so nothing provides them.  Consumers probe them via pkg-config:
    # RetroArch requires "gbm >= 9.0" when KMS output is enabled and would otherwise fail
    # with "GBM is disabled and forced to build with KMS support".
    # libdir matches where install_mali() puts the libraries (/usr/lib); the version
    # mirrors mesa's PKG_VERSION in this tree so minimum-version checks behave the same
    # as with a Mesa-provided stack.
    pc_dir="${SYSROOT_PREFIX}/usr/lib/pkgconfig"
    pc_ver="26.0.3"

    cat > "${pc_dir}/gbm.pc" <<PCEOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: gbm
Description: Mali GBM (Rockchip libmali blob, Mali DDK backed)
Version: ${pc_ver}
Requires.private: libdrm
Libs: -L\${libdir} -lgbm
Cflags: -I\${includedir}
PCEOF

    cat > "${pc_dir}/egl.pc" <<PCEOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: egl
Description: Mali EGL (Rockchip libmali blob, Mali DDK backed)
Version: ${pc_ver}
Requires.private: libdrm
Libs: -L\${libdir} -lEGL
Cflags: -I\${includedir}
PCEOF

    cat > "${pc_dir}/glesv2.pc" <<PCEOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: glesv2
Description: Mali OpenGL ES 2/3 (Rockchip libmali blob, Mali DDK backed)
Version: ${pc_ver}
Libs: -L\${libdir} -lGLESv2
Cflags: -I\${includedir}
PCEOF

  # run time
  install_mali "${INSTALL}"

  # GPU firmware, loaded by the vendor kbase driver from /lib/firmware
  # (scripts/image links /lib -> /usr/lib inside the image)
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/g610
    cp -av ${PKG_BUILD}/firmware/mali_csffw.bin ${INSTALL}/$(get_full_firmware_dir)/mali_csffw.bin
    cp -av ${PKG_BUILD}/firmware/mali_csffw.bin ${INSTALL}/$(get_full_firmware_dir)/g610/mali_csffw.bin
}
