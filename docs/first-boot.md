# First-boot checks (3A3000-specific)

Assumes: Debian 12 installed from the custom ISO (`iso/`), booted into the
installed system. This page only covers things that are **specific to this
machine / this setup**. Generic Linux admin (sudo, SSH keys, updates) is
out of scope.

## 1. VGA console

Boot was done with `console=tty0` and the LS7A (or LS2H) framebuffer
driver built into the kernel. You should see kernel messages and a
login prompt on the attached VGA screen. If the screen is black:

- check the serial console `console=ttyS0,115200` for messages;
- test the display path in isolation with the `boot/vga-stick/` kernel
  (isolates kernel vs initrd vs hardware);
- the board may be wired to a display the drivers don't cover (LS2H vs
  LS7A vs RS780E/ATI — see `kernel/README.md`).

## 2. NIC firmware (this board's NIC)

`dmesg` may show `r8169: firmware: failed to load rtl_nic/rtl8168h-2.fw`.
This board has a Realtek RTL8168h/8111h. Fix:

```sh
sudo sed -i 's/^deb \(http:\/\/[^ ]*\/debian\/ bookworm main\)$/deb \1 non-free-firmware/' /etc/apt/sources.list
sudo apt-get update && sudo apt-get install -y firmware-realtek
sudo modprobe -r r8169 && sudo modprobe r8169   # or just reboot
```

## 3. No RTC — time comes from NTP

This machine has **no usable RTC** (`/dev/rtc` absent; the kernel was not
built with a loongson RTC driver). Expect the clock to be wrong at boot
until NTP syncs it:

```sh
timedatectl | grep -E "synchronized|NTP"   # expect: yes / active
```

## 4. Firewall tooling needs module restore

The custom d-i initrd ships only 1469 of the kernel's 2801 modules and
**netfilter is among the missing** — after install, `nft`/`iptables` fail
with "Protocol not supported". Restoring the full module tree and setting
up a firewall is described in `initrd/README.md` (the missing-module
cause) — it is not specific enough to repeat here.

## 5. Hard-disk bootloader

If you installed to a hard disk, finish with
`boot/hdd-boot/setup-hdd-boot.sh` so the machine boots from disk instead
of needing the install stick every time.
