#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# gen-cores-data.py — 生成/更新 configure-cores.sh 用的元数据表 cores-data.tsv
#
#   ./gen-cores-data.py            # 就地更新 cores-data.tsv
#
# 数据来源（都从仓库里现读，不需要联网）：
#   * 核心名单  : packages/lakka/libretro_cores/package.mk 的 LIBRETRO_CORES 赋值
#   * 分类+备注 : 同目录的 CORES.md（表格行 `| \`core\` | 说明 | 备注 |`）
#   * 推荐取舍  : 本文件里的 SCHEME_A / SCHEME_B / RUST_CORES 三个常量
#
# 什么时候需要重跑：上游 `LIBRETRO_CORES` 增删了核心、或 CORES.md 更新了分类之后。
# 平时直接编辑 cores-data.tsv 也可以（纯文本 TSV）。
#
# recommend 取值：
#   keep         建议保留（主流现代机种）
#   remove       「只留主流现代机种」建议去掉（= CORES.md 方案 A，另含 3 个 Rust 核心）
#   remove-heavy remove + 编译最慢的大件（= CORES.md 方案 B）
#   managed      由构建系统自动排除，GUI 灰显不管理
#
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = HERE
while REPO != "/" and not (os.path.isfile(os.path.join(REPO, "scripts/build"))
                           and os.path.isfile(os.path.join(REPO, "Makefile"))):
    REPO = os.path.dirname(REPO)
if REPO == "/":
    sys.exit("错误：找不到仓库根目录")

# CORES.md 在设备目录下（本脚本位于其 tools/ 子目录）
CORES_MD = os.path.join(os.path.dirname(HERE), "CORES.md")
PKG_MK = os.path.join(REPO, "packages/lakka/libretro_cores/package.mk")
OUT = os.path.join(HERE, "cores-data.tsv")

# ---- 推荐方案（与 CORES.md「快速裁剪建议」保持一致）----
SCHEME_A = """stella stella2014 a5200 prosystem virtualjaguar handy beetle_lynx gearlynx atari800
freeintv freechaf o2em vecx amiarcadia pd777 gearcoleco jollycv
fuse_libretro 81 cap32 crocods bluemsx fmsx b2 applewin m2000 theodore ep128emu
xmil quasi88 np2kai meowpc98 px68k gam4980
potator gw_libretro tamalibretro sameduck mu ardens
beetle_vb pokemini
tic80 wasm4 vircon32 lowres_nx uzem retro8 fake_08 jaxe pocketcdg gme numero
2048 dinothawr mrboom jumpnbump superbroswar thepowdertoy craft anarch lutro chailove
pzretro mojozork xrick dirksimple dice cannonball clownmdemu emux_sms""".split()

SCHEME_B = "mame mame2010 mame2015 dolphin lrps2 play ppsspp citra azahar panda3ds boom3".split()

# 会拉入 llvm:host（LLVM 源码 130 MB，国内下载基本必失败），默认也建议排除
RUST_CORES = "rustation_ng boytacean doukutsu_rs".split()

MANAGED = {
    "kronos": "OPENGLES_SUPPORT=yes 时由构建系统自动追加排除，GUI 不管理",
    "lr_moonlight": "Rockchip 项目由构建系统自动追加排除，GUI 不管理",
}


def live_cores(path):
    """解析 LIBRETRO_CORES —— 负向后视排除 EXCLUDE_LIBRETRO_CORES 的赋值。"""
    s = open(path, encoding="utf-8").read()
    chunks = re.findall(r'(?<![A-Za-z0-9_])LIBRETRO_CORES\+?="([^"]*)"', s)
    words = []
    for c in chunks:
        words += c.replace("\\", " ").split()
    bad = re.compile(r'[\$\{\}/]')
    return sorted({w for w in words if not bad.search(w) and w not in ("core1", "core2")})


def main():
    live = live_cores(PKG_MK)

    cat, rows = None, {}
    row_re = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|")
    for line in open(CORES_MD, encoding="utf-8"):
        m = re.match(r"^##\s+(\d+)\.\s+(.*)$", line)
        if m:
            cat = f"{m.group(1)}. {m.group(2).strip()}"
            continue
        if line.startswith("## "):
            cat = None
            continue
        if cat:
            r = row_re.match(line)
            if r:
                rows[r.group(1).strip()] = (cat, r.group(2).strip(), r.group(3).strip())

    unclassified = []
    for c in live:
        if c not in rows:
            unclassified.append(c)
            rows[c] = ("9. 幻想主机 / 可编程平台 / 玩具", "", "（未在 CORES.md 分类，请补充）")

    recs = Counter()
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("# core\tcategory\trecommend\tnote\n")
        for c in live:
            cat_, desc, note = rows[c]
            if c in MANAGED:
                rec, note = "managed", MANAGED[c]
            elif c in SCHEME_B:
                rec = "remove-heavy"
            elif c in SCHEME_A:
                rec = "remove"
            elif c in RUST_CORES:
                rec = "remove"
                note = "Rust 核心：会拉入 llvm:host（LLVM 源码 130 MB，国内下载基本必失败），默认建议排除"
            else:
                rec = "keep"
            recs[rec] += 1
            f.write(f"{c}\t{cat_}\t{rec}\t{(note or desc).replace(chr(9), ' ')}\n")

    print(f"已写出 {OUT}")
    print(f"  核心总数 {len(live)}")
    print(f"  推荐分布 {dict(recs)}")
    if unclassified:
        print(f"  未在 CORES.md 分类: {unclassified}")


if __name__ == "__main__":
    main()
