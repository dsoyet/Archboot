#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>

_archboot_check() {
    if ! grep -qw "archboot" /etc/hostname; then
        echo "This script should only be run in booted archboot environment. Aborting..."
        exit 1
    fi
}

_ram_check() {
    while true; do
        # continue when 1 GB RAM is free
        [[ "$(grep -w MemAvailable /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "1000000" ]] && break
    done
}

_kill_w_dir() {
    if [[ -d "${_W_DIR}" ]]; then
        rm -r "${_W_DIR}"
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
        # online mode
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >"${_LOG}" 2>&1 || exit 1
        fi
    fi
    rm "${_W_DIR}"/.archboot
}

_network_check() {
    if ! getent hosts www.google.com &>"${_NO_LOG}"; then
        clear
        echo -e "\e[91mAborting:\e[m"
        echo -e "Network not yet ready."
        echo -e "Please configure your network first."
        exit 1
    fi
}

_update_installer_check() {
    if [[ -f /.update ]]; then
        clear
        echo -e "\e[91mAborting:\e[m"
        echo "update is already running on other tty..."
        echo "If you are absolutly sure it's not running, you need to remove /.update"
        exit 1
    fi
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _network_check
    fi
}

_full_system_check() {
    if [[ -e "/.full_system" ]]; then
        clear
        echo -e "\e[1mFull Arch Linux system already setup.\e[m"
        exit 0
    fi
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

_clean_kernel_cache () {
    echo 3 > /proc/sys/vm/drop_caches
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

_collect_files() {
    _KVER=$(_kver "${_RAM}/${_VMLINUZ}")
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount tmp;archboot-cpio.sh -k ${_KVER} -c ${_CONFIG} -d /tmp" >"${_LOG}" 2>&1
    rm "${_W_DIR}"/.archboot
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
    rm "${_W_DIR}"/.archboot
}

_progress_wait() {
    _COUNT=${1}
    while [[ -e "${_W_DIR}/.archboot" ]]; do
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

_download_latest() {
    # Download latest setup and quickinst script from git repository
    echo -e "\e[1mStart:\e[m Downloading latest archboot from GIT master tree..."
    [[ -d "${_INST}" ]] || mkdir "${_INST}"
    # config
    echo -e "\e[1mStep 1/4:\e[m Downloading latest config..."
    wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
    # helper binaries
    echo -e "\e[1mStep 2/4:\e[m Downloading latest scripts..."
    # main binaries
    BINS="quickinst setup clock launcher localize network pacsetup update copy-mountpoint rsync-backup restore-usbstick"
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
    LIBS="update.sh manage.sh desktop.sh xfce.sh gnome.sh gnome-wayland.sh plasma.sh plasma-wayland.sh sway.sh"
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
}

_new_environment() {
    _kill_w_dir
    _gpg_check
    _progress "1" "Removing files from /..."
    _clean_archboot
    _clean_kernel_cache
    [[ -d "${_W_DIR}" ]] || mkdir -p "${_W_DIR}"
    touch "${_W_DIR}"/.archboot
    _create_container &
    _progress_wait "2" "49" "Generating container in ${_W_DIR}..." "5"
    _clean_kernel_cache
    _ram_check
    mkdir ${_RAM}
    mount -t ramfs none ${_RAM}
    _progress "50" "Moving kernel ${_VMLINUZ} to ${_RAM}/${_VMLINUZ}..."
    # use ramfs to get immediate free space on file deletion
    mv "${_W_DIR}/boot/${_VMLINUZ}" ${_RAM}/ || exit 1
    _progress "51" "Collecting rootfs files in ${_W_DIR}..."
    # write initramfs to "${_W_DIR}"/tmp
    touch "${_W_DIR}"/.archboot
    _collect_files &
    _progress_wait "52" "69" "Collecting rootfs files in ${_W_DIR}..." "3"
    _progress "70" "Cleanup ${_W_DIR}..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' -exec rm -rf {} \;
    _clean_kernel_cache
    _ram_check
    # local switch, don't kexec on local image
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _progress "75" "Moving rootfs to ${_RAM}..."
        mv ${_W_DIR}/tmp/* /${_RAM}/
        # cleanup mkinitcpio directories and files
        _progress "95" "Cleanup ${_RAM}..."
        rm -rf /sysroot/{hooks,install,kernel,new_root,sysroot,mkinitcpio.*} &>"${_NO_LOG}"
        rm -f /sysroot/{VERSION,config,buildconfig,init} &>"${_NO_LOG}"
        _progress "100" "Switching to rootfs ${_RAM}..."
        sleep 2
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
    _progress "75" "Preserving Basic Setup values..."
    if [[ -e '/.localize' ]]; then
        cp /etc/{locale.gen,locale.conf} "${_C_DIR}"/etc
        cp /.localize "${_C_DIR}"/
        ${_NSPAWN} "${_C_DIR}" /bin/bash -c "locale-gen" &>"${_NO_LOG}"
        cp /etc/vconsole.conf "${_C_DIR}"/etc
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
        cp /.network-interface "${_C_DIR}"/
    fi
    if [[ -e '/.pacsetup' ]]; then
        cp /etc/pacman.conf "${_C_DIR}"/etc
        cp /etc/pacman.d/mirrorlist "${_C_DIR}"/etc/pacman.d/
        cp -ar /etc/pacman.d/gnupg "${_C_DIR}"/etc/pacman.d
        cp /.pacsetup "${_C_DIR}"/
    fi
    _progress "80" "Creating initramfs ${_RAM}/${_INITRD}..."
    touch "${_W_DIR}"/.archboot
    _create_initramfs &
    _progress_wait "81" "94" "Creating initramfs ${_RAM}/${_INITRD}..." "1"
    _progress "95" "Cleanup ${_W_DIR}..."
    cd /
    _kill_w_dir
    _clean_kernel_cache
    _progress "97" "Waiting for kernel to free RAM..."
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
    _progress "100" "Restarting with KEXEC_LOAD..."
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
        printf "\ec"
    done
}

_full_system() {
    _progress "1" "Refreshing pacman package database..."
    pacman -Sy >"${_LOG}" 2>&1 || exit 1
    _PACKAGES="$(pacman -Qqn)"
    _COUNT=0
    _PACKAGE_COUNT="$(pacman -Qqn | wc -l)"
    for i in ${_PACKAGES}; do
        if [[ "$((_COUNT*100/_PACKAGE_COUNT-4))" -gt 1 ]]; then
            _progress "$((_COUNT*100/_PACKAGE_COUNT-4))" "Reinstalling all packages, installing ${i} now..."
        fi
        pacman -S --noconfirm ${i} >"${_LOG}" 2>&1 || exit 1
        # avoid running mkinitcpio
        rm -f /usr/share/libalpm/{scripts/mkinitcpio,hooks/*mkinitcpio*}
        _COUNT="$((_COUNT+1))"
    done
    _progress "97" "Adding texinfo and man-pages..."
    pacman -S --noconfirm man-db man-pages texinfo >"${_LOG}" 2>&1 || exit 1
    _progress "98" "Checking kernel version..."
    _INSTALLED_KERNEL="$(pacman -Qi linux | grep Version | cut -d ':' -f 2 | sed -e 's# ##g' -e 's#\.arch#-arch#g')"
    if ! [[ "${_INSTALLED_KERNEL}" == "$(uname -r)" ]]; then
        _progress "99" "Skipping kernel module loading..."
    else
        _progress "99" "Trigger kernel module loading..."
        udevadm trigger --action=add --type=subsystems
        udevadm trigger --action=add --type=devices
        udevadm settle
    fi
    _progress "100" "Full Arch Linux system is ready now."
    sleep 2
    touch /.full_system
}

_new_image() {
    _PRESET_LATEST="${_RUNNING_ARCH}-latest"
    _PRESET_LOCAL="${_RUNNING_ARCH}-local"
    _ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)"
    _clean_archboot
    [[ -d var/cache/pacman/pkg ]] && rm -f /var/cache/pacman/pkg/*
    mkdir /archboot
    cd /archboot || exit 1
    _W_DIR="$(mktemp -u archboot-release.XXX)"
    # create container
    _progress "5" "Creating archboot container..."
    archboot-"${_RUNNING_ARCH}"-create-container.sh "${_W_DIR}" -cc > "${_LOG}" || exit 1
    _create_archboot_db "${_W_DIR}"/var/cache/pacman/pkg > "${_LOG}"
    # riscv64 does not support kexec at the moment
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        # removing not working lvm2 from latest image
        _progress "35" "Removing lvm2 from container..."
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm &>"${_NO_LOG}"
        _progress "40" "Generating local ISO..."
        # generate local iso in container, umount tmp it's a tmpfs and weird things could happen then
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
        rm -rf "${_W_DIR}"/var/cache/pacman/pkg/*
        _ram_check
        _progress "65" "Generating latest ISO..."
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
        _progress "72" "Installing lvm2 to container..."
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm &>"${_NO_LOG}"
    fi
    _progress "75" "Generating normal ISO..."
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_RUNNING_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_RUNNING_ARCH}" > "${_LOG}" || exit 1
    _progress "98" "Cleanup container..."
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>"${_NO_LOG}"
    mv "${_W_DIR}"/*.img ./ &>"${_NO_LOG}"
    rm -r "${_W_DIR}"
    _progress "100" "New isofiles are located in /archboot."
    sleep 2
}
# vim: set ft=sh ts=4 sw=4 et:
