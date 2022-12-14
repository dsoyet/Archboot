#!/usr/bin/env bash
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
_INST="/${_LIB}/installer"
_RUN="/${_LIB}/run"
_UPDATE="/${_LIB}/update-installer"
_ZRAM_SIZE=${_ZRAM_SIZE:-"3G"}
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && VMLINUZ="vmlinuz-linux"
[[ "${_RUNNING_ARCH}" == "aarch64" ]] && VMLINUZ="Image"

_graphic_options() {
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo -e " \033[1m-gnome\033[0m           Launch Gnome desktop with VNC sharing enabled."
        echo -e " \033[1m-gnome-wayland\033[0m   Launch Gnome desktop with Wayland backend."
        echo -e " \033[1m-plasma\033[0m          Launch KDE Plasma desktop with VNC sharing enabled."
        echo -e " \033[1m-plasma-wayland\033[0m  Launch KDE Plasma desktop with Wayland backend."
    fi
}

usage () {
    echo -e "\033[1mUpdate installer, launch environments or create latest image files:\033[0m"
    echo -e "\033[1m-------------------------------------------------------------------\033[0m"
    echo -e "\033[1mPARAMETERS:\033[0m"
    echo -e " \033[1m-h\033[0m               This message."
    if [[ ! -e "/var/cache/pacman/pkg/archboot.db" || -e "/usr/bin/setup" ]]; then
        echo -e " \033[1m-u\033[0m               Update scripts: setup, quickinst, tz, km and helpers."
    fi
    # latest image
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 && ! -e "/.full_system" && ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        echo -e " \033[1m-full-system\033[0m     Switch to full Arch Linux system."
    # local image
    elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 && ! -e "/.full_system" && -e "/var/cache/pacman/pkg/archboot.db" && -e "/usr/bin/setup" ]]; then
        echo -e " \033[1m-full-system\033[0m     Switch to full Arch Linux system."
    fi
    echo -e ""
    if [[ -e "/usr/bin/setup" ]]; then
        # works only on latest image
        if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] ; then
                _graphic_options
            fi
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 ]]; then
                echo -e " \033[1m-xfce\033[0m            Launch XFCE desktop with VNC sharing enabled."
                echo -e " \033[1m-custom-xorg\033[0m     Install custom X environment."
               [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] && echo -e " \033[1m-custom-wayland\033[0m  Install custom Wayland environment."
                echo ""
            fi
        fi
    fi
    if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]] || [[ -e "/var/cache/pacman/pkg/archboot.db" && ! -e "/usr/bin/setup" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 1970000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \033[1m-latest\033[0m          Launch latest archboot environment (using kexec)."
            fi
        fi
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \033[1m-latest-install\033[0m  Launch latest archboot environment with"
                echo -e "                  package cache (using kexec)."
            fi
        fi
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 4616000 &&\
    -e /usr/bin/archboot-"${_RUNNING_ARCH}"-release.sh ]]; then
        echo -e " \033[1m-latest-image\033[0m    Generate latest image files in /archboot directory."
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
    if [[ "${_D_SCRIPTS}" == "1" ]]; then
        if ! ping -c1 www.google.com >/dev/tty7 2>&1; then
            echo -e "\033[91mError: Network not yet ready, aborting!\033[0m"
            exit 1
        fi
        echo -e "\033[1mStart:\033[0m Downloading latest km, tz, quickinst, setup and helpers..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        # config
        echo -e "\033[1mStep 1/4:\033[0m Downloading latest config ..."
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        # helper binaries
        echo -e "\033[1mStep 2/4:\033[0m Downloading latest scripts ..."
        # main binaries
        BINS="quickinst setup km tz update-installer copy-mountpoint rsync-backup restore-usbstick"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        BINS="binary-check.sh secureboot-keys.sh mkkeys.sh hwsim.sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        # main libs
        echo -e "\033[1mStep 3/4:\033[0m Downloading latest script libs ..."
        LIBS="common.sh container.sh release.sh iso.sh login.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_LIB}/${i}?inline=false" -O "${_LIB}/${i}"
        done
        # update-installer libs
        LIBS="update-installer.sh xfce.sh gnome.sh gnome-wayland.sh plasma.sh plasma-wayland.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_UPDATE}/${i}?inline=false" -O "${_UPDATE}/${i}"
        done
        # run libs
        LIBS="container.sh release.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_RUN}/${i}?inline=false" -O "${_RUN}/${i}"
        done
        # setup libs
        echo -e "\033[1mStep 4/4:\033[0m Downloading latest setup libs ..."
        LIBS="autoconfiguration.sh autoprepare.sh base.sh blockdevices.sh bootloader.sh btrfs.sh common.sh \
                configuration.sh mountpoints.sh network.sh pacman.sh partition.sh storage.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_INST}/${i}?inline=false" -O "${_INST}/${i}"
        done
        echo -e "\033[1mFinished:\033[0m Downloading scripts done."
        exit 0
    fi
}

_update_installer_check() {
    if [[ -f /.update-installer ]]; then
        echo -e "\033[91mAborting:\033[0m"
        echo "update-installer is already running on other tty ..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
}

_zram_initialize() {
    # add defaults
    _ZRAM_ALGORITHM=${_ZRAM_ALGORITHM:-"zstd"}
    if ! grep -qw zram /proc/modules; then
        modprobe zram num_devices=2> /dev/tty7 2>&1
        echo "${_ZRAM_ALGORITHM}" >/sys/block/zram0/comp_algorithm
        echo "${_ZRAM_ALGORITHM}" >/sys/block/zram1/comp_algorithm
    fi
}

# use -o discard for RAM cleaning on delete
# (online fstrimming the block device!)
# fstrim <mountpoint> for manual action
# it needs some seconds to get RAM free on delete!
_zram_usr() {
    if ! mountpoint -q /usr; then
        echo "${1}" >/sys/block/zram0/disksize
        echo "Creating btrfs filesystem with ${1} on /dev/zram0 ..." > /dev/tty7
        mkfs.btrfs -q --mixed /dev/zram0 > /dev/tty7 2>&1
        mkdir /usr.zram
        mount -o discard /dev/zram0 "/usr.zram" > /dev/tty7 2>&1
        echo "Moving /usr to /usr.zram ..." > /dev/tty7
        mv /usr/* /usr.zram/
        USR_SYMLINKS="bin local lib"
        # lib64 is x86_64 only
        [[ "${_RUNNING_ARCH}" == "x86_64" ]] && USR_SYMLINKS="${USR_SYMLINKS} lib64"
        for i in ${USR_SYMLINKS}; do
            /usr.zram/bin/sln /usr.zram/"${i}" /usr/"${i}"
        done
        # pacman kills symlinks in below /usr
        # mount --bind is the only way to solve this.
        mount --bind /usr.zram /usr
        systemctl restart dbus > /dev/tty7 2>&1
    fi
}

_zram_w_dir() {
    echo "${1}" >/sys/block/zram1/disksize
    echo "Creating btrfs filesystem with ${1} on /dev/zram1 ..." > /dev/tty7
    mkfs.btrfs -q --mixed /dev/zram1 > /dev/tty7 2>&1
    [[ -d "${_W_DIR}" ]] || mkdir "${_W_DIR}"
    mount -o discard /dev/zram1 "${_W_DIR}" > /dev/tty7 2>&1
}

_initialize_zram_usr() {
    echo -e "\033[1mInitializing /usr.zram ...\033[0m"
    echo -e "\033[1mStep 1/2:\033[0m Waiting for gpg pacman keyring import to finish ..."
    _gpg_check
    if ! [[ -d /usr.zram ]]; then
        echo -e "\033[1mStep 2/2:\033[0m Move /usr to /usr.zram ..."
        _zram_usr "${_ZRAM_SIZE}"
    else
        echo -e "\033[1mStep 2/2:\033[0m Move /usr to /usr.zram already done ..."
    fi
}

_umount_w_dir() {
    if mountpoint -q "${_W_DIR}"; then
        echo "Unmounting ${_W_DIR} ..." > /dev/tty7
        # umount all possible mountpoints
        umount -R "${_W_DIR}"
        echo 1 > /sys/block/zram1/reset
        # wait 5 seconds to get RAM cleared and set free
        sleep 5
    fi
}

_clean_archboot() {
    # remove everything not necessary
    rm -rf "/usr/lib/firmware"
    rm -rf "/usr/lib/modules"
    rm -rf /usr/lib/{libicu*,libstdc++*}
    _SHARE_DIRS="efitools grub hwdata kbd licenses lshw nmap nano pacman refind systemd tc vim zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
}

_create_container() {
    # create container without package cache
    if [[ "${_L_COMPLETE}" == "1" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for local image
        # add the db too on reboot
        install -D -m644 /var/cache/pacman/pkg/archboot.db "${_W_DIR}"/var/cache/pacman/pkg/archboot.db
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
        fi
        # needed for checks
        cp "${_W_DIR}"/var/cache/pacman/pkg/archboot.db /var/cache/pacman/pkg/archboot.db
    else
        #online mode
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
        fi
    fi
}

_kver_x86() {
    # get kernel version from installed kernel
    if [[ -f "/${VMLINUZ}" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/${VMLINUZ}")
        read -r _HWKVER _ < <(dd if="/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
    fi
    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_kver_generic() {
    # get kernel version from installed kernel
    if [[ -f "/${VMLINUZ}" ]]; then
        reader="cat"
        # try if the image is gzip compressed
        [[ $(file -b --mime-type "/${VMLINUZ}") == 'application/gzip' ]] && reader="zcat"
        read -r _ _ _HWKVER _ < <($reader "/${VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi

    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_create_initramfs() {
    #from /usr/bin/mkinitcpio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    bsdtar --null -cf - --format=newc @- | zstd --rm -T0> /initrd.img &
    sleep 2
    while pgrep -x zstd > /dev/null 2>&1; do
        _clean_kernel_cache
        sleep 1
    done
}

_kexec() {
    # you need approx. 3.39x size for KEXEC_FILE_LOAD
    if [[ "$(($(stat -c %s /initrd.img)*339/100000))" -lt "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" ]]; then
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mnew\033[0m KEXEC_FILE_LOAD ..."
        kexec -s -f /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
    else
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mold\033[0m KEXEC_LOAD ..."
        kexec -c -f --mem-max=0xA0000000 /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
    fi
    sleep 2
    _clean_kernel_cache
    rm /{${VMLINUZ},initrd.img}
    while pgrep -x kexec > /dev/null 2>&1; do
        _clean_kernel_cache
        sleep 1
    done
    #shellcheck disable=SC2115
    rm -rf /usr/*
}

_cleanup_install() {
    rm -rf /usr/share/{man,help,gir-[0-9]*,info,doc,gtk-doc,ibus,perl[0-9]*}
    rm -rf /usr/include
    rm -rf /usr/lib/libgo.*
}

_cleanup_cache() {
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(grep -w 'installed' /var/log/pacman.log | cut -d ' ' -f 4); do
        rm -rf /var/cache/pacman/pkg/"${i}"-[0-9]*
    done
}

# needed for programs which check disk space
_home_root_mount() {
    if ! mountpoint /home >/dev/null 2>&1; then
        /usr/bin/mount -t tmpfs tmpfs /home
    fi
    if ! mountpoint /root >/dev/null 2>&1; then
        /usr/bin/mount -t tmpfs tmpfs /root
    fi
}

_prepare_graphic() {
    _GRAPHIC="${1}"
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing firmware files ..."
        rm -rf /usr/lib/firmware
        # fix libs first, then install packages from defaults
        _GRAPHIC="${_FIX_PACKAGES} ${1}"
    fi
    # saving RAM by calling always cleanup hook and installing each package alone
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo "Running pacman to install packages: ${_GRAPHIC} ..."
        _INSTALL_SOURCE="file:///var/cache/pacman/pkg"
        #shellcheck disable=SC2119
        _create_pacman_conf
        #shellcheck disable=SC2086
        pacman -Sy --config ${_PACMAN_CONF} >/dev/null 2>&1 || exit 1
        # check if already full system is used
        for i in ${_GRAPHIC}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --config ${_PACMAN_CONF} --noconfirm >/dev/null 2>&1 || exit 1
            [[ ! -e "/.full_system" ]] && _cleanup_install
            [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
            rm -f /var/log/pacman.log
        done
    else
        echo "Updating environment to latest packages (ignoring packages: ${_GRAPHIC_IGNORE}) ..."
        _IGNORE=""
        if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
            for i in ${_GRAPHIC_IGNORE}; do
                _IGNORE="${_IGNORE} --ignore ${i}"
            done
        fi
        #shellcheck disable=SC2086
        pacman -Syu ${_IGNORE} --noconfirm >/dev/null 2>&1 || exit 1
        [[ ! -e "/.full_system" ]] && _cleanup_install
        echo "Running pacman to install packages: ${_GRAPHIC} ..."
        for i in ${_GRAPHIC}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --noconfirm >/dev/null 2>&1 || exit 1
            [[ ! -e "/.full_system" ]] && _cleanup_install
            [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
            rm -f /var/log/pacman.log
        done
    fi
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing not used icons ..."
        rm -rf /usr/share/icons/breeze-dark
        echo "Cleanup locale and i18n ..."
        rm -rf /usr/share/{locale,i18n}
    fi
    _home_root_mount
}

_new_environment() {
    _update_installer_check
    touch /.update-installer
    _umount_w_dir
    _zram_w_dir "${_ZRAM_SIZE}"
    echo -e "\033[1mStep 1/9:\033[0m Waiting for gpg pacman keyring import to finish ..."
    _gpg_check
    echo -e "\033[1mStep 2/9:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    _zram_usr "300M"
    _clean_kernel_cache
    echo -e "\033[1mStep 3/9:\033[0m Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    _create_container || exit 1
    # 10 seconds for getting free RAM
    _clean_kernel_cache
    sleep 10
    echo -e "\033[1mStep 4/9:\033[0m Copy kernel ${VMLINUZ} to /${VMLINUZ} ..."
    cp "${_W_DIR}/boot/${VMLINUZ}" / || exit 1
    [[ ${_RUNNING_ARCH} == "x86_64" ]] && _kver_x86
    [[ ${_RUNNING_ARCH} == "aarch64" || ${_RUNNING_ARCH} == "riscv64" ]] && _kver_generic
    echo -e "\033[1mStep 5/9:\033[0m Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # write initramfs to "${_W_DIR}"/tmp
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mStep 6/9:\033[0m Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    # 10 seconds for getting free RAM
    _clean_kernel_cache
    sleep 10
    echo -e "\033[1mStep 7/9:\033[0m Create initramfs /initrd.img ..."
    echo "          This will need some time ..."
    _create_initramfs
    echo -e "\033[1mStep 8/9:\033[0m Cleanup ${_W_DIR} ..."
    cd /
    _umount_w_dir
    _clean_kernel_cache
    # unload virtio-net to avoid none functional network device on aarch64
    grep -qw virtio_net /proc/modules && rmmod virtio_net
    echo -e "\033[1mStep 9/9:\033[0m Loading files through kexec into kernel now ..."
    echo "          This will need some time ..."
    _kexec
}

_kernel_check() {
    _PATH="/usr/bin"
    _INSTALLED_KERNEL="$(${_PATH}/pacman -Qi linux | ${_PATH}/grep Version | ${_PATH}/cut -d ':' -f 2 | ${_PATH}/sed -e 's# ##g' -e 's#\.arch#-arch#g')"
    _RUNNING_KERNEL="$(${_PATH}/uname -r)"
    if ! [[ "${_INSTALLED_KERNEL}" == "${_RUNNING_KERNEL}" ]]; then
        echo -e "\033[93mWarning:\033[0m"
        echo -e "Installed kernel does \033[1mnot\033[0m match running kernel!"
        echo -e "Kernel module loading will \033[1mnot\033[0m work."
        echo -e "Use \033[1m--latest\033[0m options to get a matching kernel first."
    fi
}

_full_system() {
    if [[ -e "/.full_system" ]]; then
        echo -e "\033[1m\033[1mFull Arch Linux system already setup.\033[0m"
        exit 0
    fi
    # higher _ZRAM_SIZE is needed for plasma environment 200MB safety buffer
    #shellcheck disable=SC2001,SC2086
    _ZRAM_VALUE="$(echo ${_ZRAM_SIZE} | sed -e 's#[A-Z]##g')"
    if [[ "${_ZRAM_VALUE}" -lt "4000" ]]; then
        _ZRAM_SIZE="4000M"
    fi
    _initialize_zram_usr
    echo -e "\033[1mInitializing full Arch Linux system ...\033[0m"
    echo -e "\033[1mStep 1/3:\033[0m Reinstalling packages and adding info/man-pages ..."
    echo "          This will need some time ..."
    pacman -Sy >/dev/tty7 2>&1 || exit 1
    pacman -Qqn | pacman -S --noconfirm man-db man-pages texinfo - >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mStep 2/3:\033[0m Checking /home and /root are tmpfs ..."
    _home_root_mount
    echo -e "\033[1mStep 3/3:\033[0m Checking kernel version ..."
    _kernel_check
    echo -e "\033[1mFull Arch Linux system is ready now.\033[0m"
    touch /.full_system
}

_new_image() {
    _zram_w_dir "4000M"
    echo -e "\033[1mStep 1/2:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    rm /var/cache/pacman/pkg/*
    _zram_usr "300M"
    echo -e "\033[1mStep 2/2:\033[0m Generating new iso files in ${_W_DIR} now ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mFinished:\033[0m New isofiles are located in ${_W_DIR}"
}

_install_graphic () {
    _initialize_zram_usr
    [[ -e /var/cache/pacman/pkg/archboot.db ]] && touch /.graphic_installed
    echo -e "\033[1mInitializing desktop environment ...\033[0m"
    [[ "${_L_XFCE}" == "1" ]] && _install_xfce
    [[ "${_L_GNOME}" == "1" ]] && _install_gnome
    [[ "${_L_GNOME_WAYLAND}" == "1" ]] && _install_gnome_wayland
    [[ "${_L_PLASMA}" == "1" ]] && _install_plasma
    [[ "${_L_PLASMA_WAYLAND}" == "1" ]] && _install_plasma_wayland
    echo -e "\033[1mStep 3/4:\033[0m Starting avahi-daemon ..."
    systemctl start avahi-daemon.service
    # only start vnc on xorg environment
    echo -e "\033[1mStep 4/4:\033[0m Setting up VNC and browser ...\033[0m"
    [[ "${_L_XFCE}" == "1" || "${_L_PLASMA}" == "1" || "${_L_GNOME}" == "1" ]] && _autostart_vnc
    which firefox > /dev/null 2>&1  && _firefox_flags
    which chromium > /dev/null 2>&1 && _chromium_flags
    [[ "${_L_XFCE}" == "1" ]] && _start_xfce
    [[ "${_L_GNOME}" == "1" ]] && _start_gnome
    [[ "${_L_GNOME_WAYLAND}" == "1" ]] && _start_gnome_wayland
    [[ "${_L_PLASMA}" == "1" ]] && _start_plasma
    [[ "${_L_PLASMA_WAYLAND}" == "1" ]] && _start_plasma_wayland
}

_hint_graphic_installed () {
    echo -e "\033[1m\033[91mError: Graphical environment already installed ...\033[0m"
    echo -e "You are running in \033[1mLocal mode\033[0m with less than \033[1m4500 MB RAM\033[0m, which only can launch \033[1mone\033[0m environment."
    echo -e "Please relaunch your already used graphical environment from commandline."
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\033[1mStep 1/4:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 2/4:\033[0m Configuring GNOME desktop ..."
        _configure_gnome >/dev/tty7 2>&1
        systemd-sysusers >/dev/tty7 2>&1
        systemd-tmpfiles --create >/dev/tty7 2>&1
    else
        echo -e "\033[1mStep 1/4:\033[0m Installing GNOME desktop already done ..."
        echo -e "\033[1mStep 2/4:\033[0m Configuring GNOME desktop already done ..."
    fi
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 1/4:\033[0m Installing KDE/Plasma desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 2/4:\033[0m Configuring KDE desktop ..."
        _configure_plasma >/dev/tty7 2>&1
    else
        echo -e "\033[1mStep 1/4:\033[0m Installing KDE/Plasma desktop already done ..."
        echo -e "\033[1mStep 2/4:\033[0m Configuring KDE desktop already done ..."
    fi
}

_configure_gnome() {
    echo "Configuring Gnome ..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper ..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup ..."
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
    echo "Hiding ${_HIDE_MENU} menu entries ..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_configure_plasma() {
    echo "Configuring KDE ..."
    sed -i -e "s#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,applications:${_STANDARD_BROWSER}.desktop,applications:gparted.desktop,applications:archboot.desktop</default>#g" /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper ..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure ..."
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
    echo "Autostarting setup ..."
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

_custom_wayland_xorg() {
    _initialize_zram_usr
    if [[ "${_CUSTOM_WAYLAND}" == "1" ]]; then
        echo -e "\033[1mStep 1/3:\033[0m Installing custom wayland ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND}" > /dev/tty7 2>&1
    fi
    if [[ "${_CUSTOM_X}" == "1" ]]; then
        echo -e "\033[1mStep 1/3:\033[0m Installing custom xorg ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_XORG_PACKAGE} ${_CUSTOM_XORG}" > /dev/tty7 2>&1
    fi
    echo -e "\033[1mStep 2/3:\033[0m Starting avahi-daemon ..."
    systemctl start avahi-daemon.service
    echo -e "\033[1mStep 3/3:\033[0m Setting up browser ...\033[0m"
    which firefox > /dev/null 2>&1  && _firefox_flags
    which chromium > /dev/null 2>&1 && _chromium_flags
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf ..." >/dev/tty7
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
bit.ly/archboot
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! grep -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
            echo "Adding firefox flags vendor.js ..." >/dev/tty7
            cat << EOF >> /usr/lib/firefox/browser/defaults/preferences/vendor.js
pref("browser.aboutwelcome.enabled", false, locked);
pref("browser.startup.homepage_override.once", false, locked);
pref("datareporting.policy.firstRunURL", "https://bit.ly/archboot", locked);
EOF
        fi
    fi
}

_autostart_vnc() {
    echo "Setting VNC password /etc/tigervnc/passwd to ${_VNC_PW} ..." >/dev/tty7
    echo "${_VNC_PW}" | vncpasswd -f > /etc/tigervnc/passwd
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Autostarting tigervnc ..." >/dev/tty7
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
}
