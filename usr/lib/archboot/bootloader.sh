#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
# fedora shim setup
_SHIM_VERSION="15.4"
_SHIM_RELEASE="5"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/${_SHIM_VERSION}/${_SHIM_RELEASE}"
_SHIM_RPM="x86_64/shim-x64-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM32_RPM="x86_64/shim-ia32-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM_AA64_RPM="aarch64/shim-aa64-${_SHIM_VERSION}-${_SHIM_RELEASE}.aarch64.rpm"
_ARCH_SERVERDIR="/src/bootloader"
_GRUB_ISO="/usr/share/archboot/grub/archboot-iso-grub.cfg"

_prepare_shim_files () {
    # download packages from fedora server
    echo "Downloading fedora shim..."
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIM}" ${_SHIM_URL}/${_SHIM_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIM32}" ${_SHIM_URL}/${_SHIM32_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIMAA64}" ${_SHIM_URL}/${_SHIM_AA64_RPM} || exit 1
    # unpack rpm
    echo "Unpacking rpms..."
    bsdtar -C "${_SHIM}" -xf "${_SHIM}"/*.rpm
    bsdtar -C "${_SHIM32}" -xf "${_SHIM32}"/*.rpm
    bsdtar -C "${_SHIMAA64}" -xf "${_SHIMAA64}"/*.rpm 
    echo "Copying shim files..."
    mkdir -m 777 shim-fedora
    cp "${_SHIM}"/boot/efi/EFI/fedora/{mmx64.efi,shimx64.efi} shim-fedora/
    cp "${_SHIM}/boot/efi/EFI/fedora/shimx64.efi" shim-fedora/BOOTX64.efi
    cp "${_SHIM32}"/boot/efi/EFI/fedora/{mmia32.efi,shimia32.efi} shim-fedora/
    cp "${_SHIM32}/boot/efi/EFI/fedora/shimia32.efi" shim-fedora/BOOTIA32.efi
    cp "${_SHIMAA64}"/boot/efi/EFI/fedora/{mmaa64.efi,shimaa64.efi} shim-fedora/
    cp "${_SHIMAA64}/boot/efi/EFI/fedora/shimaa64.efi" shim-fedora/BOOTAA64.efi
    # cleanup
    echo "Cleanup directories ${_SHIM} ${_SHIM32} ${_SHIMAA64}..."
    rm -r "${_SHIM}" "${_SHIM32}" "${_SHIMAA64}"
}

# GRUB standalone setup
### build grubXXX with all modules: http://bugs.archlinux.org/task/71382
### See also: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
### RISC64: https://fedoraproject.org/wiki/Architectures/RISC-V/GRUB2
_prepare_uefi_X64() {
    echo "Preparing X64 Grub..."
    grub-mkstandalone -d /usr/lib/grub/x86_64-efi -O x86_64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="ter-u16n" --locales="" --themes="" -o grub-efi/grubx64.efi "boot/grub/grub.cfg=${_GRUB_ISO}"
}

_prepare_uefi_IA32() {
    echo "Preparing IA32 Grub..."
    grub-mkstandalone -d /usr/lib/grub/i386-efi -O i386-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="ter-u16n" --locales="" --themes="" -o grub-efi/grubia32.efi "boot/grub/grub.cfg=${_GRUB_ISO}"
}

_prepare_uefi_AA64() {
    echo "Installing grub package..."
    ${_NSPAWN} "${1}" pacman -Sy grub --noconfirm
    cp ${_GRUB_ISO} "${1}"/archboot-iso-grub.cfg
    echo "Preparing AA64 Grub..."
    ${_NSPAWN} "${1}" grub-mkstandalone -d /usr/lib/grub/arm64-efi -O arm64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="ter-u16n" --locales="" --themes="" -o /grubaa64.efi "boot/grub/grub.cfg=/archboot-iso-grub.cfg"
    mv "${1}"/grubaa64.efi grub-efi/
}

_prepare_uefi_RISCV64() {
    echo "Installing grub package..."
   ${_NSPAWN} "${1}" pacman -Sy grub --noconfirm
    cp ${_GRUB_ISO} "${1}"/archboot-iso-grub.cfg
    echo "Preparing RISCV64 Grub..."
   ${_NSPAWN} "${1}" grub-mkstandalone -d /usr/lib/grub/riscv64-efi -O riscv64-efi --sbat=/usr/share/grub/sbat.csv --compress=xz --modules="boot cat configfile echo f2fs fat font iso9660 linux loadenv loopback minicmd normal part_apple part_gpt part_msdos regexp search search_fs_file search_fs_uuid search_label serial sleep" --fonts="ter-u16n" --locales="" --themes="" -o /BOOTRISCV64.efi "boot/grub/grub.cfg=/archboot-iso-grub.cfg"
    mv "${1}"/BOOTRISCV64.efi grub-efi/
    cp grub-efi/BOOTRISCV64.efi grub-efi/grubriscv64.efi
}

_upload_efi_files() {
    # sign files
    echo "Sign files and upload..."
    #shellcheck disable=SC2086
    cd ${1}/ || exit 1
    chmod 644 ./*
    chown "${_USER}:${_GROUP}" ./*
    for i in *.efi; do
        #shellcheck disable=SC2086
        if [[ -f "${i}" ]]; then
            sudo -u "${_USER}" gpg ${_GPG} "${i}" || exit 1
        fi
    done
    sudo -u "${_USER}" "${_RSYNC}" ./* "${_SERVER}:.${_ARCH_SERVERDIR}/" || exit 1
    cd ..
}

_cleanup() {
echo "Removing ${1} directory."
rm -r "${1}"
echo "Finished ${1}."
}
# vim: set ft=sh ts=4 sw=4 et:
