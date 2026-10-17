# SPDX-License-Identifier: GPL-2.0
# RK3588 device override of the shared u-boot package.
#
# Uses the LubanCat vendor U-Boot (U-Boot 2017.09 Rockchip fork) together with its
# own make.sh, which builds U-Boot and packs the Rockchip FIT boot chain
# (SPL loader + uboot.img containing U-Boot and BL31/BL32 from rkbin).
# The commit below is the one validated by the LubanCat SDK build.

PKG_NAME="u-boot"
PKG_VERSION="8f53f800da2c25d0c6ba414fb45902a01675703a"
PKG_SHA256="9b1189299ec2ec2ffc22309faf03d162623a181f614fbf3c368c1bca09c8a7ba"
PKG_SOURCE_NAME="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_URL="https://github.com/LubanCat/u-boot/archive/${PKG_VERSION}.tar.gz"
PKG_SITE="https://github.com/LubanCat/u-boot"
PKG_LICENSE="GPL"
PKG_ARCH="aarch64"
PKG_LONGDESC="Rockchip vendor U-Boot (LubanCat fork) with FIT boot chain packing"
PKG_TOOLCHAIN="manual"

PKG_DEPENDS_TARGET="toolchain openssl:host Python3:host ${UBOOT_FIRMWARE}"
PKG_DEPENDS_UNPACK="${UBOOT_FIRMWARE}"
PKG_STAMP="${UBOOT_SYSTEM} ${UBOOT_TARGET}"

PKG_NEED_UNPACK="${PROJECT_DIR}/${PROJECT}/bootloader ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/bootloader"

make_target() {
  [ -n "${UBOOT_SYSTEM}" ] || die "UBOOT_SYSTEM must be set to build an image"

  local rkbin="$(get_build_dir rkbin)"
  # uboot_helper returns the full defconfig file name (<board>_defconfig), which is
  # what the mainline u-boot package expects.  The vendor make.sh appends the suffix
  # itself (it runs "make configs/${ARG_BOARD}_defconfig"), so pass the bare board name.
  local uboot_cfg="$(${ROOT}/${SCRIPTS}/uboot_helper ${PROJECT} ${DEVICE} ${UBOOT_SYSTEM} config)"
  uboot_cfg="${uboot_cfg%_defconfig}"

  # U-Boot 2017.09 hardcodes -Werror (Makefile: KBUILD_CFLAGS += -fshort-wchar -Werror).
  # GCC 13 is newer than what the vendor validated, so its warnings on old code
  # (-Waddress, -Wmaybe-uninitialized) become build failures.  KCFLAGS is appended last
  # (Makefile: KBUILD_CFLAGS += $(KCFLAGS)), so -Wno-error downgrades them back to
  # warnings while the explicit -Werror=... checks stay in effect.
  export KCFLAGS="-Wno-error"

  # the vendor make.sh/fit.sh expect the rkbin tree next to the u-boot tree
  [ -e "$(dirname ${PKG_BUILD})/rkbin" ] || ln -sfn "${rkbin}" "$(dirname ${PKG_BUILD})/rkbin"

  # Merge the device config fragment into the vendor defconfig.  The mainline
  # u-boot package does this automatically, but this vendor make.sh path does
  # not - without it every setting in <device>/bootloader/config is ignored.
  #
  # Several boards of one chip can share the same vendor defconfig (lubancat-5
  # and lubancat-5-v2 both use lubancat-5-rk3588-pcie_defconfig) and LibreELEC
  # reuses one source tree for every board, so keep a pristine copy and always
  # rebuild the defconfig from it: appending blindly would duplicate every
  # fragment line on the second build of a shared defconfig.
  local dev_fragment="${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/bootloader/config"
  if [ -f "${dev_fragment}" ]; then
    if [ -f "configs/${uboot_cfg}_defconfig.lakka-pristine" ]; then
      cp "configs/${uboot_cfg}_defconfig.lakka-pristine" "configs/${uboot_cfg}_defconfig"
    else
      cp "configs/${uboot_cfg}_defconfig" "configs/${uboot_cfg}_defconfig.lakka-pristine"
    fi
    echo "u-boot: merging device config fragment ${dev_fragment}"
    cat "${dev_fragment}" >> "configs/${uboot_cfg}_defconfig"
  fi

  # DDR blob selection: rkbin ships one blob per frequency and 1848MHz is the
  # default for the whole RK3588 family (LubanCat 5 trains 2112MHz as well, but
  # 1848MHz is the value the vendor SDK ships and is used everywhere).
  # Override for experiments:  DDR_FREQ=2112 projects/Rockchip/tools/build-board.sh RK3588 lubancat-5
  local ddr_freq="${DDR_FREQ:-}"
  [ -n "${ddr_freq}" ] || ddr_freq="1848"
  local uboot_ini="${rkbin}/RKBOOT/${DEVICE}MINIALL.ini"
  if [ -f "${uboot_ini}" ]; then
    sed -i "s#rk3588_ddr_lp4_[0-9]*MHz_lp5_2400MHz_v1.18.bin#rk3588_ddr_lp4_${ddr_freq}MHz_lp5_2400MHz_v1.18.bin#g" "${uboot_ini}"
    echo "u-boot: ${UBOOT_SYSTEM} DDR blob -> $(grep -m1 '^Path1=' "${uboot_ini}")"
  fi

  echo "u-boot: ./make.sh ${uboot_cfg} ${DEVICE}MINIALL.ini ${DEVICE}TRUST.ini"
  ./make.sh CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" \
           "${uboot_cfg}" \
           "${rkbin}/RKBOOT/${DEVICE}MINIALL.ini" \
           "${rkbin}/RKTRUST/${DEVICE}TRUST.ini"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/bootloader
    find_file_path bootloader/install && . ${FOUND_PATH}
    find_file_path bootloader/update.sh && cp -av ${FOUND_PATH} ${INSTALL}/usr/share/bootloader
    if find_file_path bootloader/canupdate.sh; then
      cp -av ${FOUND_PATH} ${INSTALL}/usr/share/bootloader
      sed -e "s/@PROJECT@/${DEVICE:-${PROJECT}}/g" \
          -i ${INSTALL}/usr/share/bootloader/canupdate.sh
    fi
}
