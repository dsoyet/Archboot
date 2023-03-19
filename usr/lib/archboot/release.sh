#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)"
_AMD_UCODE="boot/amd-ucode.img"
_INTEL_UCODE="boot/intel-ucode.img"
_INITRAMFS="boot/initramfs-${_ARCH}.img"
_INITRAMFS_LATEST="boot/initramfs-latest-${_ARCH}.img"
_INITRAMFS_LOCAL="boot/initramfs-local-${_ARCH}.img"
if [[ "${_ARCH}" == "aarch64" ]]; then
    _KERNEL="boot/Image-${_ARCH}.gz"
    _KERNEL_ARCHBOOT="boot/Image-archboot-${_ARCH}.gz"
else
    _KERNEL="boot/vmlinuz-${_ARCH}"
    _KERNEL_ARCHBOOT="boot/vmlinuz-archboot-${_ARCH}"
fi
_PRESET_LATEST="${_ARCH}-latest"
_PRESET_LOCAL="${_ARCH}-local"
_W_DIR="$(mktemp -u archboot-release.XXX)"

_usage () {
    echo "CREATE ARCHBOOT RELEASE IMAGE"
    echo "-----------------------------"
    echo "Usage: ${_BASENAME} <directory> <server>"
    echo "This will create an archboot release image in <directory>."
    echo "You can specify a certain <server> with an archboot repository."
    exit 0
}

_create_iso() {
    mkdir -p "${1}"
    cd "${1}" || exit 1
    # create container
    archboot-"${_ARCH}"-create-container.sh "${_W_DIR}" -cc --install-source="${2}" || exit 1
    _create_archboot_db "${_W_DIR}"/var/cache/pacman/pkg
    # riscv64 does not support kexec at the moment
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
        # removing not working lvm2 from latest image
        echo "Removing lvm2 from container ${_W_DIR}..."
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm &>/dev/null
        # generate latest tarball in container
        echo "Generating local ISO..."
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_ARCH}" || exit 1
        rm -rf "${_W_DIR}"/var/cache/pacman/pkg/*
        echo "Generating latest ISO..."
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_ARCH}" || exit 1
        echo "Installing lvm2 to container ${_W_DIR}..."
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm &>/dev/null
    fi
    echo "Generating normal ISO..."
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_ARCH}"  || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>/dev/null
    mv "${_W_DIR}"/*.img ./ &>/dev/null
    # create boot directory with ramdisks
    echo "Creating boot directory..."
    mkdir -p boot/
    if [[ "${_ARCH}" == "riscv64" ]]; then
        for i in *.img; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_KERNEL}" ./"${_KERNEL_ARCHBOOT}"
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS}"
            elif echo "${i}" | grep -q latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS_LATEST}"
            elif echo "${i}" | grep -q local; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS_LOCAL}"
            fi
        done
    else
        for i in *.iso; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                isoinfo -R -i "${i}" -x /efi.img 2>/dev/null > efi.img
                mcopy -m -i efi.img ::/"${_AMD_UCODE}" ./"${_AMD_UCODE}"
                [[ "${_ARCH}" == "aarch64" ]] || mcopy -m -i efi.img ::/"${_INTEL_UCODE}" ./"${_INTEL_UCODE}"
                mcopy -m -i efi.img ::/"${_INITRAMFS}" ./"${_INITRAMFS}"
                mcopy -m -i efi.img ::/"${_KERNEL}" ./"${_KERNEL_ARCHBOOT}"
            elif echo "${i}" | grep -q latest; then
                isoinfo -R -i "${i}" -x /efi.img 2>/dev/null > efi.img
                mcopy -m -i efi.img ::/"${_INITRAMFS}" ./"${_INITRAMFS_LATEST}"
            elif echo "${i}" | grep -q local; then
                isoinfo -R -i "${i}" -x /efi.img 2>/dev/null > efi.img
                mcopy -m -i efi.img ::/"${_INITRAMFS}" ./"${_INITRAMFS_LOCAL}"
            fi
            rm efi.img
        done
        echo "Generating Unified Kernel Images..."
        # create unified kernel image UKI, code adapted from wiki
        # https://wiki.archlinux.org/title/Unified_kernel_image
        _SPLASH="/usr/share/archboot/uki/archboot-background.bmp"
        _OSREL="/usr/share/archboot/base/etc/os-release"
        # add AMD ucode license
        mkdir -p boot/licenses/amd-ucode
        cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
        _CMDLINE="boot/cmdline.txt"
        if [[ "${_ARCH}" == "x86_64" ]]; then
            # add INTEL ucode license
            mkdir -p boot/licenses/intel-ucode
            cp /usr/share/licenses/intel-ucode/* boot/licenses/intel-ucode/
            _EFISTUB="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"
            echo "console=ttyS0,115200 console=tty0 audit=0" > ${_CMDLINE}
            _UCODE="${_INTEL_UCODE} ${_AMD_UCODE}"
        fi
        if [[ "${_ARCH}" == "aarch64" ]]; then
            echo "nr_cpus=1 console=ttyAMA0,115200 console=tty0 loglevel=4 audit=0" > ${_CMDLINE}
            _EFISTUB="/usr/lib/systemd/boot/efi/linuxaa64.efi.stub"
            _UCODE="${_AMD_UCODE}"
        fi
        rm -r "${_W_DIR:?}"/boot
        mv boot "${_W_DIR}"
        for initramfs in ${_INITRAMFS} ${_INITRAMFS_LATEST} ${_INITRAMFS_LOCAL}; do
            [[ "${initramfs}" == "${_INITRAMFS}" ]] && _UKI="boot/archboot-${_ARCH}.efi"
            [[ "${initramfs}" == "${_INITRAMFS_LATEST}" ]] && _UKI="boot/archboot-latest-${_ARCH}.efi"
            [[ "${initramfs}" == "${_INITRAMFS_LOCAL}" ]] && _UKI="boot/archboot-local-${_ARCH}.efi"
            #shellcheck disable=SC2086
            ${_NSPAWN} "${_W_DIR}" /usr/lib/systemd/ukify ${_KERNEL_ARCHBOOT} \
                ${_UCODE} ${initramfs} --cmdline @${_CMDLINE} --splash ${_SPLASH} \
                --os-release @${_OSREL} --stub ${_EFISTUB} --output ${_UKI} &>/dev/null || exit 1
        done
        # fix permission and timestamp
        mv "${_W_DIR}"/boot ./
        rm "${_CMDLINE}"
        chmod 644 boot/*.efi
        touch boot/*.efi
    fi
    # create Release.txt with included main archlinux packages
    echo "Generating Release.txt..."
    (echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM";\
    echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>";\
    echo "Homepage: https://bit.ly/archboot";\
    echo "Architecture: ${_ARCH}";\
    echo "RAM requirement to boot: 800M or greater";\
    echo "Archboot:$(${_NSPAWN} "${_W_DIR}" pacman -Qi "${_ARCHBOOT}" | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub:$(${_NSPAWN} "${_W_DIR}" pacman -Qi grub | grep Version | cut -d ":" -f3 | sed -e "s/\r//g")";\
    echo "Kernel:$(${_NSPAWN} "${_W_DIR}" pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Pacman:$(${_NSPAWN} "${_W_DIR}" pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Systemd:$(${_NSPAWN} "${_W_DIR}" pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")") >>Release.txt
    # removing container
    echo "Removing container ${_W_DIR}..."
    rm -r "${_W_DIR}"
    # create sha256sums
    echo "Generating sha256sum..."
    for i in *; do
        if [[ -f "${i}" ]]; then
            cksum -a sha256 "${i}" >> sha256sum.txt
        fi
    done
    for i in boot/*; do
        if [[ -f "${i}" ]]; then
            cksum -a sha256 "${i}" >> sha256sum.txt
        fi
    done
}
# vim: set ft=sh ts=4 sw=4 et:
