================================================================
 Loongson 3A3000 hard-disk bootloader guide (hdd-boot v5)
 Target: /boot = FAT32 partition (sda1) + / = ext4 (sda5)
 Works inside chroot (zero mount probing)
================================================================

[Why this partition plan]
The earlier concern was "does the firmware shell read ext2/ext4?".
Using FAT32 for /boot removes that question entirely:
  - firmware (pseudo EFI shell / PMON lineage) reads FAT - proven
  - GRUB embeds the fat module - proven
  - kernel/initrd also load from FAT via GRUB
  - root ext4 (sda5) is mounted by kernel+initramfs; ext4.ko is in
    our initramfs
Every link in the chain is certain; no gambling on firmware ext4.

[Layout on disk] (FAT partition mounted as /boot)
  Inside FAT (sda1):          System path:
  \boot\grub.efi      <- firmware start target   /boot/boot/grub.efi
  \boot\grub.cfg      <- GRUB config             /boot/boot/grub.cfg
  \vmlinuz-6.1.0-50-loongson-3                   /boot/vmlinuz-...
  \initrd.img-6.1.0-50-loongson-3                /boot/initrd.img-...

NOTE: firmware shell `start boot\grub.efi` is relative to the FAT
partition root, so grub.efi MUST be in the boot\ subdirectory of the
FAT partition = /boot/boot/grub.efi (NOT /boot/grub.efi!). Once GRUB
is up it looks for grub.cfg via its prefix (=boot\); kernel/initrd
paths in grub.cfg are written as /vmlinuz-... (FAT root).

[Steps]

1. Copy 4 files to a root-readable dir on the target (e.g. /root/boot-files/):
     - vmlinuz      (custom 6.1.0-50-loongson-3, 21.9MB, ls7afb VGA)
     - initrd.gz    (custom d-i initrd, 45.2MB - contains all our modules)
     - grub.efi     (ELF 578KB)
     - setup-hdd-boot.sh
   Source: the kernel/ and initrd/ build outputs (vmlinuz, initrd.gz)
   and the Loongnix ISO's grub.efi — or extract all three from the
   repack ISO's /boot/ (see iso/README.md). Copy via USB stick or scp.

2. Run (as root, in chroot or on the target):
     chmod +x setup-hdd-boot.sh
     ./setup-hdd-boot.sh /root/boot-files /dev/sda5
   Or pass the UUID directly (use this when chroot has no /dev):
     ./setup-hdd-boot.sh /root/boot-files UUID=xxxxxxxx
   v4 does NO mount probing (/proc/mounts or findmnt unusable in chroot
   is fine); layout and root UUID come purely from arguments. The script:
     1) extracts our modules to /lib/modules (official same-version backed up)
     2) installs the kernel to /boot (official same-version backed up)
     3) rebuilds initrd via update-initramfs (contains ext4.ko, verified)
     4) places grub.efi at /boot/boot/ and writes grub.cfg
        (root=UUID=you-passed console=tty0)
     5) (optional --auto) writes boot.cfg to try auto-boot
     6) verifies files

3. Reboot, drop to firmware shell, run:
     start boot\grub.efi
   GRUB auto-selects entry 1 after 5s -> Debian (VGA console).

[Prerequisites]
- cpio on the target (needed to unpack initrd.gz): apt install cpio
- initramfs-tools on the target: apt install initramfs-tools

[Kernel config note]
update-initramfs needs /boot/config-<version> to detect which initramfs
compression the kernel supports (CONFIG_RD_*). Our custom kernel ships no
config file, so the script writes a minimal stub (/boot/config-<version>
with CONFIG_RD_GZIP=y - gzip is proven since the installer booted our
gzip initrd.gz). If you have the real kernel .config, drop it in the
source dir as config-6.1.0-50-loongson-3 and the script will install it
instead.
  (normally present in a standard Debian install; the script tells you
  to install it if missing)
- If your official kernel is also 6.1.0-50-loongson-3, the script backs
  up the official kernel/modules to .official-bak before installing ours
  (the ones with the VGA port).

[Optional: auto-boot into GRUB (experimental)]
     ./setup-hdd-boot.sh /root/boot-files /dev/sda5 --auto
  Writes boot.cfg (three entries: wd0,0 / hd0,0).
  - Boots straight into GRUB: done, no manual start needed anymore.
  - Black screen at boot: firmware does not honor this auto path.
    Recovery = power off, pull the disk, mount it elsewhere and delete
    boot\boot.cfg on the FAT partition, then manual start boot\grub.efi.

[Troubleshooting]
- start says file not found: make sure grub.efi is under FAT \boot\;
  run dir / ls in the shell to see the FAT partition before starting.
- GRUB menu shows but boot fails: try root=/dev/sda5 instead of
  root=UUID=... in grub.cfg; or check initrd contains ext4.ko
  (gzip -dc /boot/initrd.img-* | cpio -t | grep ext4).
- Black screen, no output: likely firmware auto-boot (boot.cfg) was
  triggered; delete boot.cfg.
================================================================
