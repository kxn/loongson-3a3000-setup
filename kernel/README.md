# Custom kernel 6.1.0-50-loongson-3 (with Loongson VGA + CPUFreq + fan drivers)

This is the kernel that runs on the reference machine and is shipped in
the install ISO. It is the **Debian 12 (bookworm) mips64el kernel source
plus Loongson drivers** ported from the Loongnix 4.19 tree
(`github.com/loongson-community/linux-stable`, commit
`5a39ab9 "Ugly workarounds for Loongson-3"`, kernel 4.19.128):

- **LS2H / LS7A framebuffer** drivers (VGA console — without these the
  installer and desktop are headless)
- **loongson3 cpufreq** driver (3A3000 per-core frequency scaling via the
  `LOONGSON_FREQCTRL` registers; the 3A4000+ SMC/CSR/boost path from 4.19
  was removed — this port targets the 3A3000)
- **LS7A fan** control driver (hwmon PWM fan control, 4 channels, made
  self-contained: built-in temperature read + fan policy, registers its
  own platform devices)

## What is in this directory

| File | What |
|---|---|
| `ls2hfb.c` | LS2H framebuffer driver (ported from Loongnix 4.19, adapted to 6.1) |
| `ls7afb.c` | LS7A framebuffer driver (ported from Loongnix 4.19, adapted to 6.1) |
| `loongson3-cpufreq.c` | Loongson-3A3000 CPUFreq driver (ported from Loongnix 4.19, 6.1 API) |
| `ls7a-fan.c` | LS7A PWM fan control driver (ported from Loongnix 4.19, self-contained) |
| `patches/0001-fbdev-kconfig-ls2h-ls7a.patch` | adds `CONFIG_FB_LS2H` / `CONFIG_FB_LS7A` Kconfig entries |
| `patches/0002-fbdev-makefile-ls2h-ls7a.patch` | adds `obj-$(CONFIG_FB_LS2H/LS7A) += ls2hfb.o / ls7afb.o` |
| `patches/0003-arch-mips-loongson64-cpufreq.patch` | `MACH_LOONGSON64` selects `CPU_SUPPORTS_CPUFREQ` + `MIPS_EXTERNAL_TIMER` (6.1 gates the whole cpufreq framework on these) |
| `patches/0004-cpufreq-loongson3.patch` | adds `CONFIG_LOONGSON3_CPUFREQ` + `drivers/cpufreq/loongson3-cpufreq.c` |
| `patches/0005-platform-mips-ls7a-fan.patch` | adds `CONFIG_LS7A_FAN` + `drivers/platform/mips/ls7a-fan.c` |
| `config-6.1.0-50-loongson-3` | full `.config` used for the build |

## Build provenance (verified)

- **Source**: Debian package `linux-source-6.1` version **6.1.176-1**
  (bookworm mips64el) — upstream 6.1.176 + Debian patches. The shipped
  config was derived from Debian's `config-6.1.0-50-loongson-3` via
  `make olddefconfig`.
- **Toolchain**: cross-compiled inside the docker container
  `kbuild-toolchain` (Debian 12 bookworm) with
  `mips64el-linux-gnuabi64-gcc` **(Debian 12.2.0-14) 12.2.0**.
- **Result**: `6.1.0-50-loongson-3 SMP PREEMPT`, built 2026-08-11.
  `vmlinuz-6.1.0-50-loongson-3-cpufreq` (ELF64 MIPS little-endian,
  21,983,976 B), sha256:
  ```
  cf73bc7fe6053d3ad41cc139ad4e18f451e15fee6c635f72ecb272d4f1bc93b4
  ```
  (Previous build without cpufreq/fan: 21,885,160 B,
  `c285d7e271e9dcc80526f2306c234a9a3e74ceeb66520f122a7f6fedd94566fa`.)

## Patch set (everything we changed vs the Debian source)

1. `drivers/video/fbdev/ls2hfb.c` — new file (this directory)
2. `drivers/video/fbdev/ls7afb.c` — new file (this directory)
3. `drivers/video/fbdev/Kconfig` — `patch 0001`
4. `drivers/video/fbdev/Makefile` — `patch 0002`
5. `arch/mips/Kconfig` — `patch 0003`: `MACH_LOONGSON64` now selects
   `CPU_SUPPORTS_CPUFREQ` and `MIPS_EXTERNAL_TIMER`. In 6.1 the whole
   `drivers/cpufreq/` tree is only sourced when both are set; Loongson-3
   supports frequency scaling, and `MIPS_EXTERNAL_TIMER` is a pure
   Kconfig gate (no code effect) for loongson64.
6. `drivers/cpufreq/loongson3-cpufreq.c` + Kconfig/Makefile — `patch 0004`
7. `drivers/platform/mips/ls7a-fan.c` + Kconfig/Makefile — `patch 0005`
8. `.config` — `CONFIG_FB_LS2H=y`, `CONFIG_FB_LS7A=y` (built-in),
   `CONFIG_FB_RADEON=y` (RS780E / external ATI),
   `CONFIG_CPU_FREQ=y` + `CONFIG_LOONGSON3_CPUFREQ=y` (built-in,
   default governor `schedutil`; `performance`/`userspace`/`ondemand`
   also enabled), `CONFIG_LS7A_FAN=y` (built-in).

Everything else is stock Debian — in particular the loongson64 platform
code already handles 3A3000 + LS7A/LS2H bridges (DT-based), and
`loongson_freqctrl[]` is already populated by `arch/mips/loongson64/env.c`
(so the cpufreq driver needs no arch-side additions).

## Porting notes (4.19 → 6.1)

- **loongson3-cpufreq.c**: removed the 3A4000+ SMC/CSR/boost path and the
  transition notifier (3A3000 has a constant-rate timer, so no
  clockevent/udelay recalibration is needed). Frequency get/set go
  straight to `LOONGSON_FREQCTRL` (4 bits per core, level 1..8 →
  `cpu_clock_freq * level / 8`), same as 4.19's `clock.c` did via the
  legacy clk shim.
- **ls7a-fan.c**: 4.19 got fan policies and platform devices from the
  firmware `sensors[]` table and arch `platform.c` globals; 6.1 no longer
  instantiates those, so the driver now carries its own step-speed policy
  and temperature read (`LOONGSON_CHIPTEMP`, same formula as
  `cpu_hwmon`), and registers its 4 platform devices itself.
  `hwmon_device_register()` (deprecated) → `hwmon_device_register_with_info()`.

## Build flow (cross, in the kbuild-toolchain container)

```sh
# inside the container, with the Debian source extracted:
apt-get install -y crossbuild-essential-mips64el libncurses-dev
cp config-6.1.0-50-loongson-3 .config      # our shipped config
cp ls2hfb.c ls7afb.c drivers/video/fbdev/
cp loongson3-cpufreq.c drivers/cpufreq/
cp ls7a-fan.c drivers/platform/mips/
patch -p1 < patches/0001-fbdev-kconfig-ls2h-ls7a.patch
patch -p1 < patches/0002-fbdev-makefile-ls2h-ls7a.patch
patch -p1 < patches/0003-arch-mips-loongson64-cpufreq.patch
patch -p1 < patches/0004-cpufreq-loongson3.patch
patch -p1 < patches/0005-platform-mips-ls7a-fan.patch

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
- After boot with the new kernel: `/sys/devices/system/cpu/cpu*/cpufreq/`
  should appear (loongson3 driver), and `/sys/class/hwmon/` should gain an
  `ls7a-fan` entry with `pwm1..pwm4` / `pwmN_enable` attributes.
