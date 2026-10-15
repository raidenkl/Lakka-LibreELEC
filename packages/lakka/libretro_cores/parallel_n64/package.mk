PKG_NAME="parallel_n64"
PKG_VERSION="37605bb45964c7a2695e6301e80f5c6a4feb5558"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/parallel-n64"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Optimized/rewritten Nintendo 64 emulator made specifically for Libretro. Originally based on Mupen64 Plus."
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="HAVE_PARALLEL=1"

if [ "${ARCH}" = "i386" ]; then
  PKG_MAKE_OPTS_TARGET+=" WITH_DYNAREC=x86"
else
  PKG_MAKE_OPTS_TARGET+=" WITH_DYNAREC=${ARCH}"
fi

if [ "${OPENGL_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL}"
  PKG_MAKE_OPTS_TARGET+=" HAVE_OPENGL=1"
elif [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  # 本核心的 Makefile.common 把 GLES 宏定义**嵌套**在 ifeq ($(HAVE_OPENGL),1) 之内，
  # 所以「只有 GLES、没有桌面 GL」的平台也必须把 HAVE_OPENGL 置 1，否则一个 GL 宏
  # 都不会定义，代码会落到 rglgen_private_headers.h 的 #else 分支去
  # #include <GL/gl.h>（桌面 GL 头，libmali/mesa-GLES-only 环境里不存在）而失败。
  PKG_MAKE_OPTS_TARGET+=" HAVE_OPENGL=1"
else
  PKG_MAKE_OPTS_TARGET+=" HAVE_OPENGL=0"
fi

if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  # GLES=1 既让 Makefile.common 定义 -DHAVE_OPENGLES2 并编入 glsym_es2.c，
  # 也会让它自动关掉只支持桌面 GL 的 GLIDEN64。
  PKG_MAKE_OPTS_TARGET+=" FORCE_GLES=1 GLES=1"
fi

# workaround for RPiZero2-GPiCase compile error
# TODO: package.mk and the core's Makefile need a proper review to
# correctly enable GLES support.
if [ "${DEVICE}" = "RPiZero2-GPiCase" ]; then
  PKG_MAKE_OPTS_TARGET="${PKG_MAKE_OPTS_TARGET/HAVE_OPENGL=0/HAVE_OPENGL=1}"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
fi

if [ "${PROJECT}" = "Generic" ]; then
  PKG_MAKE_OPTS_TARGET+=" HAVE_PARALLEL_RSP=1 HAVE_THR_AL=1"
fi

pre_make_target() {
  if [ "${ARCH}" = "arm" -o "${ARCH}" = "aarch64" ]; then
    CFLAGS+=" -DARM_FIX -fcommon"
  fi

  if target_has_feature neon ; then
    CFLAGS+=" -DGL_BGRA_EXT=0x80E1" # Fix build for platforms where GL_BGRA_EXT is not defined
    [ "${ARCH}" = "arm" ] && PKG_MAKE_OPTS_TARGET+=" platform=armv-neon" || true
  fi
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -v parallel_n64_libretro.so ${INSTALL}/usr/lib/libretro/
}
