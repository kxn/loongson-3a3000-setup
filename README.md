# Loongson 3A3000 (Debian 12 mips64el) bring-up kit

Everything specific to making a **Loongson 3A3000** machine run Debian 12,
collected and verified on a real reference machine.

The 3A3000 is a MIPS64el SoC (4× GS464E @ ~1.45 GHz) whose firmware is a
PMON-derived "pseudo-UEFI" shell with quirks that make stock install media
unbootable. This repo contains the working recipes:

- **custom kernel** with the Loongson LS2H / LS7A VGA framebuffer drivers
  (missing from mainline), built from the Debian `linux-source-6.1`
  package with a documented patch set;
- **custom d-i initrd** (anna neutralized so the installer keeps our
  kernel's modules);
- **install ISO repack script** — the only install medium layout that
  works (the firmware hijacks ISO files; see `docs/bootchain.md`);
- **VGA console test stick** and **hard-disk boot installer**.

Scope: this repo deliberately contains **only machine/Loongson-specific
material**. Generic Debian admin (sudo, SSH keys, firewalls, sysctls) is
out of scope.

## Layout

```
docs/bootchain.md       firmware traps + the one boot chain that works
docs/hardware.md        hardware facts, kernel details, harmless boot noise
docs/first-boot.md      3A3000-specific checks after first boot
kernel/                 LS2H/LS7A drivers, patches, .config, build provenance
initrd/                 custom d-i initrd rebuild recipe (anna no-op)
iso/repack-iso.sh       build the install ISO (the actual entry point)
boot/vga-stick/         minimal VGA console test stick
boot/hdd-boot/          hard-disk GRUB installer (post-install)
```

## Quick start

```sh
# 1. kernel:  build per kernel/README.md  ->  vmlinuz
# 2. initrd:  rebuild per initrd/README.md ->  initrd.gz
# 3. ISO:     repack per iso/README.md     ->  custom.iso
dd if=custom.iso of=/dev/sdX bs=4M status=progress
# 4. install on the 3A3000, then finish the disk boot with
#    boot/hdd-boot/setup-hdd-boot.sh
```

For step 3 you also need the ELF `grub.efi` (578,728 B, taken from the
Loongnix ISO — the firmware only boots this one).

## Reference artifact hashes

| File | SHA256 |
|---|---|
| `vmlinuz` (custom kernel 6.1.0-50-loongson-3, 21,885,160 B) | `c285d7e271e9dcc80526f2306c234a9a3e74ceeb66520f122a7f6fedd94566fa` |
| `initrd.gz` (custom d-i initrd, 45,225,409 B) | `153016ac55d44014a6f98db0e3ac6f1c1efcec76dcfc20ac4dcb840e5fc407d7` |
| `grub.efi` (ELF MIPS N32, 578,728 B) | `a03766d136790c994bc4b77087bbf1b0edfc80321a8a0f4241d29ee25fc18078` |

## License

Kernel drivers (`kernel/ls2hfb.c`, `kernel/ls7afb.c`) are GPL-2.0
(kernel-derived). Scripts and documentation are MIT (see `LICENSE`).
