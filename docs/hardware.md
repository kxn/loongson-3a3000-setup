# Hardware facts (verified on the reference machine)

## Machine

| Item | Value |
|---|---|
| CPU | Loongson 3A3000, 4× GS464E @ ~1.45 GHz, MIPS64el (little-endian) |
| Bridge | LS7A (boards with LS2H also exist — both framebuffer drivers provided) |
| RAM | 8 GB DDR3 (7.8 GiB visible) |
| NIC | Realtek RTL8168h/8111h gigabit (`r8169`) |
| Disk | Mechanical HDD (SATA, AHCI) — slow, known |
| RTC | **None** — `/dev/rtc` does not exist; kernel has no loongson RTC driver enabled. Time comes from NTP (`timedatectl` shows `synchronized: yes` after boot). |
| Firmware | PMON-derived "pseudo-UEFI" shell (see `bootchain.md`) |
| OS | Debian 12 bookworm, `6.1.0-50-loongson-3`, mips64el |

## Kernel details

- `uname -r`: `6.1.0-50-loongson-3`
- Built-in (no modules needed): SATA/AHCI, sd, USB, PS/2, VFAT, **LS2H/LS7A framebuffer**
- Modules: full tree 2801 `.ko` (the custom d-i initrd only ships 1469 —
  see `initrd/README.md` for why and how to restore)
- `CONFIG_FB_LS2H=y`, `CONFIG_FB_LS7A=y`, `CONFIG_FB_RADEON=y` (RS780E / external ATI fallback)

## Boot-time noise that is harmless

```
i8042: i8042 controller selftest timeout     <- no keyboard attached, fine
usbhid: can't add hid device: -62            <- no HID device, fine
This architecture does not have kernel memory protection.  <- MIPS design, not a fault
Warning: PIX clock precision degraded to 50/10000          <- radeonfb, harmless
Problem parsing in-kernel X.509 certificate list           <- unsigned kernel, harmless
```

## The one real boot-time warning (fixed)

```
r8169: firmware: failed to load rtl_nic/rtl8168h-2.fw (-2)
```

Fix: enable `non-free-firmware` in `sources.list` and install
`firmware-realtek` (see `docs/first-boot.md`). Without it the NIC still
works but without power management / advanced features.

## Boot flow of the reference machine (verbatim)

```
firmware shell: start boot\grub.efi
  -> /boot/grub.cfg
    -> linux /vmlinuz-6.1.0-50-loongson-3 root=UUID=<sda5> console=tty0
    -> initrd /initrd.img-6.1.0-50-loongson-3   (rebuilt by initramfs-tools)
```
