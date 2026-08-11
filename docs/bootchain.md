# Firmware boot chain (verified, do not deviate)

The 3A3000 firmware is **not real UEFI**. It is a PMON-derived shell with
UEFI-like surface behavior, and its quirks will eat your boot media if you
don't design around them.

## The three traps

### 1. ISO images get hijacked (mechanism unknown)

The firmware **mounts ISO images as CD devices** and removes the rest of
your boot media from the boot path. What we know:

- It does not go by file extension — renaming `foo.iso` → `foo.cd` changes
  nothing.
- We hypothesized a magic scan for the ISO9660 signature `CD001` (at
  offset `0x8001`) and built a whole workaround around corrupting the
  magic (`CD001` → `CD00X`) plus a RAM-restore loop-mount helper.
  **That workaround failed in practice**: even with the magic corrupted
  the firmware still hijacked the image. The magic-scan theory is
  **disproven**; the real detection mechanism is **unknown**.
- Practical consequence: don't design boot flows that rely on a FAT
  partition coexisting with ISO files on the same removable medium. The
  layout that actually worked is the **repacked ISO written straight to
  the stick with `dd`** (see `iso/`). With a pure-ISO medium there is
  nothing to hijack — the ISO *is* the boot medium.

### 2. Only ELF-format GRUB boots

The firmware boots **ELF 32-bit MIPS N32** `grub.efi` (578,728 bytes,
byte-identical to the one in the Loongnix ISO). The PE32+ `BOOTMIPS.EFI`
UEFI path (`EFI/BOOT/`) is **dead code** on this firmware — don't bother.

### 3. PMON-style boot.cfg is the entry point

The firmware reads `boot.cfg` (PMON syntax), and the working chain is:

```
boot.cfg
  kernel (usb0,0)/boot/grub.efi      <- ELF GRUB, must go through GRUB
    -> grub.cfg (GRUB prefix is "%s/grub.cfg", i.e. /boot/grub.cfg)
      -> linux /boot/vmlinuz console=tty0     <- VGA, never serial-only
      -> initrd /boot/initrd.gz
```

Booting a kernel directly from `boot.cfg` (as Loongnix does) does **not**
work on this firmware.

## Hard-disk boot (after Debian is installed)

- The firmware shell command is `start boot\grub.efi` (relative to the
  FAT partition root).
- With FAT32 `/boot` (sda1) + ext4 `/` (sda5):
  - `grub.efi` goes in `/boot/boot/grub.efi`
  - `grub.cfg` goes in `/boot/boot/grub.cfg`
  - kernel/initrd go in `/boot/vmlinuz-*`, `/boot/initrd.img-*`
- GRUB's embedded modules include `ext2` (reads ext4), `fat`, `iso9660`,
  `search`, `linux`, `initrd` — enough for both FAT and ext4 layouts.
- The kernel has **ext4 as a module** → the system initrd **must** be
  rebuilt with `initramfs-tools` (the d-i `initrd.gz` is an installer,
  not a system initrd). `boot/hdd-boot/setup-hdd-boot.sh` does this.

## Layout cheat-sheet

| File | Where it must be | Why |
|---|---|---|
| `boot.cfg` | FAT root `\boot\boot.cfg` (+ copies at `\boot.cfg`) | firmware entry |
| `grub.efi` | FAT `\boot\grub.efi` (= `/boot/boot/grub.efi` on disk) | firmware → GRUB |
| `grub.cfg` | next to grub.efi: `\boot\grub.cfg` | GRUB prefix |
| `vmlinuz` / `initrd.gz` | FAT `\boot\` | GRUB loads |
| `console=tty0` | GRUB linux line | VGA output |

## Golden rules

1. `kernel (usb0,0)/boot/grub.efi` — always through ELF GRUB.
2. `console=tty0` — never serial-only.
3. For removable install media: **repack the ISO and `dd` it** — do not
   rely on FAT layouts; ISO files get hijacked by the firmware and we
   don't know the detection mechanism, so we can't reliably dodge it.
4. On the installed hard disk, don't keep ISO images lying around either —
   the firmware scans disks too.
