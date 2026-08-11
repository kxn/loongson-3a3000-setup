# boot/ — boot recipes

Verified boot recipes for the 3A3000's pseudo-UEFI firmware.

| Path | Purpose | Status |
|---|---|---|
| `../iso/` | install medium (repacked netinst ISO, `dd` to stick) | ✅ used for the install |
| `vga-stick/` | minimal VGA console test (kernel + busybox initrd) | ✅ QEMU-verified; HW paths documented in its README |
| `hdd-boot/` | hard-disk GRUB installer (post-install) | ✅ used on the reference machine |

## Which one do I need?

- **Install**: `../iso/repack-iso.sh` → `dd` to a USB stick.
- **VGA sanity check** (black screen): `vga-stick/` — boots to a shell
  with the framebuffer console, isolates kernel-vs-initrd-vs-hardware
  display problems.
- **After Debian is on the disk**: `hdd-boot/setup-hdd-boot.sh`.

## Common thread

All recipes follow the same boot chain (see `docs/bootchain.md`):

```
boot.cfg -> ELF grub.efi -> grub.cfg -> vmlinuz (console=tty0) + initrd
```
