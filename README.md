All information on Archboot is located [here](https://archboot.com).

The corresponding files are licensed under the GNU General Public License, version 3 or later 
as per the included LICENSE file.

```
mkdir boot
archboot-x86_64-create-container.sh boot
systemd-nspawn -D
archboot-cpio.sh -c /etc/archboot/x86_64.conf -g initrd-x86_64.img

/usr/lib/systemd/ukify build --linux=$HOME/boot/usr/lib/modules/6.8.2-arch2-1/vmlinuz --initrd=$HOME/boot/boot/intel-ucode.img --initrd=$HOME/boot/boot/amd-ucode.img --initrd=$HOME/boot/root/initrd-x86_64.img --cmdline=@/code/cmdline --os-release=@/usr/share/archboot/base/etc/os-release --splash=/usr/share/archboot/uki/archboot-background.bmp --output=/code/example.efi
```

&#169; 2006 - 2024 | [Tobias Powalowski](mailto:<tpowa@archlinux.org>) | Arch Linux Developer [tpowa](https://archlinux.org/people/developers/#tpowa)
