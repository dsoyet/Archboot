#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_D_SCRIPTS=""
_L_COMPLETE=""
_L_INSTALL_COMPLETE=""
_G_RELEASE=""
_CONFIG="/etc/archboot/${_RUNNING_ARCH}-update_installer.conf"
_W_DIR="/archboot"
_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master"
_BIN="/usr/bin"
_ETC="/etc/archboot"
_LIB="/usr/lib/archboot"
_RAM="/sysroot"
_INITRD="initrd.img"
_INST="/${_LIB}/installer"
_HELP="/${_LIB}/installer/help"
_RUN="/${_LIB}/run"
_UPDATE="/${_LIB}/update"
_LOG="/dev/tty7"
_NO_LOG="/dev/null"
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="vmlinuz-linux"
[[ "${_RUNNING_ARCH}" == "aarch64" ]] && _VMLINUZ="Image"

_graphic_options() {
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo -e " \e[1m-gnome\e[m           Launch Gnome desktop with VNC sharing enabled."
        echo -e " \e[1m-gnome-wayland\e[m   Launch Gnome desktop with Wayland backend."
        echo -e " \e[1m-plasma\e[m          Launch KDE Plasma desktop with VNC sharing enabled."
        echo -e " \e[1m-plasma-wayland\e[m  Launch KDE Plasma desktop with Wayland backend."
    fi
}

usage () {
    echo -e "\e[1mManage \e[36mArchboot\e[m\e[1m - Arch Linux Environment:\e[m"
    echo -e "\e[1m-----------------------------------------\e[m"
    echo -e " \e[1m-help\e[m            This message."
    if [[ ! -e "/var/cache/pacman/pkg/archboot.db" || -e "/usr/bin/setup" ]]; then
        echo -e " \e[1m-update\e[m          Update scripts: setup, quickinst, clock, vconsole and helpers."
    fi
    # latest image
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2000000 && ! -e "/.full_system" && ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        echo -e " \e[1m-full-system\e[m     Switch to full Arch Linux system."
    # local image
    elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 && ! -e "/.full_system" && -e "/var/cache/pacman/pkg/archboot.db" && -e "/usr/bin/setup" ]]; then
        echo -e " \e[1m-full-system\e[m     Switch to full Arch Linux system."
    fi
    echo -e ""
    if [[ -e "/usr/bin/setup" ]]; then
        # works only on latest image
        if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2400000 ]] ; then
                _graphic_options
            fi
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 1500000 ]]; then
                echo -e " \e[1m-sway\e[m            Launch Sway desktop with VNC sharing enabled."
                echo -e " \e[1m-xfce\e[m            Launch Xfce desktop with VNC sharing enabled."
                echo -e " \e[1m-custom-xorg\e[m     Install custom X environment."
               [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2400000 ]] && echo -e " \e[1m-custom-wayland\e[m  Install custom Wayland environment."
                echo ""
            fi
        fi
    fi
    if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]] || [[ -e "/var/cache/pacman/pkg/archboot.db" && ! -e "/usr/bin/setup" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 1970000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \e[1m-latest\e[m          Launch latest archboot environment (using kexec)."
            fi
        fi
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3271000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \e[1m-latest-install\e[m  Launch latest archboot environment with"
                echo -e "                  package cache (using kexec)."
            fi
        fi
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3216000 ]]; then
        echo -e " \e[1m-latest-image\e[m    Generate latest image files in /archboot directory."
    fi
    exit 0
}

_archboot_check() {
    if ! grep -qw "archboot" /etc/hostname; then
        echo "This script should only be run in booted archboot environment. Aborting..."
        exit 1
    fi
}

_clean_kernel_cache () {
    echo 3 > /proc/sys/vm/drop_caches
}

_download_latest() {
    # Download latest setup and quickinst script from git repository
    if [[ -n "${_D_SCRIPTS}" ]]; then
        _network_check
        echo -e "\e[1mStart:\e[m Downloading latest archboot from GIT master tree..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        # config
        echo -e "\e[1mStep 1/4:\e[m Downloading latest config..."
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        # helper binaries
        echo -e "\e[1mStep 2/4:\e[m Downloading latest scripts..."
        # main binaries
        BINS="quickinst setup vconsole clock launcher localize network pacsetup update copy-mountpoint rsync-backup restore-usbstick"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        BINS="binary-check.sh not-installed.sh secureboot-keys.sh mkkeys.sh hwsim.sh cpio,sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        HELP="guid-partition.txt guid.txt luks.txt lvm2.txt mbr-partition.txt md.txt"
        for i in ${HELP}; do
            [[ -e "${_HELP}/${i}" ]] && wget -q "${_SOURCE}${_HELP}/${i}?inline=false" -O "${_HELP}/${i}"
        done
        # main libs
        echo -e "\e[1mStep 3/4:\e[m Downloading latest script libs..."
        LIBS="basic-common.sh common.sh container.sh release.sh iso.sh login.sh cpio.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_LIB}/${i}?inline=false" -O "${_LIB}/${i}"
        done
        # update libs
        LIBS="update.sh xfce.sh gnome.sh gnome-wayland.sh plasma.sh plasma-wayland.sh sway.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_UPDATE}/${i}?inline=false" -O "${_UPDATE}/${i}"
        done
        # run libs
        LIBS="container.sh release.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_RUN}/${i}?inline=false" -O "${_RUN}/${i}"
        done
        # setup libs
        echo -e "\e[1mStep 4/4:\e[m Downloading latest setup libs..."
        LIBS="autoconfiguration.sh quicksetup.sh base.sh blockdevices.sh bootloader.sh btrfs.sh common.sh \
                configuration.sh mountpoints.sh network.sh pacman.sh partition.sh storage.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_INST}/${i}?inline=false" -O "${_INST}/${i}"
        done
        echo -e "\e[1mFinished:\e[m Downloading scripts done."
        exit 0
    fi
}

_network_check() {
    if ! getent hosts www.google.com &>"${_NO_LOG}"; then
        echo -e "\e[91mAborting:\e[m"
        echo -e "Network not yet ready."
        echo -e "Please configure your network first."
        exit 1
    fi
}

_update_installer_check() {
    if [[ -f /.update ]]; then
        echo -e "\e[91mAborting:\e[m"
        echo "update is already running on other tty..."
        echo "If you are absolutly sure it's not running, you need to remove /.update"
        exit 1
    fi
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _network_check
    fi
}

_kill_w_dir() {
    if [[ -d "${_W_DIR}" ]]; then
        rm -r "${_W_DIR}"
    fi
}

_clean_archboot() {
    # remove everything not necessary
    rm -rf /usr/lib/firmware
    rm -rf /usr/lib/modules
    rm -rf /usr/lib/libstdc++*
    _SHARE_DIRS="bash-completion efitools fonts hwdata kbd licenses lshw nano nvim pacman systemd tc zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
    if [[ -e /etc/systemd/system/pacman-init.service ]]; then
        systemctl stop pacman-init.service
    fi
}

_create_container() {
    # create container without package cache
    if [[ -n "${_L_COMPLETE}" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >"${_LOG}" 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for local image
        # add the db too on reboot
        install -D -m644 /var/cache/pacman/pkg/archboot.db "${_W_DIR}"/var/cache/pacman/pkg/archboot.db
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///var/cache/pacman/pkg >"${_LOG}" 2>&1 || exit 1
        fi
        # needed for checks
        cp "${_W_DIR}"/var/cache/pacman/pkg/archboot.db /var/cache/pacman/pkg/archboot.db
    else
        #online mode
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >"${_LOG}" 2>&1 || exit 1
        fi
    fi
}

_kver_x86() {
    # get kernel version from installed kernel
    if [[ -f "${_RAM}/${_VMLINUZ}" ]]; then
        offset="$(od -An -j0x20E -dN2 "${_RAM}/${_VMLINUZ}")"
        read -r _HWKVER _ < <(dd if="${_RAM}/${_VMLINUZ}" bs=1 count=127 skip=$((offset + 0x200)) 2>"${_NO_LOG}")
    fi
}

_kver_generic() {
    # get kernel version from installed kernel
    if [[ -f "${_RAM}/${_VMLINUZ}" ]]; then
        reader="cat"
        # try if the image is gzip compressed
        bytes="$(od -An -t x2 -N2 "${_RAM}/${_VMLINUZ}" | tr -dc '[:alnum:]')"
        [[ $bytes == '8b1f' ]] && reader="zcat"
        read -r _ _ _HWKVER _ < <($reader "${_RAM}/${_VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi
}

_create_initramfs() {
    # https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' |
            sort -z |
            LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            zstd --rm -T0> ${_RAM}/${_INITRD} &
    sleep 2
    while pgrep -x zstd &>"${_NO_LOG}"; do
        _clean_kernel_cache
        sleep 1
    done
}

_ram_check() {
    while true; do
        # continue when 1 GB RAM is free
        [[ "$(grep -w MemAvailable /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "1000000" ]] && break
    done
}

_cleanup_install() {
    rm -rf /usr/share/{man,help,gir-[0-9]*,info,doc,gtk-doc,ibus,perl[0-9]*}
    rm -rf /usr/include
    rm -rf /usr/lib/libgo.*
}

_cleanup_cache() {
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(grep 'installed' /var/log/pacman.log | cut -d ' ' -f 4); do
        rm -rf /var/cache/pacman/pkg/"${i}"-[0-9]*
    done
}

_prepare_graphic() {
    _GRAPHIC="${1}"
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing firmware files..."
        rm -rf /usr/lib/firmware
        # fix libs first, then install packages from defaults
        _GRAPHIC="${_FIX_PACKAGES} ${1}"
    fi
    echo "Updating environment to latest packages (ignoring packages: ${_GRAPHIC_IGNORE})..."
    _IGNORE=""
    if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
        for i in ${_GRAPHIC_IGNORE}; do
            _IGNORE="${_IGNORE} --ignore ${i}"
        done
    fi
    #shellcheck disable=SC2086
    pacman -Syu ${_IGNORE} --noconfirm &>"${_NO_LOG}" || exit 1
    [[ ! -e "/.full_system" ]] && _cleanup_install
    # check for qxl module
    grep -q qxl /proc/modules && grep -q xorg "${_GRAPHIC}" && _GRAPHIC="${_GRAPHIC} xf86-video-qxl"
    echo "Running pacman to install packages: ${_GRAPHIC}..."
    for i in ${_GRAPHIC}; do
        #shellcheck disable=SC2086
        pacman -S ${i} --noconfirm &>"${_NO_LOG}" || exit 1
        [[ ! -e "/.full_system" ]] && _cleanup_install
        [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
        rm -f /var/log/pacman.log
    done
    # install firefox langpacks
    if [[ "${_STANDARD_BROWSER}" == "firefox" ]]; then
        _LANG="be bg cs da de el fi fr hu it lt lv mk nl nn pl ro ru sk sr uk"
        for i in ${_LANG}; do
            if grep -q "${i}" /etc/locale.conf; then
                pacman -S firefox-i18n-"${i}" --noconfirm &>"${_NO_LOG}" || exit 1
            fi
        done
        if grep -q en_US /etc/locale.conf; then
            pacman -S firefox-i18n-en-us --noconfirm &>"${_NO_LOG}" || exit 1
        elif grep -q es_ES /etc/locale.conf; then
            pacman -S firefox-i18n-es-es --noconfirm &>"${_NO_LOG}" || exit 1
        elif grep -q pt_PT /etc/locale.conf; then
            pacman -S firefox-i18n-pt-pt --noconfirm &>"${_NO_LOG}" || exit 1
        elif grep -q sv_SE /etc/locale.conf; then
            pacman -S firefox-i18n-sv-se --noconfirm &>"${_NO_LOG}" || exit 1
        fi
    fi
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing not used icons..."
        rm -rf /usr/share/icons/breeze-dark
        echo "Cleanup locale and i18n..."
        find /usr/share/locale/ -mindepth 2 ! -path '*/be/*' ! -path '*/bg/*' ! -path '*/cs/*' \
        ! -path '*/da/*' ! -path '*/de/*' ! -path '*/en/*' ! -path '*/el/*' ! -path '*/es/*' \
        ! -path '*/fi/*' ! -path '*/fr/*' ! -path '*/hu/*' ! -path '*/it/*' ! -path '*/lt/*' \
        ! -path '*/lv/*' ! -path '*/mk/*' ! -path '*/nl/*' ! -path '*/nn/*' ! -path '*/pl/*' \
        ! -path '*/pt/*' ! -path '*/ro/*' ! -path '*/ru/*' ! -path '*/sk/*' ! -path '*/sr/*' \
        ! -path '*/sv/*' ! -path '*/uk/*' -delete &>"${_NO_LOG}"
        find /usr/share/i18n/charmaps ! -name 'UTF-8.gz' -delete &>"${_NO_LOG}"
    fi
    systemd-sysusers >"${_LOG}" 2>&1
    systemd-tmpfiles --create >"${_LOG}" 2>&1
    # fixing dbus requirements
    systemctl reload dbus
    systemctl reload dbus-org.freedesktop.login1.service
}

_new_environment() {
    _update_installer_check
    touch /.update
    _kill_w_dir
    _STEPS="11"
    _S_APPEND="0"
    _S_EMPTY="  "
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _STEPS="7"
        _S_APPEND=""
        _S_EMPTY=""
    fi
    echo -e "\e[1mStep ${_S_APPEND}1/${_STEPS}:\e[m Waiting for gpg pacman keyring import to finish..."
    _gpg_check
    echo -e "\e[1mStep ${_S_APPEND}2/${_STEPS}:\e[m Removing not necessary files from /..."
    _clean_archboot
    _clean_kernel_cache
    echo -e "\e[1mStep ${_S_APPEND}3/${_STEPS}:\e[m Generating archboot container in ${_W_DIR}..."
    echo "${_S_EMPTY}          This will need some time..."
    _create_container || exit 1
    _clean_kernel_cache
    _ram_check
    mkdir ${_RAM}
    mount -t ramfs none ${_RAM}
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "\e[1mStep ${_S_APPEND}4/${_STEPS}:\e[m Skipping copying of kernel ${_VMLINUZ} to ${_RAM}/${_VMLINUZ}..."
    else
        echo -e "\e[1mStep ${_S_APPEND}4/${_STEPS}:\e[m Copying kernel ${_VMLINUZ} to ${_RAM}/${_VMLINUZ}..."
        # use ramfs to get immediate free space on file deletion
        mv "${_W_DIR}/boot/${_VMLINUZ}" ${_RAM}/ || exit 1
    fi
    [[ ${_RUNNING_ARCH} == "x86_64" ]] && _kver_x86
    [[ ${_RUNNING_ARCH} == "aarch64" || ${_RUNNING_ARCH} == "riscv64" ]] && _kver_generic
    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
    echo -e "\e[1mStep ${_S_APPEND}5/${_STEPS}:\e[m Collecting rootfs files in ${_W_DIR}..."
    echo "${_S_EMPTY}          This will need some time..."
    # write initramfs to "${_W_DIR}"/tmp
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount tmp;archboot-cpio.sh -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >"${_LOG}" 2>&1 || exit 1
    echo -e "\e[1mStep ${_S_APPEND}6/${_STEPS}:\e[m Cleanup ${_W_DIR}..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' -exec rm -rf {} \;
    _clean_kernel_cache
    _ram_check
    # local switch, don't kexec on local image
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "\e[1mStep ${_STEPS}/${_STEPS}:\e[m Switch root to ${_RAM}..."
        mv ${_W_DIR}/tmp/* /${_RAM}/
        # cleanup mkinitcpio directories and files
        rm -rf /sysroot/{hooks,install,kernel,new_root,sysroot,mkinitcpio.*} &>"${_NO_LOG}"
        rm -f /sysroot/{VERSION,config,buildconfig,init} &>"${_NO_LOG}"
        # https://www.freedesktop.org/software/systemd/man/bootup.html
        # enable systemd  initrd functionality
        touch /etc/initrd-release
        # fix /run/nouser issues
        systemctl stop systemd-user-sessions.service
        # avoid issues by taking down services in ordered way
        systemctl stop dbus-org.freedesktop.login1.service
        systemctl stop dbus.socket
        # prepare for initrd-switch-root
        systemctl start initrd-cleanup.service
        systemctl start initrd-switch-root.target
    fi
    _C_DIR="${_W_DIR}/tmp"
    echo -e "\e[1mStep ${_S_APPEND}7/${_STEPS}:\e[m Preserving Basic Setup values..."
    if [[ -e '/.localize' ]]; then
        cp /etc/{locale.gen,locale.conf} "${_C_DIR}"/etc
        cp /.localize "${_C_DIR}"/
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "locale-gen" &>"${_NO_LOG}"
    fi
    if [[ -e '/.vconsole' ]]; then
        cp /etc/vconsole.conf "${_C_DIR}"/etc
        cp /.vconsole "${_C_DIR}"/
        : >"${_C_DIR}"/.vconsole-run
    fi
    if [[ -e '/.clock' ]]; then
        cp -a /etc/{adjtime,localtime} "${_C_DIR}"/etc
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "systemctl enable systemd-timesyncd.service" &>"${_NO_LOG}"
        cp /.clock "${_C_DIR}"/
    fi
    if [[ -e '/.network' ]]; then
        cp -r /var/lib/iwd "${_C_DIR}"/var/lib
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "systemctl enable iwd" &>"${_NO_LOG}"
        cp /etc/systemd/network/* "${_C_DIR}"/etc/systemd/network/
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "systemctl enable systemd-networkd" &>"${_NO_LOG}"
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "systemctl enable systemd-resolved" &>"${_NO_LOG}"
        rm "${_C_DIR}"/etc/systemd/network/10-wired-auto-dhcp.network
        [[ -e '/etc/profile.d/proxy.sh' ]] && cp /etc/profile.d/proxy.sh "${_C_DIR}"/etc/profile.d/proxy.sh
        cp /.network "${_C_DIR}"/
    fi
    if [[ -e '/.pacsetup' ]]; then
        cp /etc/pacman.conf "${_C_DIR}"/etc
        cp /etc/pacman.d/mirrorlist "${_C_DIR}"/etc/pacman.d/
        cp -ar /etc/pacman.d/gnupg "${_C_DIR}"/etc/pacman.d
        cp /.pacsetup "${_C_DIR}"/
    fi
    echo -e "\e[1mStep ${_S_APPEND}8/${_STEPS}:\e[m Creating initramfs ${_RAM}/${_INITRD}..."
    echo "            This will need some time..."
    _create_initramfs
    echo -e "\e[1mStep ${_S_APPEND}9/${_STEPS}:\e[m Cleanup ${_W_DIR}..."
    cd /
    _kill_w_dir
    _clean_kernel_cache
    echo -e "\e[1mStep 10/${_STEPS}:\e[m Waiting for kernel to free RAM..."
    echo "            This will need some time..."
    # wait until enough memory is available!
    while true; do
        [[ "$(($(stat -c %s ${_RAM}/${_INITRD})*200/100000))" -lt "$(grep -w MemAvailable /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" ]] && break
        sleep 1
    done
    _MEM_MIN=""
    # only needed on aarch64
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
            _MEM_MIN="--mem-min=0xA0000000"
    fi
    echo -e "\e[1mStep ${_STEPS}/${_STEPS}:\e[m Running \e[1;92mkexec\e[m with \e[1mKEXEC_LOAD\e[m..."
    echo "            This will need some time..."
    kexec -c -f ${_MEM_MIN} ${_RAM}/"${_VMLINUZ}" --initrd="${_RAM}/${_INITRD}" --reuse-cmdline &
    sleep 0.1
    _clean_kernel_cache
    rm ${_RAM}/{"${_VMLINUZ}","${_INITRD}"}
    umount ${_RAM} &>"${_NO_LOG}"
    rm -r ${_RAM} &>"${_NO_LOG}"
    #shellcheck disable=SC2115
    rm -rf /usr/* &>"${_NO_LOG}"
    while true; do
        _clean_kernel_cache
        read -r -t 1
    done
}

_kernel_check() {
    _PATH="/usr/bin"
    _INSTALLED_KERNEL="$(${_PATH}/pacman -Qi linux | ${_PATH}/grep Version | ${_PATH}/cut -d ':' -f 2 | ${_PATH}/sed -e 's# ##g' -e 's#\.arch#-arch#g')"
    _RUNNING_KERNEL="$(${_PATH}/uname -r)"
    if ! [[ "${_INSTALLED_KERNEL}" == "${_RUNNING_KERNEL}" ]]; then
        echo -e "\e[93mWarning:\e[m"
        echo -e "Installed kernel does \e[1mnot\e[m match running kernel!"
        echo -e "Kernel module loading will \e[1mnot\e[m work."
        echo -e "Use \e[1m--latest\e[m options to get a matching kernel first."
    fi
}

_full_system() {
    if [[ -e "/.full_system" ]]; then
        echo -e "\e[1mFull Arch Linux system already setup.\e[m"
        exit 0
    fi
    echo -e "\e[1mInitializing full Arch Linux system...\e[m"
    echo -e "\e[1mStep 1/3:\e[m Reinstalling packages and adding info/man-pages..."
    echo "          This will need some time..."
    pacman -Sy >"${_LOG}" 2>&1 || exit 1
    pacman -Qqn | pacman -S --noconfirm man-db man-pages texinfo - >"${_LOG}" 2>&1 || exit 1
    echo -e "\e[1mStep 2/3:\e[m Checking kernel version..."
    _kernel_check
    echo -e "\e[1mStep 3/3:\e[m Trigger kernel module loading..."
    udevadm trigger --action=add --type=subsystems
    udevadm trigger --action=add --type=devices
    udevadm settle
    echo -e "\e[1mFull Arch Linux system is ready now.\e[m"
    touch /.full_system
}

_new_image() {
    _PRESET_LATEST="${_RUNNING_ARCH}-latest"
    _PRESET_LOCAL="${_RUNNING_ARCH}-local"
    _ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)"
    echo -e "\e[1mStep 1/2:\e[m Removing not necessary files from /..."
    _clean_archboot
    [[ -d var/cache/pacman/pkg ]] && rm -f /var/cache/pacman/pkg/*
    echo -e "\e[1mStep 2/2:\e[m Generating new iso files in ${_W_DIR} now..."
    echo "          This will need some time..."
    mkdir /archboot
    cd /archboot || exit 1
    _W_DIR="$(mktemp -u archboot-release.XXX)"
    # create container
    archboot-"${_RUNNING_ARCH}"-create-container.sh "${_W_DIR}" -cc > "${_LOG}" || exit 1
    _create_archboot_db "${_W_DIR}"/var/cache/pacman/pkg > "${_LOG}"
    # riscv64 does not support kexec at the moment
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
        # removing not working lvm2 from latest image
        echo "Removing lvm2 from container ${_W_DIR}..." > "${_LOG}"
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm &>"${_NO_LOG}"
        # generate latest tarball in container
        echo "Generating local ISO..." > "${_LOG}"
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
        rm -rf "${_W_DIR}"/var/cache/pacman/pkg/*
        _ram_check
        echo "Generating latest ISO..." > "${_LOG}"
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
        echo "Installing lvm2 to container ${_W_DIR}..." > "${_LOG}"
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm &>"${_NO_LOG}"
    fi
    echo "Generating normal ISO..." > "${_LOG}"
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_RUNNING_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>"${_NO_LOG}"
    mv "${_W_DIR}"/*.img ./ &>"${_NO_LOG}"
    rm -r "${_W_DIR}"
    echo -e "\e[1mFinished:\e[m New isofiles are located in /archboot"
}

_install_graphic () {
    [[ -e /var/cache/pacman/pkg/archboot.db ]] && touch /.graphic_installed
    echo -e "\e[1mInitializing desktop environment...\e[m"
    [[ -n "${_L_XFCE}" ]] && _install_xfce
    [[ -n "${_L_GNOME}" ]] && _install_gnome
    [[ -n "${_L_GNOME_WAYLAND}" ]] && _install_gnome_wayland
    [[ -n "${_L_PLASMA}" ]] && _install_plasma
    [[ -n "${_L_PLASMA_WAYLAND}" ]] && _install_plasma_wayland
    [[ -n "${_L_SWAY}" ]] && _install_sway
    # only start vnc on xorg environment
    echo -e "\e[1mStep 3/3:\e[m Setting up VNC and browser...\e[m"
    [[ -n "${_L_XFCE}" || -n "${_L_PLASMA}" || -n "${_L_GNOME}" ]] && _autostart_vnc
    command -v firefox &>"${_NO_LOG}"  && _firefox_flags
    command -v chromium &>"${_NO_LOG}" && _chromium_flags
    [[ -n "${_L_XFCE}" ]] && _start_xfce
    [[ -n "${_L_GNOME}" ]] && _start_gnome
    [[ -n "${_L_GNOME_WAYLAND}" ]] && _start_gnome_wayland
    [[ -n "${_L_PLASMA}" ]] && _start_plasma
    [[ -n "${_L_PLASMA_WAYLAND}" ]] && _start_plasma_wayland
    [[ -n "${_L_SWAY}" ]] && _start_sway
}

_hint_graphic_installed () {
    echo -e "\e[1;91mError: Graphical environment already installed...\e[m"
    echo -e "You are running in \e[1mOffline Mode\e[m with less than \e[1m4500 MB RAM\e[m, which only can launch \e[1mone\e[m environment."
    echo -e "Please relaunch your already used graphical environment from commandline."
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop..."
        _configure_gnome >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop already done..."
    fi
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop..."
        _configure_plasma >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop already done..."
    fi
}

_prepare_sway() {
    if ! [[ -e /usr/bin/sway ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing Sway desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring Sway desktop..."
        _configure_sway >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing Sway desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring Sway desktop already done..."
    fi
}

_configure_dialog() {
    echo "Configuring dialog..."
        cat <<EOF > /etc/dialogrc
border_color = (BLACK,WHITE,ON)
border2_color = (BLACK,WHITE,ON)
menubox_border_color = (BLACK,WHITE,ON)
menubox_border2_color = (BLACK,WHITE,ON)
EOF
}

_configure_gnome() {
    echo "Configuring Gnome..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal -- /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
    _configure_dialog
}

_configure_plasma() {
    echo "Configuring KDE..."
    sed -i -e "s#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,applications:${_STANDARD_BROWSER}.desktop,applications:gparted.desktop,applications:archboot.desktop</default>#g" /usr/share/plasma/plasmoids/org.kde.plasma.tasvconsoleanager/contents/config/main.xml
    echo "Replacing wallpaper..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure..."
    cat << EOF >/etc/xdg/menus/applications.menu
 <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<!-- Search the default locations -->
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Separator/>
		<Menuname>More</Menuname>
	</DefaultLayout>
	<Layout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Menuname>Applications</Menuname>
	</Layout>
	<Menu>
		<Name>Settingsmenu</Name>
		<Directory>kf5-settingsmenu.directory</Directory>
		<Include>
			<Category>Settings</Category>
		</Include>
	</Menu>
	<DefaultMergeDirs/>
	<Include>
	<Filename>archboot.desktop</Filename>
	<Filename>${_STANDARD_BROWSER}.desktop</Filename>
	<Filename>org.kde.dolphin.desktop</Filename>
	<Filename>gparted.desktop</Filename>
	<Filename>org.kde.konsole.desktop</Filename>
	</Include>
</Menu>
EOF
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=konsole -p colors=Linux -e /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_configure_sway() {
    echo "Configuring Sway..."
    echo "Configuring bemenu..."
    sed -i -e 's|^set $menu.*|set $menu j4-dmenu-desktop --dmenu=\x27bemenu -i --tf "#00ff00" --hf "#00ff00" --nf "#dcdccc" --fn "pango:Terminus 12" -H 30\x27 --no-generic --term="foot"|g'  /etc/sway/config
    echo "Configuring wallpaper..."
    sed -i -e 's|^output .*|output * bg /usr/share/archboot/grub/archboot-background.png fill|g' /etc/sway/config
    echo "Configuring foot..."
    if ! grep -q 'archboot colors' /etc/xdg/foot/foot.ini; then
cat <<EOF >> /etc/xdg/foot/foot.ini
# archboot colors
[colors]
background=000000
foreground=ffffff

## Normal/regular colors (color palette 0-7)
regular0=000000   # bright black
regular1=ff0000   # bright red
regular2=00ff00   # bright green
regular3=ffff00   # bright yellow
regular4=005fff   # bright blue
regular5=ff00ff   # bright magenta
regular6=00ffff   # bright cyan
regular7=ffffff   # bright white

## Bright colors (color palette 8-15)
bright0=000000   # bright black
bright1=ff0000   # bright red
bright2=00ff00   # bright green
bright3=ffff00   # bright yellow
bright4=005fff   # bright blue
bright5=ff00ff   # bright magenta
bright6=00ffff   # bright cyan
bright7=ffffff   # bright white

[main]
font=monospace:size=12
EOF

    fi
    echo "Autostarting setup..."
    grep -q 'exec foot' /etc/sway/config ||\
        echo "exec foot -- /usr/bin/setup" >> /etc/sway/config
    if ! grep -q firefox /etc/sway/config; then
        cat <<EOF >> /etc/sway/config
# from https://wiki.gentoo.org/wiki/Sway
# automatic floating
for_window [window_role = "pop-up"] floating enable
for_window [window_role = "bubble"] floating enable
for_window [window_role = "dialog"] floating enable
for_window [window_type = "dialog"] floating enable
for_window [window_role = "task_dialog"] floating enable
for_window [window_type = "menu"] floating enable
for_window [app_id = "floating"] floating enable
for_window [app_id = "floating_update"] floating enable, resize set width 1000px height 600px
for_window [class = "(?i)pinentry"] floating enable
for_window [title = "Administrator privileges required"] floating enable
# firefox tweaks
for_window [title = "About Mozilla Firefox"] floating enable
for_window [window_role = "About"] floating enable
for_window [app_id="firefox" title="Library"] floating enable, border pixel 1, sticky enable
for_window [title = "Firefox - Sharing Indicator"] kill
for_window [title = "Firefox — Sharing Indicator"] kill
EOF
    fi
    echo "Configuring desktop files..."
    cat << EOF > /usr/share/applications/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=foot -- /usr/bin/setup
Icon=system-software-install
EOF
    _HIDE_MENU="avahi-discover bssh bvnc org.codeberg.dnkl.foot-server org.codeberg.dnkl.footclient qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
    echo "Configuring waybar..."
    if ! grep -q 'exec waybar' /etc/sway/config; then
        # hide sway-bar
        sed -i '/position top/a mode invisible' /etc/sway/config
        # diable not usable plugins
        echo "exec waybar" >> /etc/sway/config
        sed -i -e 's#, "custom/media"##g' /etc/xdg/waybar/config
        sed -i -e 's#"mpd", "idle_inhibitor", "pulseaudio",##g' /etc/xdg/waybar/config
    fi
    _configure_dialog
    echo "Configuring wayvnc..."
     if ! grep -q wayvnc /etc/sway/config; then
        echo "address=0.0.0.0" > /etc/wayvnc
        echo "exec wayvnc -C /etc/wayvnc &" >> /etc/sway/config
    fi
}

_custom_wayland_xorg() {
    if [[ -n "${_CUSTOM_WAYLAND}" ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing custom wayland..."
        echo "          This will need some time..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND}" > "${_LOG}" 2>&1
    fi
    if [[ -n "${_CUSTOM_X}" ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing custom xorg..."
        echo "          This will need some time..."
        _prepare_graphic "${_XORG_PACKAGE} ${_CUSTOM_XORG}" > "${_LOG}" 2>&1
    fi
    echo -e "\e[1mStep 2/3:\e[m Starting avahi-daemon..."
    systemctl start avahi-daemon.service
    echo -e "\e[1mStep 3/3:\e[m Setting up browser...\e[m"
    which firefox &>"${_NO_LOG}"  && _firefox_flags
    which chromium &>"${_NO_LOG}" && _chromium_flags
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf..." >"${_LOG}"
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
archboot.com
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! grep -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
            echo "Adding firefox flags vendor.js..." >"${_LOG}"
            cat << EOF >> /usr/lib/firefox/browser/defaults/preferences/vendor.js
pref("browser.aboutwelcome.enabled", false, locked);
pref("browser.startup.homepage_override.once", false, locked);
pref("datareporting.policy.firstRunURL", "https://wiki.archlinux.org", locked);
pref("browser.startup.homepage", "https://archboot.com|https://wiki.archlinux.org", locked);
pref("browser.startup.firstrunSkipsHomepage"; true, locked);
pref("startup.homepage_welcome_url", "https://archboot.com", locked );
EOF
        fi
    fi
}

_autostart_vnc() {
    echo "Setting VNC password /etc/tigervnc/passwd to ${_VNC_PW}..." >"${_LOG}"
    echo "${_VNC_PW}" | vncpasswd -f > /etc/tigervnc/passwd
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Autostarting tigervnc..." >"${_LOG}"
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
}
# vim: set ft=sh ts=4 sw=4 et:
