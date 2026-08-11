# Install ISO (repack)

The install medium is a **repacked Debian netinst ISO**, written to a USB
stick with `dd`. FAT+file layouts are unusable on this firmware (ISO
hijacking, mechanism unknown — see `docs/bootchain.md`); a pure-ISO medium
has nothing to hijack.

## Script

`./repack-iso.sh` does the whole job. Inputs:

| Input | Where it comes from |
|---|---|
| `--base-iso` | official `debian-12.15.0-mips64el-netinst.iso` |
| `--kernel` | custom `vmlinuz` — output of the `kernel/` build |
| `--initrd` | custom `initrd.gz` — output of the `initrd/` build |
| `--grub-efi` | ELF MIPS N32 `grub.efi` (578,728 B, from the Loongnix ISO) |
| `--out` | output ISO path |

```sh
./repack-iso.sh \
  --base-iso debian-12.15.0-mips64el-netinst.iso \
  --kernel   vmlinuz \
  --initrd   initrd.gz \
  --grub-efi grub.efi \
  --out      debian-12.15.0-mips64el-netinst-custom.iso

dd if=debian-12.15.0-mips64el-netinst-custom.iso of=/dev/sdX bs=4M status=progress
```

## What the script adds to the official ISO

```
/boot/boot.cfg                      PMON menu -> loads grub.efi
/boot.cfg                           identical copy (belt & braces)
/boot/grub.efi                      ELF MIPS N32 (only boot entry that works)
/boot/grub.cfg                      GRUB config (console=tty0)
/boot/grub/grub.cfg                 identical copy
/boot/vmlinuz                       custom kernel (ls2h/ls7afb VGA)
/boot/initrd.gz                     custom d-i initrd (anna no-op)
/install/loongson-3/netboot/vmlinuz-6.1.0-50-loongson-3   custom kernel
/install/loongson-3/netboot/initrd.gz                      custom initrd
/install/loongson-3/netboot/boot.cfg                       d-i menu entry
```

Everything else (pool/, dists/, firmware/, install/ content) stays
untouched. There is **no El Torito boot record** — the firmware reads
`/boot/boot.cfg` straight off the ISO filesystem.

## Forbidden / useless on this firmware

- `EFI/BOOT/BOOTMIPS.EFI` (PE32+ path — dead)
- serial-only console args
- booting a kernel directly from `boot.cfg` (must go through ELF GRUB)

## Shipped artifact (reference build)

```
debian-12.15.0-mips64el-netinst-custom3.iso   695 MB
```
