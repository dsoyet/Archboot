#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults

_usage () {
    echo "CREATE ARCHBOOT CONTAINER"
    echo "-------------------------"
    echo "This will create an archboot container for an archboot image."
    echo ""
    echo " -cc    Cleanup container eg. removing manpages, includes..."
    echo " -cp    Cleanup container package cache"
    echo " -install-source=<server>    add package server with archboot repository"
    echo ""
    echo "usage: ${_BASENAME} <directory> <options>"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -cc|--cc) _CLEANUP_CONTAINER="1" ;;
            -cp|--cp) _CLEANUP_CACHE="1" ;;
            -install-source=*|--install-source=*) _INSTALL_SOURCE="$(echo "${1}" | awk -F= '{print $2;}')" ;;
        esac
        shift
    done
}

_clean_cache() {
    if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
        echo "Cleaning pacman cache in ${1}..."
        rm -r "${1}${_CACHEDIR}"
    fi
    if grep -qw 'archboot' /etc/hostname; then
        echo "Cleaning archboot ${_CACHEDIR}..."
        for i in "${1}${_CACHEDIR}"/*; do
            [[ "${i}" == "${1}${_CACHEDIR}/archboot.db" ]] || rm -f "${_CACHEDIR}"/"$(basename "${i}")"
        done
    fi
}

_pacman_chroot() {
    if ! [[ -f ${3} && -f ${3}.sig ]]; then
        echo "Downloading ${3}..."
        wget "${2}"/"${3}"{,.sig} &>/dev/null
    else
        echo "Using local ${3}..."
    fi
    echo "Verifying ${3}..."
    gpg --verify "${3}.sig" &>/dev/null || exit 1
    bsdtar -C "${1}" -xf "${3}"
    if [[ -f "${3}" && -f "${3}".sig ]]; then
        echo "Removing installation tarball ${3}..."
        rm "${3}"{,.sig}
    fi
    echo "Updating container to latest packages..."
    ${_NSPAWN} "${1}" pacman -Syu --noconfirm &>/dev/null
}

# clean container from not needed files
_clean_container() {
    if [[ "${_CLEANUP_CONTAINER}" ==  "1" ]]; then
        echo "Cleaning container, delete not needed files from ${1}..."
        rm -r "${1}"/usr/include
        rm -r "${1}"/usr/share/{aclocal,applications,audit,awk,common-lisp,emacs,et,fish,gdb,gettext,gettext-[0-9]*,glib-[0-9]*,gnupg,gtk-doc,iana-etc,icons,icu,keyutils,libalpm,libgpg-error,makepkg-template,misc,mkinitcpio,pixmaps,pkgconfig,screen,smartmontools,ss,tabset,vala,xml,man,doc,info,xtables}
        rm -r "${1}"/usr/lib/{audit,awk,binfmt.d,cmake,dracut,e2fsprogs,engines-[0-9]*,environment.d,gawk,getconf,gettext,girepository-[0-9]*,glib-[0-9]*,gnupg,gssproxy,icu,krb5,ldscripts,libnl,pkgconfig,sasl2,siconv,tar,xfsprogs,xtables}
        # locale cleaning
        find "${1}"/usr/share/locale/ -mindepth 2 ! -path '*/be/*' ! -path '*/bg/*' ! -path '*/cs/*' ! -path '*/da/*' ! -path '*/de/*' \
        ! -path '*/en/*' ! -path '*/el/*' ! -path '*/es/*' ! -path '*/fi/*' ! -path '*/fr/*' ! -path '*/hu/*' ! -path '*/it/*' \
        ! -path '*/lt/*' ! -path '*/lv/*' ! -path '*/mk/*' ! -path '*/nl/*' ! -path '*/nn/*' ! -path '*/pl/*' ! -path '*/pt/*' \
        ! -path '*/ro/*' ! -path '*/ru/*' ! -path '*/sk/*' ! -path '*/sr/*' ! -path '*/sv/*' ! -path '*/uk/*' -delete &>/dev/null
        find "${1}"/usr/share/i18n/charmaps ! -name 'UTF-8.gz' -delete &>/dev/null
    fi
}

# removing mkinitcpio hooks to speed up process, removing not needed initramdisks
_clean_mkinitcpio() {
    echo "Cleaning mkinitcpio from ${1}..."
    [[ -e "${1}/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook" ]] && rm "${1}/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook"
    [[ -e "${1}/usr/share/libalpm/hooks/90-mkinitcpio-install.hook" ]] && rm "${1}/usr/share/libalpm/hooks/90-mkinitcpio-install.hook"
    [[ -e "${1}/boot/initramfs-linux.img" ]] && rm "${1}/boot/initramfs-linux.img"
    [[ -e "${1}/boot/initramfs-linux-fallback.img" ]] && rm "${1}/boot/initramfs-linux-fallback.img"
}

_prepare_pacman() {
    # prepare pacman dirs
    echo "Creating directories in ${1}..."
    mkdir -p "${1}/var/lib/pacman"
    mkdir -p "${1}/${_CACHEDIR}"
    [[ -e "${1}/proc" ]] || mkdir -m 555 "${1}/proc"
    [[ -e "${1}/sys" ]] || mkdir -m 555 "${1}/sys"
    [[ -e "${1}/dev" ]] || mkdir -m 755 "${1}/dev"
    # mount special filesystems to ${1}
    echo "Mounting special filesystems in ${1}..."
    mount proc "${1}/proc" -t proc -o nosuid,noexec,nodev
    mount sys "${1}/sys" -t sysfs -o nosuid,noexec,nodev,ro
    mount udev "${1}/dev" -t devtmpfs -o mode=0755,nosuid
    mount devpts "${1}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm "${1}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    echo "Removing archboot repository sync db..."
    rm -f /var/lib/pacman/sync/archboot.db
    echo "Updating Arch Linux keyring..."
    #shellcheck disable=SC2086
    pacman -Sy --config ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} &>/dev/null
}

#shellcheck disable=SC2120
_create_pacman_conf() {
    if [[ -z "${_INSTALL_SOURCE}" ]]; then
        echo "Using default pacman.conf..."
        [[ "${2}" == "use_binfmt" ]] && _PACMAN_CONF="${1}${_PACMAN_CONF}"
        if ! grep -qw "\[archboot\]" "${_PACMAN_CONF}"; then
            echo "Adding archboot repository to ${_PACMAN_CONF}..."
            echo "[archboot]" >> "${_PACMAN_CONF}"
            echo "Server = https://archboot.com/pkg" >> "${_PACMAN_CONF}"
        fi
        #shellcheck disable=SC2001
        [[ "${2}" == "use_binfmt" ]] && _PACMAN_CONF="$(echo "${_PACMAN_CONF}" | sed -e "s#^${1}##g")"
    else
        echo "Using custom pacman.conf..."
        _PACMAN_CONF="$(mktemp "${1}"/pacman.conf.XXX)"
        #shellcheck disable=SC2129
        echo "[options]" >> "${_PACMAN_CONF}"
        echo "Architecture = auto" >> "${_PACMAN_CONF}"
        echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
        echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
        echo "ParallelDownloads = 5" >> "${_PACMAN_CONF}"
        echo "Color" >> "${_PACMAN_CONF}"
        echo "[archboot]" >> "${_PACMAN_CONF}"
        echo "Server = ${_INSTALL_SOURCE}" >> "${_PACMAN_CONF}"
        [[ "${2}" == "use_binfmt" ]] && _PACMAN_CONF="$(basename "${_PACMAN_CONF}")"
    fi
}

_change_pacman_conf() {
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
    sed -i -e 's:^#Color:Color:g' "${1}"/etc/pacman.conf
}

# umount special filesystems
_umount_special() {
    echo "Unmounting special filesystems in ${1}..."
    umount -R "${1}/proc"
    umount -R "${1}/sys"
    umount -R "${1}/dev"
}

_install_base_packages() {
    if [[ "${2}" == "use_binfmt" ]]; then
        echo "Downloading ${_PACKAGES} ${_KEYRING} to ${1}..."
        #shellcheck disable=SC2086
        ${_PACMAN} -Syw ${_PACKAGES} ${_KEYRING} ${_PACMAN_DEFAULTS} ${_PACMAN_DB} &>/dev/null || exit 1
    fi
    echo "Installing ${_PACKAGES} ${_KEYRING} to ${1}..."
    #shellcheck disable=SC2086
    ${_PACMAN} -Sy ${_PACKAGES} ${_KEYRING} ${_PACMAN_DEFAULTS} &>/dev/null || exit 1
}

_install_archboot() {
    if [[ "${2}" == "use_binfmt" ]]; then
        _pacman_key "${1}"
    else
        _pacman_key_system
    fi
    echo "Installing ${_ARCHBOOT} ${_MAN_INFO_PACKAGES} to ${1}..."
    #shellcheck disable=SC2086
    ${_PACMAN} -Sy ${_ARCHBOOT} ${_MAN_INFO_PACKAGES} ${_PACMAN_DEFAULTS} &>/dev/null || exit 1
    # cleanup
    if ! [[ "${2}"  == "use_binfmt" ]]; then
        rm -r "${1}"/blankdb
        echo "Removing archboot repository sync db..."
        rm /var/lib/pacman/sync/archboot.db
    fi
}

#_install_custom_grub() {
#        [[ -e /var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst ]] && \
#         cp "/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst" \
#         "${1}/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst"
#        [[ -e /var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig ]] && \
#         cp "/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig" \
#         "${1}/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig"
#}

_copy_mirrorlist_and_pacman_conf() {
    # copy local mirrorlist to container
    echo "Creating pacman config and mirrorlist in container..."
    cp "/etc/pacman.d/mirrorlist" "${1}/etc/pacman.d/mirrorlist"
    # only copy from archboot pacman.conf, else use default file
    grep -qw 'archboot' /etc/hostname && cp /etc/pacman.conf "${1}"/etc/pacman.conf
}

_copy_archboot_defaults() {
    echo "Copying archboot defaults to container..."
    cp /etc/archboot/defaults "${1}"/etc/archboot/defaults
}

_reproducibility() {
    echo "Reproducibility changes..."
    sed -i -e '/INSTALLDATE/{n;s/.*/0/}' "${1}"/var/lib/pacman/local/*/desc
    rm "${1}"/var/cache/ldconfig/aux-cache
    rm "${1}"/etc/ssl/certs/java/cacerts
}

_set_hostname() {
    echo "Setting hostname to archboot..."
    echo 'archboot' > "${1}/etc/hostname"
}
# vim: set ft=sh ts=4 sw=4 et:
