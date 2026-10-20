# SPDX-License-Identifier: GPL-2.0
# Rockchip board audio output initialisation
#
# Why this package exists
# -----------------------
# * RK809/RK817 (LubanCat 1/2 families): the codec's "Playback Path" control
#   defaults to OFF, which leaves the whole analogue output stage powered down.
# * ES8388 (LubanCat 3/5 families): the analogue output stages OUT1/OUT2
#   default to off as well.
# * LibreELEC's udev soundconfig only handles generic controls (Master, PCM,
#   Speaker, Headphone, ...), so neither vendor-private switch is touched and
#   every board boots up silent.
#
# What it does
# ------------
# Runs /usr/bin/rk-audio-default after the sound card is registered and sets
# the switch that belongs to the detected codec.  RK809 additionally needs the
# kernel side (rockchip-9006): DAPM restores the output stage defaults on every
# PCM start, so the path has to be re-applied there as well.

PKG_NAME="rk-audio-default"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://libreelec.tv"
PKG_LONGDESC="Enable the board audio output stage at boot (RK809 Playback Path / ES8388 OUT1-OUT2)"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rk-audio-default ${INSTALL}/usr/bin/rk-audio-default
  chmod 0755 ${INSTALL}/usr/bin/rk-audio-default
}

post_install() {
  enable_service rk-audio-default.service
}
