# Custom d-i initrd

The install initrd (`initrd.gz`, 45,225,409 B, sha256
`153016ac55d44014a6f98db0e3ac6f1c1efcec76dcfc20ac4dcb840e5fc407d7`) is
the **Debian d-i initrd rebuilt with our custom kernel's modules** plus
one modification. It boots the installer; it is **not** the system
initrd for the installed OS (that one is rebuilt by `initramfs-tools` via
`boot/hdd-boot/setup-hdd-boot.sh`).

## What is inside (vs stock d-i initrd)

1. `lib/modules/6.1.0-50-loongson-3/` — module tree compiled **for the
   custom kernel** (1469 modules: everything the installer needs).
   The stock udebs' modules fail the modversions CRC check against our
   kernel, so they must not be installed — hence (2).
2. `/bin/anna-install` — **neutralized to a no-op** (original kept as
   `anna-install.orig`). `anna` is d-i's "install packages from media"
   step; left alone it would install the stock `linux-*-di` module udebs
   from the ISO and break our kernel's modules. The stub is:

   ```sh
   #!/bin/sh
   # Neutralized: stock d-i module udebs fail modversions CRC against
   # the custom 6.1.0-50-loongson-3 kernel. Initrd already carries the
   # complete module set for this kernel.
   exit 0
   ```

3. `preseed.cfg` — kept minimal; do **not** add the old
   `early_command` hook that mounted a separate ISO from a FAT stick
   (that whole approach was abandoned — see `docs/bootchain.md`).

## Rebuild recipe

```sh
# take the stock d-i initrd from the official netinst ISO:
#   install/loongson-3/netboot/initrd.gz
zcat initrd.gz | cpio -idmv -D rootfs

# 1. replace the module tree with yours (from the kernel build):
rm -rf rootfs/lib/modules/6.1.0-50-loongson-3
cp -a <kernel-build>/modules/lib/modules/6.1.0-50-loongson-3 rootfs/lib/modules/

# 2. neutralize anna:
cp rootfs/bin/anna-install rootfs/bin/anna-install.orig
printf '#!/bin/sh\nexit 0\n' > rootfs/bin/anna-install
chmod +x rootfs/bin/anna-install

# 3. drop mount-iso / early_command from preseed.cfg

# 4. repack:
(cd rootfs && find . | cpio -o -H newc | gzip -9 > ../initrd.gz)
```

## Missing netfilter after install (known consequence)

The 1469-module subset is chosen for the installer; **netfilter is not in
it**, so a freshly installed system has no `nft`/`iptables` support
("Protocol not supported"). To restore the full module set on the
installed machine, sync the **full** tree from the kernel build
(2801 `.ko`, same build — vermagic and modversions must match):

```sh
# on the build machine:
tar cf - -C <kernel-build>/modules/lib/modules/6.1.0-50-loongson-3 . | \
  ssh kxn@<host> 'sudo tar xf - --keep-old-files -C /lib/modules/6.1.0-50-loongson-3'

# on the target:
sudo depmod -a
sudo modprobe nf_tables && sudo modprobe ip_tables
echo nf_tables | sudo tee /etc/modules-load.d/netfilter.conf
```

After that, firewall rules are plain Debian admin (out of scope here).

## Verification

```sh
# initrd must carry the custom kernel's modules:
zcat initrd.gz | cpio -t | grep -c "lib/modules/6.1.0-50-loongson-3"
# anna must be the stub:
zcat initrd.gz | cpio -i --to-stdout bin/anna-install
```
