#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_LOCAL_DB="/var/cache/pacman/pkg/archboot.db"
_RUNNING_ARCH="$(uname -m)"
_KERNELPKG="linux"
_NO_LOG="/dev/null"
# use the first VT not dedicated to a running console
# don't use _DESTDIR=/mnt because it's intended to mount other things there!
# check first if bootet in archboot
# don't ask for source and network on booted system
if grep -qw '^archboot' /etc/hostname; then
    _DESTDIR="/install"
    _NSPAWN="systemd-nspawn -q -D ${_DESTDIR}"
else
    _DESTDIR="/"
    _NSPAWN=""
fi
# name of the kernel image
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="vmlinuz-${_KERNELPKG}"
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _VMLINUZ="Image.gz"
    #shellcheck disable=SC2034
    _VMLINUZ_EFISTUB="Image"
fi
# abstract the common pacman args
_PACMAN="pacman --root ${_DESTDIR} --cachedir=${_DESTDIR}/var/cache/pacman/pkg --noconfirm --noprogressbar"
_MIRRORLIST="/etc/pacman.d/mirrorlist"

# $1: percentage
# $2: message
_progress() {
cat <<EOF
XXX
${1}
${2}
XXX
EOF
}

# $1: start percentage
# $2: end percentage
# $3: message
# $4: sleep time
_progress_wait() {
    _COUNT=${1}
    while [[ -e "${_W_DIR}/.archboot" || -e /.archboot ]]; do
        if [[ "${_COUNT}" -lt "${2}" ]]; then
            _progress "${_COUNT}" "${3}"
        fi
        if [[ "${_COUNT}" -gt "${2}" ]]; then
            _progress "${2}"  "${3}"
        fi
        # abort after 15 minutes
        if [[ "${_COUNT}" -gt 150 ]]; then
            exit 1
        fi
        _COUNT="$((_COUNT+1))"
        sleep "${4}"
    done
}

_linux_firmware() {
    _PACKAGES="${_PACKAGES//\ linux-firmware\ / }"
    #shellcheck disable=SC2013
    for i in $(cut -d ' ' -f1</proc/modules); do
        if modinfo "${i}" | grep -qw 'firmware:'; then
            _PACKAGES="${_PACKAGES} linux-firmware"
            break
        fi
    done
}

_marvell_firmware() {
    _MARVELL=""
    _PACKAGES="${_PACKAGES//\ linux-firmware-marvell\ / }"
    for i in $(find /lib/modules/"$(uname -r)" | grep -w wireless | grep -w marvell); do
        [[ -f $i ]] && _MARVELL="${_MARVELL} $(basename "${i}" | sed -e 's#\..*$##g')"
    done
    # check marvell modules if already loaded
    for i in ${_MARVELL}; do
        if lsmod | grep -qw "${i}"; then
            _PACKAGES="${_PACKAGES} linux-firmware-marvell"
            break
        fi
    done
}

# prepares target system as a chroot
_chroot_mount()
{
    if grep -qw '^archboot' /etc/hostname; then
        [[ -e "${_DESTDIR}/proc" ]] || mkdir -m 555 "${_DESTDIR}/proc"
        [[ -e "${_DESTDIR}/sys" ]] || mkdir -m 555 "${_DESTDIR}/sys"
        [[ -e "${_DESTDIR}/dev" ]] || mkdir -m 755 "${_DESTDIR}/dev"
        mount proc "${_DESTDIR}/proc" -t proc -o nosuid,noexec,nodev
        mount sys "${_DESTDIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
        mount udev "${_DESTDIR}/dev" -t devtmpfs -o mode=0755,nosuid
        mount devpts "${_DESTDIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
        mount shm "${_DESTDIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    fi
}

# tears down chroot in target system
_chroot_umount()
{
    if grep -qw '^archboot' /etc/hostname; then
        umount -R "${_DESTDIR}/proc"
        umount -R "${_DESTDIR}/sys"
        umount -R "${_DESTDIR}/dev"
    fi
}

_local_pacman_conf() {
    _PACMAN_CONF="$(mktemp /tmp/pacman.conf.XXX)"
    #shellcheck disable=SC2129
    echo "[options]" >> "${_PACMAN_CONF}"
    echo "Architecture = auto" >> "${_PACMAN_CONF}"
    echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
    echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
    echo "[archboot]" >> "${_PACMAN_CONF}"
    echo "Server = file:///var/cache/pacman/pkg" >> "${_PACMAN_CONF}"
    _PACMAN_CONF="--config ${_PACMAN_CONF}"
    _PACMAN="pacman --root ${_DESTDIR} ${_PACMAN_CONF} --cachedir=${_DESTDIR}/var/cache/pacman/pkg --noconfirm --noprogressbar"
}

_auto_packages() {
    # Add filesystem packages
    if ${_LSBLK} FSTYPE | grep -q btrfs; then
        ! echo "${_PACKAGES}" | grep -qw btrfs-progs && _PACKAGES="${_PACKAGES} btrfs-progs"
    fi
    if ${_LSBLK} FSTYPE | grep -q nilfs2; then
        ! echo "${_PACKAGES}" | grep -qw nilfs-utils && _PACKAGES="${_PACKAGES} nilfs-utils"
    fi
    if ${_LSBLK} FSTYPE | grep -q ext; then
        ! echo "${_PACKAGES}" | grep -qw e2fsprogs && _PACKAGES="${_PACKAGES} e2fsprogs"
    fi
    if ${_LSBLK} FSTYPE | grep -q xfs; then
        ! echo "${_PACKAGES}" | grep -qw xfsprogs && _PACKAGES="${_PACKAGES} xfsprogs"
    fi
    if ${_LSBLK} FSTYPE | grep -q jfs; then
        ! echo "${_PACKAGES}" | grep -qw jfsutils && _PACKAGES="${_PACKAGES} jfsutils"
    fi
    if ${_LSBLK} FSTYPE | grep -q f2fs; then
        ! echo "${_PACKAGES}" | grep -qw f2fs-tools && _PACKAGES="${_PACKAGES} f2fs-tools"
    fi
    if ${_LSBLK} FSTYPE | grep -q vfat; then
        ! echo "${_PACKAGES}" | grep -qw dosfstools && _PACKAGES="${_PACKAGES} dosfstools"
    fi
    # Add packages for complex blockdevices
    if ${_LSBLK} FSTYPE | grep -qw 'linux_raid_member'; then
        ! echo "${_PACKAGES}" | grep -qw mdadm && _PACKAGES="${_PACKAGES} mdadm"
    fi
    if ${_LSBLK} FSTYPE | grep -qw 'LVM2_member'; then
        ! echo "${_PACKAGES}" | grep -qw lvm2 && _PACKAGES="${_PACKAGES} lvm2"
    fi
    if ${_LSBLK} FSTYPE | grep -qw 'crypto_LUKS'; then
        ! echo "${_PACKAGES}" | grep -qw cryptsetup && _PACKAGES="${_PACKAGES} cryptsetup"
    fi
    #shellcheck disable=SC2010
    # Add iwd, if wlan is detected
    if ls /sys/class/net | grep -q wlan; then
        ! echo "${_PACKAGES}" | grep -qw iwd && _PACKAGES="${_PACKAGES} iwd"
    fi
    # Add broadcom-wl, if module is detected
    if lsmod | grep -qw wl; then
        ! echo "${_PACKAGES}" | grep -qw broadcom-wl && _PACKAGES="${_PACKAGES} broadcom-wl"
    fi
    grep -q '^FONT=ter' /etc/vconsole.conf && _PACKAGES="${_PACKAGES} terminus-font"
    # only add firmware if already used
    _linux_firmware
    _marvell_firmware
}

# /etc/locale.gen
# enable at least C.UTF-8 if nothing was changed, else weird things happen on reboot!
_locale_gen() {
    ${_NSPAWN} locale-gen &>"${_NO_LOG}"
    [[ -e /.archboot ]] && rm /.archboot
}
# vim: set ft=sh ts=4 sw=4 et:
