afptool / rkImageMaker - Rockchip firmware packing tools (Linux, x86-64, static)

Taken from the Firefly/LubanCat vendor SDK:
  <SDK>/tools/linux/Linux_Pack_Firmware/rockdev/{afptool,rkImageMaker}

These are Rockchip's closed-source build/pack utilities, which Rockchip and
every vendor SDK redistribute freely; they are statically linked and run on
any x86_64 Linux without further dependencies.  They are only used by
mk-rockchip-update.sh to pack a standard RKFW update.img from the normal
Lakka image; nothing here is required for building the image itself.

Vendored copy: rk3588 build, binaries dated 2025-08-22 (SDK snapshot).
