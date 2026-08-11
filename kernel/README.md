# Custom kernel 6.1.0-50-loongson-3 (with Loongson VGA drivers)

This is the kernel that runs on the reference machine and is shipped in
the install ISO. It is the **Debian 12 (bookworm) mips64el kernel source
plus the Loongson LS2H / LS7A framebuffer drivers** ported from the
Loongnix 4.19 tree.

## What is in this directory

| File | What |
|---|---|
| `ls2hfb.c` | LS2H framebuffer driver (ported from Loongnix 4.19, adapted to 6.1) |
| `ls7afb.c` | LS7A framebuffer driver (ported from Loongnix 4.19, adapted to 6.1) |
| `patches/0001-fbdev-kconfig-ls2h-ls7a.patch` | adds `CONFIG_FB_LS2H` / `CONFIG_FB_LS7A` Kconfig entries |
| `patches/0002-fbdev-makefile-ls2h-ls7a.patch` | adds `obj-$(CONFIG_FB_LS2H/LS7A) += ls2hfb.o / ls7afb.o` |
| `config-6.1.0-50-loongson-3` | full `.config` used for the build |

## Build provenance (verified)

- **Source**: Debian package `linux-source-6.1` version **6.1.176-1**
  (bookworm mips64el) — upstream 6.1.176 + Debian patches. The shipped
  config was derived from Debian's `config-6.1.0-50-loongson-3` via
  `make olddefconfig`.
- **Toolchain**: cross-compiled inside the docker container
  `kbuild-toolchain` (Debian 12 bookworm) with
  `mips64el-linux-gnuabi64-gcc` **(Debian 12.2.0-14) 12.2.0**.
- **Result**: `6.1.0-50-loongson-3 #3 SMP PREEMPT`, built
  2026-08-11. `vmlinuz` (ELF64 MIPS little-endian, 21,885,160 B),
  sha256:
  ```
  c285d7e271e9dcc80526f2306c234a9a3e74ceeb66520f122a7f6fedd94566fa
  ```

## Patch set (everything we changed vs the Debian source)

1. `drivers/video/fbdev/ls2hfb.c` — new file (this directory)
2. `drivers/video/fbdev/ls7afb.c` — new file (this directory)
3. `drivers/video/fbdev/Kconfig` — `patch 0001`
4. `drivers/video/fbdev/Makefile` — `patch 0002`
5. `.config` — `CONFIG_FB_LS2H=y`, `CONFIG_FB_LS7A=y` (both drivers
   built-in; `CONFIG_FB_RADEON=y` already present for RS780E / external
   ATI)

Nothing else was touched — in particular `arch/mips/` is stock Debian
(loongson64 platform code already handles 3A3000 + LS7A/LS2H bridges).

The drivers were ported from the Loongnix 4.19 kernel tree
(`linux-stable-4.19.tar.gz` + Loongson additions); the 6.1 port mainly
adjusted the fbdev API (`fb_info`/`fb_ops` changes). Both files are
GPL-2.0 (kernel-derived).

## Build flow (cross, in the kbuild-toolchain container)

```sh
# inside the container, with the Debian source extracted:
apt-get install -y crossbuild-essential-mips64el libncurses-dev
cp config-6.1.0-50-loongson-3 .config      # our shipped config
cp ls2hfb.c ls7afb.c drivers/video/fbdev/
patch -p1 < patches/0001-fbdev-kconfig-ls2h-ls7a.patch
patch -p1 < patches/0002-fbdev-makefile-ls2h-ls7a.patch

make ARCH=mips CROSS_COMPILE=mips64el-linux-gnuabi64- olddefconfig
make ARCH=mips CROSS_COMPILE=mips64el-linux-gnuabi64- -j$(nproc) vmlinux
# strip for the firmware:
mips64el-linux-gnuabi64-strip -o vmlinuz vmlinux

# modules (full tree — 2801 .ko):
make ARCH=mips CROSS_COMPILE=mips64el-linux-gnuabi64- modules
make ARCH=mips CROSS_COMPILE=mips64el-linux-gnuabi64- \
     INSTALL_MOD_PATH=$PWD/modules modules_install
```

## Notes

- **The full module tree matters.** The install initrd (`initrd/`) and the
  installed system only carry a subset of modules unless you deliberately
  sync the whole `modules_install` output — that is why e.g. netfilter is
  missing out of the box (see `initrd/README.md`).
- `vga-stick/` uses this same kernel as a minimal VGA console test
  (`boot/vga-stick/`).
