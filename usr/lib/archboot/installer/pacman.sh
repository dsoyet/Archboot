#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# downloader
DLPROG="wget"
MIRRORLIST="/etc/pacman.d/mirrorlist"

getsource() {
    S_SRC=0
    PACMAN_CONF=""
    if [[ -e "${LOCAL_DB}" ]]; then
        NEXTITEM="4"
        local_pacman_conf
        DIALOG --msgbox "Setup is running in <Local mode>.\nOnly Local package database is used for package installation.\n\nIf you want to switch to <Online mode>, you have to delete /var/cache/pacman/pkg/archboot.db and rerun this step." 10 70
        S_SRC=1
    else
        select_mirror || return 1
        S_SRC=1
    fi
}

# select_mirror()
# Prompt user for preferred mirror and set ${SYNC_URL}
#
# args: none
# returns: nothing
select_mirror() {
    NEXTITEM="2"
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        dialog --infobox "Downloading latest mirrorlist ..." 3 40
        ${DLPROG} -q "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
        if grep -q '#Server = http:' /tmp/pacman_mirrorlist.txt; then
            mv "${MIRRORLIST}" "${MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    MIRRORS=$(grep -E -o '((http)|(https))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
    #shellcheck disable=SC2086
    DIALOG --menu "Select a mirror:" 14 55 7 \
        ${MIRRORS} \
        "Custom" "_" 2>${_ANSWER} || return 1
    #shellcheck disable=SC2155
    local _server=$(cat "${_ANSWER}")
    if [[ "${_server}" == "Custom" ]]; then
        DIALOG --inputbox "Enter the full URL to repositories." 8 65 \
            "" 2>"${_ANSWER}" || return 1
            SYNC_URL=$(cat "${_ANSWER}")
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        SYNC_URL=$(grep -E -o "${_server}.*" "${MIRRORLIST}" | head -n1)
    fi
    NEXTITEM="4"
    echo "Using mirror: ${SYNC_URL}" > "${LOG}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${SYNC_URL}"" >> /etc/pacman.d/mirrorlist
}

# dotesting()
# enable testing repository on network install
dotesting() {
    if ! grep -q "^\[testing\]" /etc/pacman.conf; then
        DIALOG --defaultno --yesno "Do you want to enable [testing]\nand [community-testing] repositories?\n\nOnly enable this if you need latest\navailable packages for testing purposes!" 9 50 && DOTESTING="yes"
        if [[ "${DOTESTING}" == "yes" ]]; then
            sed -i -e '/^#\[testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' /etc/pacman.conf
        fi
    fi
}

# check for updating complete environment with packages
update_environment() {
    if [[ -d "/var/cache/pacman/pkg" ]] && [[ -n "$(ls -A "/var/cache/pacman/pkg")" ]]; then
        echo "Packages are already in pacman cache ..."  > "${LOG}"
        DIALOG --infobox "Packages are already in pacman cache. Continuing in 3 seconds ..." 3 70
        sleep 3
    else
        UPDATE_ENVIRONMENT=""
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "2571000" ]]; then
            if ! [[ "${RUNNING_ARCH}" == "riscv64" ]]; then
                DIALOG --infobox "Refreshing package database ..." 3 70
                pacman -Sy > "${LOG}" 2>&1
                sleep 1
                DIALOG --infobox "Checking on new online kernel version ..." 3 70
                #shellcheck disable=SC2086
                LOCAL_KERNEL="$(pacman -Qi ${KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                if  [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
                    #shellcheck disable=SC2086
                    ONLINE_KERNEL="$(pacman -Si ${KERNELPKG}-${RUNNING_ARCH} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                else
                    #shellcheck disable=SC2086
                    ONLINE_KERNEL="$(pacman -Si ${KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                fi
                echo "${LOCAL_KERNEL} local kernel version and ${ONLINE_KERNEL} online kernel version." > "${LOG}"
                sleep 2
                if [[ "${LOCAL_KERNEL}" == "${ONLINE_KERNEL}" ]]; then
                    DIALOG --infobox "No new kernel online available. Continuing in 3 seconds ..." 3 70
                    sleep 3
                else
                    DIALOG --defaultno --yesno "New online kernel version ${ONLINE_KERNEL} available.\n\nDo you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nThis will reboot the system using kexec!" 0 0 && UPDATE_ENVIRONMENT="1"
                    if [[ "${UPDATE_ENVIRONMENT}" == "1" ]]; then
                        DIALOG --infobox "Now setting up new archboot environment and dowloading latest packages.\n\nRunning at the moment: update-installer -latest-install\nCheck ${VC} console (ALT-F${VC_NUM}) for progress...\n\nGet a cup of coffee ...\nDepending on your system's setup, this needs about 5 minutes.\nPlease be patient." 0 0
                        update-installer -latest-install > "${LOG}" 2>&1
                    fi
                fi
            fi
        fi
    fi
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
prepare_pacman() {
    NEXTITEM="5"
    # Set up the necessary directories for pacman use
    [[ ! -d "${_DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${_DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${_DESTDIR}/var/lib/pacman" ]] && mkdir -p "${_DESTDIR}/var/lib/pacman"
    DIALOG --infobox "Waiting for Arch Linux keyring initialization ..." 3 40
    # pacman-key process itself
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    DIALOG --infobox "Refreshing package database ..." 3 40
    ${PACMAN} -Sy > "${LOG}" 2>&1 || (DIALOG --msgbox "Pacman preparation failed! Check ${LOG} for errors." 6 60; return 1)
    DIALOG --infobox "Update Arch Linux keyring ..." 3 40
    KEYRING="archlinux-keyring"
    [[ "${RUNNING_ARCH}" == "aarch64" ]] && KEYRING="${KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy ${PACMAN_CONF} --noconfirm --noprogressbar ${KEYRING} > "${LOG}" 2>&1 || (DIALOG --msgbox "Keyring update failed! Check ${LOG} for errors." 6 60; return 1)
}

# Set PACKAGES parameter before running to install wanted packages
run_pacman(){
    # create chroot environment on target system
    # code straight from mkarchroot
    chroot_mount
    DIALOG --infobox "Pacman is running...\n\nInstalling package(s) to ${_DESTDIR}:\n${PACKAGES} ...\n\nCheck ${VC} console (ALT-F${VC_NUM}) for progress ..." 10 70
    echo "Installing Packages ..." >/tmp/pacman.log
    sleep 5
    #shellcheck disable=SC2086,SC2069
    ${PACMAN} -S ${PACKAGES} |& tee -a "${LOG}" /tmp/pacman.log >/dev/null 2>&1
    echo $? > /tmp/.pacman-retcode
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
    else
        echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
    fi
    # pacman finished, display scrollable output
    local _result=''
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        _result="Installation Failed (see errors below)"
        DIALOG --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/pacman.log" 18 70 || return 1
    else
        DIALOG --infobox "Package installation complete.\nContinuing in 3 seconds ..." 4 40
        sleep 3
    fi
    rm /tmp/.pacman-retcode
    # ensure the disk is synced
    sync
    chroot_umount
}

# install_packages()
# performs package installation to the target system
install_packages() {
    destdir_mounts || return 1
    if [[ "${S_SRC}" == "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman || return 1
    PACKAGES=""
    # add packages from archboot defaults
    PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${PACKAGES}" ]] && PACKAGES="base linux linux-firmware"
    auto_packages
    # fix double spaces
    PACKAGES="${PACKAGES//  / }"
    DIALOG --yesno "Next step will install the following packages for a minimal system:\n${PACKAGES}\n\nYou can watch the progress on your ${VC} console.\n\nDo you wish to continue?" 12 75 || return 1
    run_pacman
    NEXTITEM="6"
    chroot_mount
    # automagic time!
    # any automatic configuration should go here
    DIALOG --infobox "Writing base configuration ..." 6 40
    auto_timesetting
    auto_network
    auto_fstab
    auto_scheduler
    auto_swap
    auto_mdadm
    auto_luks
    auto_pacman
    auto_testing
    auto_pacman_mirror
    auto_vconsole
    auto_hostname
    auto_locale
    auto_nano_syntax
    # tear down the chroot environment
    chroot_umount
}
