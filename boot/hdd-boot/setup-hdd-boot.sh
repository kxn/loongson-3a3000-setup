#!/bin/bash
# ============================================================
# setup-hdd-boot.sh v6 - Loongson 3A3000 hard-disk bootloader installer
# ------------------------------------------------------------
# chroot-friendly: NO mount probing (/proc/mounts / findmnt unusable in
# chroot). Layout and root UUID are passed as arguments.
#
# Partition plan (confirmed):
#   /boot = FAT32 partition (sda1, 200M)   +   / = ext4 (sda5)
# Boot chain (firmware shell):
#   start boot\grub.efi                 <- FAT \boot\grub.efi (= /boot/boot/grub.efi)
#     -> GRUB reads \boot\grub.cfg      (= /boot/boot/grub.cfg)
#       -> linux /vmlinuz-6.1.0-50-loongson-3 root=UUID=<sda5> console=tty0
#       -> initrd /initrd.img-6.1.0-50-loongson-3   <- rebuilt by initramfs-tools, contains our ext4.ko
#
# Usage (run as root, in chroot or on the target machine):
#   setup-hdd-boot.sh <src-dir> <root-device|UUID> [--auto] [--layout=fat|ext]
#     <src-dir>        must contain: vmlinuz  initrd.gz  grub.efi
#                      optional: config-6.1.0-50-loongson-3 (kernel .config;
#                      if absent a minimal stub with CONFIG_RD_GZIP=y is written)
#     <root-device|UUID>  /dev/sda5  or  UUID=xxxx  or bare UUID
#     --auto           also write boot.cfg to try firmware auto-boot (experimental)
#     --layout=ext     only needed if /boot is NOT FAT (default: fat)
# Examples:
#   ./setup-hdd-boot.sh /root/boot-files /dev/sda5
#   ./setup-hdd-boot.sh /root/boot-files UUID=abcd-1234 --auto
# ============================================================
set -e

SRC="${1:?usage: setup-hdd-boot.sh <src-dir> <root-device|UUID> [--auto] [--layout=fat|ext]}"
ROOT_SPEC="${2:?missing root device/UUID argument}"
AUTO=0
LAYOUT=fat
for a in "${@:3}"; do
  case "$a" in
    --auto)       AUTO=1 ;;
    --layout=*)   LAYOUT="${a#--layout=}" ;;
    *) echo "unknown argument: $a"; exit 1 ;;
  esac
done
[ "$LAYOUT" = "fat" ] || [ "$LAYOUT" = "ext" ] || { echo "!! --layout accepts only fat or ext"; exit 1; }
KVER="6.1.0-50-loongson-3"

[ "$(id -u)" = "0" ] || { echo "must run as root"; exit 1; }
for f in vmlinuz initrd.gz grub.efi; do
  [ -f "$SRC/$f" ] || { echo "missing $SRC/$f"; exit 1; }
done

# ---- 0. root UUID (no probing, taken from argument) ----
case "$ROOT_SPEC" in
  UUID=*) ROOT_UUID="${ROOT_SPEC#UUID=}" ;;
  /dev/*) ROOT_UUID=$(blkid -s UUID -o value "$ROOT_SPEC" 2>/dev/null || true)
          [ -n "$ROOT_UUID" ] || { echo "!! cannot get UUID of $ROOT_SPEC (no /dev in chroot?), pass UUID=xxxx directly"; exit 1; } ;;
  *)      ROOT_UUID="$ROOT_SPEC" ;;
esac
case "$ROOT_UUID" in
  *[!0-9a-fA-F-]*) echo "!! invalid characters in root UUID: '$ROOT_UUID' (check: blkid -s UUID -o value /dev/sda5)"; exit 1;;
esac
echo "$ROOT_UUID" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
  || { echo "!! root UUID '$ROOT_UUID' is not a canonical 8-4-4-4-12 UUID. Get it with: blkid -s UUID -o value /dev/sda5"; exit 1; }
echo "== layout: /boot=$LAYOUT   / root UUID=$ROOT_UUID"

# ---- 1. kernel modules (extract from custom initrd.gz, back up official same-version first) ----
echo "== 1/6 install kernel modules =="
command -v cpio >/dev/null || { echo "!! cpio not found (apt install cpio, then rerun)"; exit 1; }
if [ -d "/lib/modules/$KVER" ] && [ ! -d "/lib/modules/$KVER.official-bak" ]; then
  mv "/lib/modules/$KVER" "/lib/modules/$KVER.official-bak"
  echo "    official modules backed up -> /lib/modules/$KVER.official-bak"
fi
mkdir -p /lib/modules
# Unpack the whole initrd to a temp dir, then copy only our modules out.
# (cpio per-path extraction was unreliable: './lib/modules/...' matches nothing.)
TMPX="$(mktemp -d /tmp/hddboot.XXXXXX 2>/dev/null || echo /tmp/hddboot.$$)"
if ! gzip -t "$SRC/initrd.gz" 2>/dev/null; then
  echo "!! $SRC/initrd.gz is not valid gzip"; rm -rf "$TMPX"; exit 1
fi
if ! ( cd "$TMPX" && gzip -dc "$SRC/initrd.gz" | cpio -id --quiet ) 2>/dev/null; then
  echo "!! failed to unpack $SRC/initrd.gz"; rm -rf "$TMPX"; exit 1
fi
if [ -d "$TMPX/lib/modules/$KVER" ]; then
  rm -rf "/lib/modules/$KVER"
  cp -a "$TMPX/lib/modules/$KVER" "/lib/modules/$KVER"
else
  echo "!! $SRC/initrd.gz has no lib/modules/$KVER (is it our custom initrd?)"; rm -rf "$TMPX"; exit 1
fi
rm -rf "$TMPX"
[ -d "/lib/modules/$KVER" ] || { echo "!! module extraction failed"; exit 1; }
echo "    module count: $(find /lib/modules/$KVER -name '*.ko*' | wc -l)"

# ---- 2. kernel ----
echo "== 2/6 install kernel =="
if [ -f "/boot/vmlinuz-$KVER" ] && [ ! -f "/boot/vmlinuz-$KVER.official-bak" ]; then
  cp -a "/boot/vmlinuz-$KVER" "/boot/vmlinuz-$KVER.official-bak"
  echo "    official kernel backed up -> /boot/vmlinuz-$KVER.official-bak"
fi
cp -f "$SRC/vmlinuz" "/boot/vmlinuz-$KVER"
cp -f "$SRC/vmlinuz" /boot/vmlinuz
echo "    /boot/vmlinuz-$KVER in place"

# ---- 3. initramfs (required: ext4.ko is a module) ----
echo "== 3/6 rebuild initramfs =="
command -v update-initramfs >/dev/null || { echo "!! initramfs-tools missing: apt install initramfs-tools, then rerun"; exit 1; }
# update-initramfs greps /boot/config-$KVER (CONFIG_RD_*) to pick initramfs
# compression. Our custom kernel ships no config file; gzip is proven
# supported (the installer booted our gzip initrd.gz). Install the real
# config if present in the source dir, otherwise write a minimal stub.
if [ ! -f "/boot/config-$KVER" ]; then
  if [ -f "$SRC/config-$KVER" ]; then
    cp -f "$SRC/config-$KVER" "/boot/config-$KVER"
    echo "    kernel config installed from source -> /boot/config-$KVER"
  else
    cat > "/boot/config-$KVER" <<'CFG'
# Minimal kernel config for initramfs-tools compression detection.
# The real .config is not shipped; CONFIG_RD_GZIP=y is proven by the
# installer having booted our gzip initrd.gz.
CONFIG_RD_GZIP=y
CFG
    echo "    WARN: no kernel config in source; wrote minimal /boot/config-$KVER (CONFIG_RD_GZIP=y)"
  fi
fi
update-initramfs -c -k "$KVER"
[ -f "/boot/initrd.img-$KVER" ] || { echo "!! initrd generation failed"; exit 1; }
if ! gzip -dc "/boot/initrd.img-$KVER" 2>/dev/null | cpio -t 2>/dev/null | grep -q 'ext4\.ko'; then
  echo "!! no ext4.ko in initrd, check /lib/modules/$KVER"; exit 1
fi
echo "    initrd rebuilt with ext4.ko: /boot/initrd.img-$KVER"

# ---- 4. grub.efi + grub.cfg ----
echo "== 4/6 place GRUB boot files =="
if [ "$LAYOUT" = "fat" ]; then
  # FAT /boot: firmware shell `start boot\grub.efi` looks for \boot\grub.efi on the FAT partition
  mkdir -p /boot/boot
  cp -f "$SRC/grub.efi" /boot/boot/grub.efi
  GRUB_CFG=/boot/boot/grub.cfg
  KERNEL_PATH="/vmlinuz-$KVER"
  INITRD_PATH="/initrd.img-$KVER"
else
  cp -f "$SRC/grub.efi" /boot/grub.efi
  GRUB_CFG=/boot/grub.cfg
  KERNEL_PATH="/boot/vmlinuz-$KVER"
  INITRD_PATH="/boot/initrd.img-$KVER"
fi

cat > "$GRUB_CFG" <<EOF
# Loongson 3A3000 GRUB config - /boot=$LAYOUT, /=$ROOT_UUID, ls7afb VGA
# FAT /boot: grub.efi lives under boot\\ on the FAT partition, so GRUB's
# root is that partition by default; kernel/initrd are fetched from the
# FAT root (/vmlinuz-...). If root is wrong, fix the partition number below.
set pager=1
set timeout=5
set default=0

insmod part_msdos
insmod part_gpt
insmod fat
insmod ext2
insmod search
insmod search_fs_uuid
insmod linux
insmod initrd

if [ "\${root}" = "" ]; then
  set root='(hd0,msdos1)'
fi

menuentry 'Debian 12 mips64el 6.1.0-50-loongson-3 (ls7afb VGA)' {
  echo 'Loading Linux ...'
  linux $KERNEL_PATH root=UUID=$ROOT_UUID console=tty0
  echo 'Loading initrd ...'
  initrd $INITRD_PATH
  boot
}
EOF
echo "    wrote $GRUB_CFG"

# ---- 5. boot.cfg (only with --auto, experimental) ----
if [ "$AUTO" = "1" ]; then
  echo "== 5/6 write boot.cfg (experimental auto-boot) =="
  [ "$LAYOUT" = "fat" ] && BCFG=/boot/boot/boot.cfg || BCFG=/boot/boot.cfg
  cat > "$BCFG" <<'EOF'
default 0
timeout 3
showmenu 1

title Boot GRUB2 (wd0,0)
    kernel (wd0,0)/boot/grub.efi
    args nil

title Boot GRUB2 (hd0,0)
    kernel (hd0,0)/boot/grub.efi
    args nil
EOF
  echo "    wrote $BCFG (if screen goes black at boot, delete this file to restore manual start)"
fi

# ---- 6. verification ----
echo "== 6/6 verification =="
echo "--- grub.efi ---"
[ "$LAYOUT" = "fat" ] && file /boot/boot/grub.efi || file /boot/grub.efi
echo "--- /boot content ---"
ls -la /boot/ | grep -E 'vmlinuz|initrd' || true
echo "--- layout ---"
[ "$LAYOUT" = "fat" ] && ls -la /boot/boot/
echo
echo "Done! Reboot, drop to the firmware shell, and run:"
echo "  start boot\\grub.efi"
echo "GRUB auto-boots Debian (VGA) after 5 seconds."
