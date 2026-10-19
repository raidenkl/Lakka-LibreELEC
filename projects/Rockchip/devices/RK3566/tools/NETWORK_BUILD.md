# 在中国大陆网络下构建 Lakka RK3588 镜像

这份文档说明：**为什么**在 GitHub 直连不通的宿主机上构建会失败、**怎么判断**是网络问题、
以及**怎么用 `tools/` 里的脚本一次性修好**。

> 一句话结论：跑一次 `tools/fix-build-env.sh`，再 `tools/resume-build.sh` 就能构建。
> 若有极个别包仍然拉不下来，用 `tools/audit-missing-sources.sh` + `tools/seed-missing-sources.sh` 补齐。

---

## 1. 先判断「是不是网络问题」

在宿主机上跑这组命令：

```sh
for u in https://github.com https://codeload.github.com https://www.baidu.com https://archive.ubuntu.com; do
  printf '%-34s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' -m 12 -L "$u")"
done
```

| 结果 | 含义 |
| --- | --- |
| `github.com` / `codeload.github.com` 返回 **`000`**，而 baidu / archive.ubuntu.com 返回 `200` | **到 GitHub 的链路被阻断**（最典型）。这类问题重试再多次也没用，必须走镜像 |
| 全部能通，但构建里偶发 `early EOF` / `GnuTLS recv error (-9)` | 链路**抖动**，重试可解（`scripts/get_git` 已内置重试） |
| 全部不通 | 宿主机没网，先解决网络 |

对应到构建日志里的典型报错：

```
fatal: unable to access 'https://github.com/...': gnutls_handshake() failed: The TLS connection was non-properly terminated
fatal: unable to access 'https://github.com/...': Failed to connect to github.com port 443: Connection timed out
get_git: <pkg> failed after 8 attempts
FAILURE: scripts/install <pkg>:target has failed!
```

---

## 2. 三层修复（`tools/fix-build-env.sh` 全做了）

### 第 1 层 · 宿主依赖：**不装会报假错误**

`scripts/checkdeps` 和若干包的构建需要一些宿主工具。它们缺失时的报错**非常迷惑**，所以先修这个：

| 缺失项 | 表面现象 | 真实原因 |
| --- | --- | --- |
| `zstd` / `zstdcat` | `tar: This does not look like a tar archive` | `scripts/extract` 用 `zstdcat` 解 `.tar.zst`，命令不存在 → tar 收到空流 |
| `perl Parse::Yapp`（模块 **+ `yapp` 程序**） | `samba:target during configure_target` 失败，日志里 `perl module Parse::Yapp::Driver 1.05 : ok` 竟然是通过的 | samba 自带的 `pidl` 还会 `find_program('yapp')`，只有模块没有程序照样挂 |
| `perl JSON` | `checkdeps` 直接拦下 `make image` | 需要一个真实的 `JSON.pm` |
| `rdfind` | `checkdeps` 拦下 | 构建流程**从不调用**它，放个 no-op 占位即可 |

> ⚠️ **绝对不要用自制假模块/假脚本去凑 `checkdeps`**。
> 我们踩过：假 `Parse::Yapp::Driver` 骗过了模块探测，却在 samba 的 `find_program('yapp')` 处
> 以更难查的形式炸掉。正确优先级：**官方包解包 > 源码编译 > 借用现成二进制 > 绝不造假**。
> `fix-build-env.sh` 用的是「从 Ubuntu pool 解包 `.deb`」（不需要 sudo）。

### 第 2 层 · git 全局 `insteadOf`：**一次修好所有 git 类下载**

```sh
git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"
```

这一条的价值远超它的长度 —— 它让**所有**本该发往 `github.com` 的 git 操作透明走镜像：

- `scripts/get_git` 抓取 git 源包（全树有 180+ 个）
- `git submodule update --init --recursive`（**递归子模块也覆盖**，因为 `--global` 配置对所有 git 进程生效）
- **CMake `FetchContent`**：例如 `melondsds` 在 configure 阶段要拉 11 个 GitHub 依赖
  （melonDS、libretro-common、glm、fmt、zlib…），没有这条就会死在 configure

**为什么可以放心用镜像**：git 会按 SHA-1 校验每一个对象，并且
`scripts/get_git` 与 `seed-any-pkg.sh` 都会比对 `rev-parse HEAD == PKG_VERSION`。
所以传输经过第三方最多只是**下载失败**，不可能悄悄换掉代码。

### 第 3 层 · `~/bin/wget` 包装器：**管 git 管不到的下载**

很多包不是 git 源，而是**归档源**（`.../archive/<sha>.tar.gz`、`.../releases/download/...`），
走 `scripts/get_archive` + `wget`。git 的 `insteadOf` 对它们无效。

`tools/wget-gh-mirror` 会被装成 `~/bin/wget`：

- GitHub 系主机（`github.com` / `codeload.github.com` / `raw.githubusercontent.com` / `objects.githubusercontent.com`）
  → 依次经 `gh-proxy.com`、`ghfast.top` 重试
  （**不能靠 https→http 降级**：GitHub 有 HSTS，会把 http 强制转回 https，这条路是死的）
- 其它主机 → 先直连，失败再用同一 URL 的 http 重试
  （修的是 `www.kernel.org` 这类「HTTPS 不通但 HTTP 正常」的站）

完整性同样不依赖镜像：`get_archive` 会拿 `PKG_SHA256` 校验，不符就中止构建。

### 兜底 · 源码预置

如果某个包连镜像也拿不到（镜像会挂、仓库在别处、或 recipe 钉的哈希过期），就手动预置：

```sh
tools/audit-missing-sources.sh          # 列出「计划内、但缓存还没准备好」的包
tools/seed-missing-sources.sh           # 逐个用 seed-any-pkg.sh 预置
tools/seed-missing-sources.sh /tmp/audit-missing.tsv   # 或用已有审计结果
```

`seed-any-pkg.sh` 会自动识别源类型并生成构建系统期望的缓存布局：

| 源类型 | 缓存文件（放 `sources/<pkg>/`） |
| --- | --- |
| git | `<pkg>-<sha>.tar.xz`（顶层目录同名）+ `<pkg>-<sha>.tar.xz.gitstamp`<br>`.gitstamp` 内容 = `<PKG_URL>|<PKG_VERSION>`，**必须是原始非镜像 URL** |
| 归档 | `<PKG_SOURCE_NAME>` + `<PKG_SOURCE_NAME>.url` + `<PKG_SOURCE_NAME>.sha256` |

**两者不能混用** —— 这是很容易搞错的一点。

---

## 3. 用法

```sh
cd <repo>/projects/Rockchip/devices/RK3588/tools

./fix-build-env.sh                 # 检查 + 修复（幂等，可重复跑）
./fix-build-env.sh --check         # 只看缺什么，不改动任何东西
./fix-build-env.sh --deps-only     # 只修宿主依赖
./fix-build-env.sh --net-only      # 只装网络垫片
./fix-build-env.sh --mirror https://ghfast.top    # 换镜像
./fix-build-env.sh --unset-mirror  # 撤销（恢复直连 / 卸掉 wget 包装器）
```

`fix-build-env.sh` 会做：

1. 补齐 `zstd` / `Parse::Yapp`+`yapp` / `JSON` / `rdfind`（全部**不需要 sudo**）
2. 设置 git `insteadOf` + `http.version=HTTP/1.1` + `http.postBuffer`
3. 安装 `~/bin/wget` 包装器
4. 把 `~/bin`、`~/perl5` 写进 `~/.bashrc`
5. 自检：逐个打印 `✓/✗`，最后跑一次 `scripts/checkdeps`

> **`~/.bashrc` 只在交互式 shell 生效**。用脚本/ssh 起构建时必须显式传：
> ```sh
> env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5" \
>     PROJECT=Rockchip DEVICE=RK3588 ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 \
>     THREADCOUNT=4 make image
> ```
> `tools/resume-build.sh` 已经替你设好了这些。

然后构建：

```sh
tools/resume-build.sh              # 前台
tools/resume-build.sh &            # 后台
tail -f /tmp/rk3588-build-image.log
```

---

## 4. 验证修复是否生效

```sh
# ① 宿主依赖全部就绪
env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5" ./scripts/checkdeps; echo "rc=$?"   # 期望 rc=0

# ② git 走镜像（应能返回 refs，而不是 TLS 握手失败）
git ls-remote https://github.com/libretro/glsl-shaders 2>&1 | head -2

# ③ wget 解析到包装器
env PATH="$HOME/bin:$PATH" sh -c 'command -v wget'    # 期望 ~/bin/wget
tail -5 /tmp/wget-gh-mirror.log                       # 看它触发了哪些镜像重写

# ④ 单个包能取到源码（拿任一 git 源包验证，期望 rc=0）
env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5" PROJECT=Rockchip DEVICE=RK3588 \
    ARCH=aarch64 UBOOT_SYSTEM=lubancat-5 ./scripts/get glsl_shaders; echo "rc=$?"
```

---

## 5. 踩过的坑（速查表）

| 日志里的现象 | 原因 | 处理 |
| --- | --- | --- |
| `gnutls_handshake() failed` / `Connection timed out` / `SSL_ERROR_SYSCALL` | GitHub 直连被阻断 | `fix-build-env.sh --net-only`（git `insteadOf` + wget 包装器） |
| CMake `FetchContent` 在 configure 阶段下载失败 | 包在 configure 时拉 GitHub 依赖（如 `melondsds` 拉 11 个） | 同上一行 —— `insteadOf` 对 FetchContent 同样生效 |
| `No targets specified and no makefile found`（目录空） | 预置的 git 缓存**漏了子模块** | `seed-any-pkg.sh` 重灌（会自动 `submodule update --init --recursive`），并 `rm -rf <build>/build/<pkg>-* <build>/.stamps/<pkg>`（`unpack` 按 stamp 跳过，只换 tarball 不会重新解包） |
| `Cannot get <pkg> sources` + `Unable to establish SSL connection` | 归档源，且 https 降级被 **HSTS** 挡回 | `seed-any-pkg.sh`（走镜像）或让 `~/bin/wget` 包装器生效 |
| `WARNING Incorrect checksum calculated on downloaded file` | 上游 cgit「快照」源重新生成了归档，recipe 里的 SHA256 过期 | **不要直接改哈希**：先重复下载确认字节稳定，再用独立来源交叉验证，然后才更新 `PKG_SHA256` |
| `scripts/extract: line NN: zstdcat: command not found` | 宿主缺 zstd | `fix-build-env.sh --deps-only` |
| `yapp not found` | 只有 `Parse::Yapp` 模块、没有 `yapp` 程序 | 同上（会从 Ubuntu pool 装真包） |
| `The available kernel headers are older than the requested compatible kernel version` | vendor 6.1 内核 headers 比 glibc 默认要求的 6.6 旧 | 已在仓库内修好（`packages/devel/glibc/package.mk` 的 `lubancat-6.1` 分支） |
| `error: unknown value 'cortex-a76.cortex-a53' for '-mtune'` | RK3588 是 4×A76+4×A55，GCC 只认 `cortex-a76.cortex-a55` | 已在仓库内修好 |
| `[-Werror=address]` / `all warnings being treated as errors` | vendor 内核/uboot 的旧代码撞上 GCC 13 的新警告 | 已在仓库内修好（关 `CONFIG_WERROR`、u-boot 加 `KCFLAGS=-Wno-error`） |

---

## 6. 设计取舍说明

- **为什么用镜像而不是配置 HTTP 代理**：宿主机往往没有可用代理；镜像方案零依赖、可随时
  `--unset-mirror` 撤销，且不像代理那样影响全局流量。
- **为什么镜像不影响正确性**：git 有对象级 SHA 校验；归档源有 `PKG_SHA256` 校验。
  镜像最多让下载**失败**，无法让构建**静默接受错误内容**。
- **为什么保留 `seed-*` 这一路**：镜像可能临时不可用，部分仓库也不在 GitHub
  （本项目里 `higan_sfc` 在 gitlab.com、`virtualxt` 在 codeberg.org —— 这些**直连就行**，
  所以 `seed-any-pkg.sh` 只在 host 是 github.com 时才加镜像前缀）。
- **请自行评估镜像可信度**：默认 `gh-proxy.com` 仅为了方便，可通过
  `MIRROR_BASE` / `--mirror` 换成你信任的通道。
