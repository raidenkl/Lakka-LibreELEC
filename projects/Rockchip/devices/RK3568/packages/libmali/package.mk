# SPDX-License-Identifier: GPL-2.0
# RK3576 device override of the shared libmali package.
#
# The LubanCat vendor kernel (6.1) ships the ARM Mali kbase driver and has no
# panthor/panfrost, so the Mali-G52 (Bifrost) userspace has to come from the
# Rockchip closed source blob.  The LubanCat SDK pairs this kernel with the
# g13p0 Bifrost blobs for its G52 boards (ubuntu22.04/packages/arm64/libmali/),
# so the same revision is pinned here: the plain "gbm" variant from the
# tsukumijima v1.9-1-20260312-bd33ee2 release.  Do NOT switch to the newest
# release for g13p0 - it only carries "dummy" builds there.
#
# Lakka runs KMS/GBM only (no X11, no Wayland) -> the plain "gbm" variant.
# It is the 2020-era packaging:
#   * NO usr/include  - the Khronos EGL/GLES headers are vendored next to this
#     file (include/) and installed from there.
#   * NO firmware     - Bifrost firmware is built into the kbase driver; only
#     Valhall/CSF GPUs (G610/G710) load an external mali_csffw.bin.
#   * the mali/ shim set has no libMaliVulkan - this blob predates Vulkan.

PKG_NAME="libmali"
PKG_VERSION="1.9-1"
PKG_SHA256="6d84ff83bdb6e152bf3c6eb4865188efe16af3062e41dbc923859cce918b6879"
PKG_SOURCE_NAME="libmali-bifrost-g52-g13p0-gbm_1.9-1_arm64.deb"
PKG_URL="https://github.com/tsukumijima/libmali-rockchip/releases/download/v1.9-1-20260312-bd33ee2/${PKG_SOURCE_NAME}"
PKG_SITE="https://github.com/tsukumijima/libmali-rockchip"
PKG_LICENSE="nonfree"
PKG_ARCH="aarch64"
PKG_LONGDESC="Rockchip Mali-G52 (Bifrost) userspace blob for RK3576/RK356x, KMS/GBM"
PKG_TOOLCHAIN="manual"
PKG_DEPENDS_TARGET="toolchain libdrm"
PKG_STAMP="${MALI_FAMILY}"

# versioned wrapper libraries shipped in the package (mali/ shim dir)
MALI_VERSIONED="libEGL.so.1 libGLESv1_CM.so.1 libGLESv2.so.2 libgbm.so.1 libMaliOpenCL.so.1"
MALI_PLAIN="libEGL.so libGLESv1_CM.so libGLESv2.so libgbm.so libMaliOpenCL.so"

# LibreELEC cannot unpack .deb natively (scripts/extract has no deb branch),
# so unpack the ar archive here.  Resulting layout:
#   usr/lib/aarch64-linux-gnu/{libmali.so.1.9.0, libmali-hook.so.1.9.0,
#                              mali/<shims>, pkgconfig/mali.pc}
unpack() {
  command -v dpkg-deb >/dev/null || die "dpkg-deb is required to unpack the libmali .deb"
  dpkg-deb -x "${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME}" "${PKG_BUILD}"
}

install_mali() {
  local dest="$1"

  mkdir -p "${dest}/usr/lib"
    cp -av  ${PKG_BUILD}/usr/lib/aarch64-linux-gnu/libmali.so.1.9.0       "${dest}/usr/lib/"
    cp -av  ${PKG_BUILD}/usr/lib/aarch64-linux-gnu/libmali-hook.so.1.9.0  "${dest}/usr/lib/"

    ln -sfv /usr/lib/libmali.so.1.9.0      "${dest}/usr/lib/libmali.so.1"
    ln -sfv /usr/lib/libmali.so.1.9.0      "${dest}/usr/lib/libmali.so"
    ln -sfv /usr/lib/libmali-hook.so.1.9.0 "${dest}/usr/lib/libmali-hook.so.1"

    for lib in ${MALI_VERSIONED} ${MALI_PLAIN}; do
      cp -av ${PKG_BUILD}/usr/lib/aarch64-linux-gnu/mali/${lib} "${dest}/usr/lib/${lib}"
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
    for lib in libEGL libGLESv1_CM libGLESv2 libgbm libMaliOpenCL; do
      ln -sfv libmali.so.1.9.0 "${SYSROOT_PREFIX}/usr/lib/${lib}.so"
    done
  mkdir -p ${SYSROOT_PREFIX}/usr/include
    cp -a ${PKG_DIR}/include/. ${SYSROOT_PREFIX}/usr/include/
    # Mesa normally installs <gbm.h>; this device replaces Mesa with the libmali blob,
    # so RetroArch (gfx/drivers_context/drm_ctx.c) fails with "gbm.h: No such file or
    # directory".  The header is taken verbatim from libgbm-dev 26.0.3 (MIT, same
    # version as mesa in this tree) and lives next to this package so it is reviewable
    # and versioned with the port.
    cp -av ${PKG_DIR}/gbm.h ${SYSROOT_PREFIX}/usr/include/gbm.h
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/pkgconfig
    cp -av ${PKG_BUILD}/usr/lib/aarch64-linux-gnu/pkgconfig/mali.pc ${SYSROOT_PREFIX}/usr/lib/pkgconfig/ 2>/dev/null || true

    # Mesa normally ships egl.pc / gbm.pc / glesv2.pc, but this device replaces Mesa with
    # the libmali blob, so nothing provides them (see the RK3588 package for the details).
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

  # No GPU firmware: Bifrost firmware is compiled into the kbase driver.
}
