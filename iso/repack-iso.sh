#!/bin/bash
# ============================================================
# repack-iso.sh - build the bootable Debian netinst ISO for the
# Loongson 3A3000's pseudo-UEFI firmware.
# ------------------------------------------------------------
# Verified against the ISO that actually installed the reference
# machine (debian-12.15.0-mips64el-netinst-custom3.iso).
#
# Why repack instead of FAT+files? The firmware hijacks ISO images
# on removable media (mechanism unknown, see docs/bootchain.md), so
# the medium itself must BE an ISO. There is no El Torito boot
# record involved: the firmware reads /boot/boot.cfg from the ISO
# (Rock Ridge) filesystem directly.
#
# Usage:
#   ./repack-iso.sh --base-iso debian-12.15.0-mips64el-netinst.iso \
#                   --kernel vmlinuz --initrd initrd.gz \
#                   --grub-efi grub.efi \
#                   --out debian-12.15.0-mips64el-netinst-custom.iso
#
# Inputs:
#   --base-iso   official Debian netinst ISO for mips64el (required)
#   --kernel     custom vmlinuz (kernel/ build output)
#   --initrd     custom d-i initrd (initrd/ build output)
#   --grub-efi   ELF MIPS N32 grub.efi (from the Loongnix ISO)
#   --out        output ISO path
#   --kver       kernel release string (default 6.1.0-50-loongson-3)
# ============================================================
set -euo pipefail

KVER="6.1.0-50-loongson-3"
BASE_ISO=""
KERNEL=""
INITRD=""
GRUB_EFI=""
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base-iso) BASE_ISO="$2"; shift 2 ;;
    --kernel)   KERNEL="$2";   shift 2 ;;
    --initrd)   INITRD="$2";   shift 2 ;;
    --grub-efi) GRUB_EFI="$2"; shift 2 ;;
    --out)      OUT="$2";      shift 2 ;;
    --kver)     KVER="$2";     shift 2 ;;
    *) echo "!! unknown arg: $1" >&2; exit 1 ;;
  esac
done

for v in BASE_ISO KERNEL INITRD GRUB_EFI OUT; do
  [ -n "${!v}" ] || { echo "!! missing --$(echo $v | tr A-Z a-z)" >&2; exit 1; }
done
for f in "$BASE_ISO" "$KERNEL" "$INITRD" "$GRUB_EFI"; do
  [ -f "$f" ] || { echo "!! not found: $f" >&2; exit 1; }
done
command -v xorriso >/dev/null || { echo "!! xorriso not installed (apt install xorriso)" >&2; exit 1; }

WORK="$(mktemp -d /tmp/repack-iso.XXXXXX)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
TREE="$WORK/tree"

echo "== 1/5 extract base ISO =="
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE" >/dev/null 2>&1
# ISO dirs come out 0555; make the tree writable for the steps below
chmod -R u+w "$TREE"

echo "== 2/5 stage boot files =="
mkdir -p "$TREE/boot/grub" "$TREE/install/loongson-3/netboot"
cp "$KERNEL"   "$TREE/boot/vmlinuz"
cp "$INITRD"   "$TREE/boot/initrd.gz"
cp "$GRUB_EFI" "$TREE/boot/grub.efi"

# firmware entry: /boot/boot.cfg (+ root copy, belt & braces)
cat > "$TREE/boot/boot.cfg" <<'EOF'
default 0
timeout 3
showmenu 1

title Boot GRUB2 (PMON grub.efi, /boot)
    kernel (usb0,0)/boot/grub.efi
    args nil
EOF
cp "$TREE/boot/boot.cfg" "$TREE/boot.cfg"

# GRUB config (identical copy under /boot/grub/ too)
cat > "$TREE/boot/grub.cfg" <<'EOF'
# Loongson 3A3000 GRUB config (ELF grub.efi) - load 6.1 kernel + ls7afb VGA
set pager=1
set timeout=5
set default=0

insmod part_msdos
insmod part_gpt
insmod fat
insmod iso9660
insmod search
insmod search_fs_file
insmod linux
insmod initrd

# Locate this ISO/stick by its root file
search --no-floppy --set=root --file /boot/vmlinuz
if [ -z "${root}" ]; then
  set root='(usb0,0)'
fi

menuentry 'Debian 12 mips64el 6.1.0-50 (ls7afb VGA)' {
  echo 'Loading Linux /boot/vmlinuz ...'
  linux /boot/vmlinuz console=tty0
  echo 'Loading initrd /boot/initrd.gz ...'
  initrd /boot/initrd.gz
  boot
}
EOF
cp "$TREE/boot/grub.cfg" "$TREE/boot/grub/grub.cfg"

echo "== 3/5 stage netboot tree (d-i entry point) =="
cp "$KERNEL" "$TREE/install/loongson-3/netboot/vmlinuz-$KVER"
cp "$INITRD" "$TREE/install/loongson-3/netboot/initrd.gz"
cat > "$TREE/install/loongson-3/netboot/boot.cfg" <<EOF
default 0
timeout 3
showmenu 1

title Debian 12 mips64el $KVER (custom, VGA)
    kernel (usb0,0)/boot/vmlinuz
    initrd (usb0,0)/boot/initrd.gz
    args console=tty0
EOF

echo "== 4/5 repack ISO =="
VOLID="$(xorriso -indev "$BASE_ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id    : //p' | head -1)"
[ -n "$VOLID" ] || VOLID="Debian 12.15.0 m64el n"
xorriso -as mkisofs -o "$OUT" -V "$VOLID" -J -joliet-long -r -iso-level 3 "$TREE" >/dev/null 2>&1

echo "== 5/5 done =="
ls -la "$OUT"
sha256sum "$OUT"

echo
echo "Write to USB stick:"
echo "  dd if=$OUT of=/dev/sdX bs=4M status=progress"
