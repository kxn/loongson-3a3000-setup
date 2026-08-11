Loongson 3A3000 VGA console test stick
=====================================
Kernel: Linux 6.1.176 (Debian 6.1.176 source + ported Loongson LS2H/LS7A
        framebuffer drivers, CONFIG_FB_LS2H=y / CONFIG_FB_LS7A=y, fbcon=y)
Initrd: busybox test initrd (static, 1.1MB)

Files (copy ALL to the ROOT of a FAT32 USB stick):
  BOOT/BOOT.CFG     PMON boot menu (copies at boot/boot.cfg and /boot.cfg)
  vmlinux           19MB stripped kernel (ELF64 MIPS little-endian)
  initrd.gz         test initrd

Menu entry 1: kernel + initrd -> should boot to an interactive shell
Menu entry 2: kernel only     -> boots, panics "no rootfs", but you still
              see all kernel messages on screen (isolates initrd problems)

Boot args (both entries): console=ttyS0,115200 console=tty loglevel=7
  -> VGA text console (tty) is the primary console, serial is also enabled

Which GPU this covers:
  LS2H bridge (2H DC at 0x1be50000)  -> ls2hfb (built in)   <-- most 3A3000
  LS7A bridge (PCI 0x0014:0x7a06)    -> ls7afb (built in)
  RS780E / external ATI              -> radeonfb (built in)

QEMU-verified: kernel boots, initrd loads (rd_start/rd_size), shell works.
The LS2H/LS7A hardware paths themselves can only be tested on your machine.

If the screen is STILL black after this:
  - the machine's display is wired to something we don't cover, or
  - PMON hands the display to the GPU in a state we don't expect.
  Serial (console=ttyS0,115200) will show what's happening either way.
