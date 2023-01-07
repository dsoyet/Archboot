#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# name of intel ucode initramfs image
INTEL_UCODE="intel-ucode.img"
# name of amd ucode initramfs image
AMD_UCODE="amd-ucode.img"
ROOTFS=""
# name of the initramfs filesystem
INITRAMFS="initramfs-${KERNELPKG}.img"

getrootfstype() {
    ROOTFS="$(getfstype "${PART_ROOT}")"
}

getrootflags() {
    ROOTFLAGS=""
    ROOTFLAGS="$(findmnt -m -n -o options -T "${_DESTDIR}")"
    # add subvolume for btrfs
    if [[ "${ROOTFS}" == "btrfs" ]]; then
        findmnt -m -n -o SOURCE -T "${_DESTDIR}" | grep -q "\[" && ROOTFLAGS="${ROOTFLAGS},subvol=$(basename "$(findmnt -m -n -o SOURCE -T "${_DESTDIR}" | cut -d "]" -f1)")"
    fi
    [[ -n "${ROOTFLAGS}" ]] && ROOTFLAGS="rootflags=${ROOTFLAGS}"
}

getraidarrays() {
    RAIDARRAYS=""
    if ! grep -q ^ARRAY "${_DESTDIR}"/etc/mdadm.conf; then
        RAIDARRAYS="$(echo -n "$(grep ^md /proc/mdstat 2>/dev/null | sed -e 's#\[[0-9]\]##g' -e 's# :.* raid[0-9]##g' -e 's#md#md=#g' -e 's# #,/dev/#g' -e 's#_##g')")"
    fi
}

getcryptsetup() {
    CRYPTSETUP=""
    if ! cryptsetup status "$(basename "${PART_ROOT}")" | grep -q inactive; then
        #avoid clash with dmraid here
        if cryptsetup status "$(basename "${PART_ROOT}")"; then
            if [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
                CRYPTDEVICE="UUID=$(${_LSBLK} UUID "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            elif [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
                CRYPTDEVICE="LABEL=$(${_LSBLK} LABEL "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            else
                CRYPTDEVICE="$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g'))"
            fi
            CRYPTNAME="$(basename "${PART_ROOT}")"
            CRYPTSETUP="cryptdevice=${CRYPTDEVICE}:${CRYPTNAME}"
        fi
    fi
}

getrootpartuuid() {
    _rootpart="${PART_ROOT}"
    _partuuid="$(getpartuuid "${PART_ROOT}")"
    if [[ -n "${_partuuid}" ]]; then
        _rootpart="PARTUUID=${_partuuid}"
    fi
}

getrootpartlabel() {
    _rootpart="${PART_ROOT}"
    _partlabel="$(getpartlabel "${PART_ROOT}")"
    if [[ -n "${_partlabel}" ]]; then
        _rootpart="PARTLABEL=${_partlabel}"
    fi
}

getrootfsuuid() {
    _rootpart="${PART_ROOT}"
    _fsuuid="$(getfsuuid "${PART_ROOT}")"
    if [[ -n "${_fsuuid}" ]]; then
        _rootpart="UUID=${_fsuuid}"
    fi
}

getrootfslabel() {
    _rootpart="${PART_ROOT}"
    _fslabel="$(getfslabel "${PART_ROOT}")"
    if [[ -n "${_fslabel}" ]]; then
        _rootpart="LABEL=${_fslabel}"
    fi
}

# freeze and unfreeze xfs, as hack for grub(2) installing
freeze_xfs() {
    sync
    if [[ -x /usr/bin/xfs_freeze ]]; then
        if grep -q "${_DESTDIR}/boot " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${_DESTDIR}"/boot >/dev/null 2>&1
            xfs_freeze -u "${_DESTDIR}"/boot >/dev/null 2>&1
        fi
        if grep -q "${_DESTDIR} " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${_DESTDIR}" >/dev/null 2>&1
            xfs_freeze -u "${_DESTDIR}" >/dev/null 2>&1
        fi
    fi
}

## Setup kernel cmdline parameters to be added to bootloader configs
bootloader_kernel_parameters() {
    if [[ "${_UEFI_BOOT}" == "1" ]]; then
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] && getrootpartuuid
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] && getrootpartlabel
    fi
    [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] && getrootfsuuid
    [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] && getrootfslabel
    [[ "${_rootpart}" == "" ]] && _rootpart="${PART_ROOT}"
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_rootpart} rootfstype=${ROOTFS} rw ${ROOTFLAGS} ${RAIDARRAYS} ${CRYPTSETUP}"
    _KERNEL_PARAMS_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
}

# basic checks needed for all bootloaders
common_bootloader_checks() {
    activate_special_devices
    getrootfstype
    getraidarrays
    getcryptsetup
    getrootflags
    bootloader_kernel_parameters
}

# look for a separately-mounted /boot partition
check_bootpart() {
    subdir=""
    bootdev="$(mount | grep "${_DESTDIR}/boot " | cut -d' ' -f 1)"
    if [[ "${bootdev}" == "" ]]; then
        subdir="/boot"
        bootdev="${PART_ROOT}"
    fi
}

# only allow ext2/3/4 and vfat on uboot bootloader
abort_uboot(){
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}" 2>/dev/null)"
        if ! [[ "${FSTYPE}" == "ext2" || "${FSTYPE}" == "ext3" || "${FSTYPE}" == "ext4" || "${FSTYPE}" == "vfat" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from none ext2/3/4 or vfat /boot on it." 0 0
            return 1
        fi
}

# check for nilfs2 bootpart and abort if detected
abort_nilfs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}" 2>/dev/null)"
        if [[ "${FSTYPE}" == "nilfs2" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from nilfs2 partition with /boot on it." 0 0
            return 1
        fi
}

# check for f2fs bootpart and abort if detected
abort_f2fs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}" 2>/dev/null)"
        if [[ "${FSTYPE}" == "f2fs" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from f2fs partition with /boot on it." 0 0
            return 1
        fi
}

do_uefi_common() {
    PACKAGES=""
    [[ ! -f "${_DESTDIR}/usr/bin/mkfs.vfat" ]] && PACKAGES="${PACKAGES} dosfstools"
    [[ ! -f "${_DESTDIR}/usr/bin/efivar" ]] && PACKAGES="${PACKAGES} efivar"
    [[ ! -f "${_DESTDIR}/usr/bin/efibootmgr" ]] && PACKAGES="${PACKAGES} efibootmgr"
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        [[ ! -f "${_DESTDIR}/usr/bin/mokutil" ]] && PACKAGES="${PACKAGES} mokutil"
        [[ ! -f "${_DESTDIR}/usr/bin/efi-readvar" ]] && PACKAGES="${PACKAGES} efitools"
        [[ ! -f "${_DESTDIR}/usr/bin/sbsign" ]] && PACKAGES="${PACKAGES} sbsigntools"
    fi
    ! [[ "${PACKAGES}" == "" ]] && run_pacman
    check_efisys_part
}

do_uefi_efibootmgr() {
    if [[ "$(/usr/bin/efivar -l)" ]]; then
        cat << EFIBEOF > "/tmp/efibootmgr_run.sh"
#!/usr/bin/env bash
_BOOTMGR_LOADER_PARAMETERS="${_BOOTMGR_LOADER_PARAMETERS}"
for _bootnum in \$(efibootmgr | grep '^Boot[0-9]' | grep -F -i "${_BOOTMGR_LABEL}" | cut -b5-8) ; do
    efibootmgr --quiet --bootnum "\${_bootnum}" --delete-bootnum
done
if [[ "\${_BOOTMGR_LOADER_PARAMETERS}" != "" ]]; then
    efibootmgr --quiet --create --disk "${_BOOTMGR_DISC}" --part "${_BOOTMGR_PART_NUM}" --loader "${_BOOTMGR_LOADER_PATH}" --label "${_BOOTMGR_LABEL}" --unicode "\${_BOOTMGR_LOADER_PARAMETERS}" -e "3"
else
    efibootmgr --quiet --create --disk "${_BOOTMGR_DISC}" --part "${_BOOTMGR_PART_NUM}" --loader "${_BOOTMGR_LOADER_PATH}" --label "${_BOOTMGR_LABEL}" -e "3"
fi
EFIBEOF
        chmod a+x "/tmp/efibootmgr_run.sh"
        /tmp/efibootmgr_run.sh &>"/tmp/efibootmgr_run.log"
    else
        DIALOG --msgbox "Boot entry could not be created. Check whether you have booted in UEFI boot mode and create a boot entry for ${UEFISYS_MP}/${_EFIBOOTMGR_LOADER_PATH} using efibootmgr." 0 0
    fi
}

do_apple_efi_hfs_bless() {
    ## Grub upstream bzr mactel branch => http://bzr.savannah.gnu.org/lh/grub/branches/mactel/changes
    ## Fedora's mactel-boot => https://bugzilla.redhat.com/show_bug.cgi?id=755093
    DIALOG --msgbox "TODO: Apple Mac EFI Bootloader Setup" 0 0
}

do_uefi_bootmgr_setup() {
    _uefisysdev="$(findmnt -vno SOURCE "${_DESTDIR}/${UEFISYS_MP}")"
    _DISC="$(${_LSBLK} KNAME "${_uefisysdev}")"
    UEFISYS_PART_NUM="$(${_BLKID} -p -i -s PART_ENTRY_NUMBER -o value "${_uefisysdev}")"
    _BOOTMGR_DISC="${_DISC}"
    _BOOTMGR_PART_NUM="${UEFISYS_PART_NUM}"
    if [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Inc.' ]] || [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Computer, Inc.' ]]; then
        do_apple_efi_hfs_bless
    else
        do_uefi_efibootmgr
    fi
}

do_uefi_secure_boot_efitools() {
    do_uefi_common
    # install helper tools and create entries in UEFI boot manager, if not present
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        if [[ ! -f "${UEFISYS_MP}/EFI/BOOT/HashTool.efi" ]]; then
            cp "${_DESTDIR}/usr/share/efitools/efi/HashTool.efi" "${UEFISYS_MP}/EFI/BOOT/HashTool.efi"
            _BOOTMGR_LABEL="HashTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/HashTool.efi"
            do_uefi_bootmgr_setup
        fi
        if [[ ! -f "${UEFISYS_MP}/EFI/BOOT/KeyTool.efi" ]]; then
            cp "${_DESTDIR}/usr/share/efitools/efi/KeyTool.efi" "${UEFISYS_MP}/EFI/BOOT/KeyTool.efi"
            _BOOTMGR_LABEL="KeyTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/KeyTool.efi"
            do_uefi_bootmgr_setup
        fi
    fi
}

do_secureboot_keys() {
    CN=""
    MOK_PW=""
    KEYDIR=""
    while [[ "${KEYDIR}" == "" ]]; do
        DIALOG --inputbox "Setup keys:\nEnter the directory to store the keys on ${_DESTDIR}." 9 65 "/etc/secureboot/keys" 2>"${_ANSWER}" || return 1
        KEYDIR=$(cat "${_ANSWER}")
        #shellcheck disable=SC2086,SC2001
        KEYDIR="$(echo ${KEYDIR} | sed -e 's#^/##g')"
    done
    if [[ ! -d "${_DESTDIR}/${KEYDIR}" ]]; then
        while [[ "${CN}" == "" ]]; do
            DIALOG --inputbox "Setup keys:\nEnter a common name(CN) for your keys, eg. Your Name" 8 65 "" 2>"${_ANSWER}" || return 1
            CN=$(cat "${_ANSWER}")
        done
        secureboot-keys.sh -name="${CN}" "${_DESTDIR}/${KEYDIR}" > "${LOG}" 2>&1 || return 1
         DIALOG --infobox "Setup keys created:\n\nCommon name(CN) ${CN}\nused for your keys in ${_DESTDIR}/${KEYDIR}\n\nContinuing in 10 seconds ..." 8 60
         sleep 10
    else
         DIALOG --infobox "Setup keys:\n-Directory ${_DESTDIR}/${KEYDIR} exists\n-assuming keys are already created\n-trying to use existing keys now\n\nContinuing in 10 seconds ..." 8 50
         sleep 10
    fi
}

do_mok_sign () {
    UEFI_BOOTLOADER_DIR="${UEFISYS_MP}/EFI/BOOT"
    INSTALL_MOK=""
    MOK_PW=""
    DIALOG --yesno "Do you want to install the MOK certificate to the UEFI keys?" 5 65 && INSTALL_MOK="1"
    if [[ "${INSTALL_MOK}" == "1" ]]; then
        while [[ "${MOK_PW}" == "" ]]; do
            DIALOG --insecure --passwordbox "Enter a one time MOK password for SHIM on reboot:" 8 65 2>"${_ANSWER}" || return 1
            PASS=$(cat "${_ANSWER}")
            DIALOG --insecure --passwordbox "Retype one time MOK password:" 8 65 2>"${_ANSWER}" || return 1
            PASS2=$(cat "${_ANSWER}")
            if [[ "${PASS}" == "${PASS2}" && -n "${PASS}" ]]; then
                MOK_PW=${PASS}
                echo "${MOK_PW}" > /tmp/.password
                echo "${MOK_PW}" >> /tmp/.password
                MOK_PW=/tmp/.password
            else
                DIALOG --msgbox "Password didn't match or was empty, please enter again." 6 65
            fi
        done
        mokutil -i "${_DESTDIR}"/"${KEYDIR}"/MOK/MOK.cer < ${MOK_PW} > "${LOG}"
        rm /tmp/.password
        DIALOG --infobox "MOK keys have been installed successfully.\n\nContinuing in 5 seconds ..." 5 50
        sleep 5
    fi
    SIGN_MOK=""
    DIALOG --yesno "Do you want to sign with the MOK certificate?\n\n/boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi" 7 55 && SIGN_MOK="1"
    if [[ "${SIGN_MOK}" == "1" ]]; then
        if [[ "${_DESTDIR}" == "/install" ]]; then
            systemd-nspawn -q -D "${_DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output /boot/"${VMLINUZ}" /boot/"${VMLINUZ}" > "${LOG}" 2>&1
            systemd-nspawn -q -D "${_DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output "${UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi "${UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi > "${LOG}" 2>&1
        else
            sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output /boot/"${VMLINUZ}" /boot/"${VMLINUZ}" > "${LOG}" 2>&1
            sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output "${UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi "${UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi > "${LOG}" 2>&1
        fi
        DIALOG --infobox "/boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi\n\nbeen signed successfully.\n\nContinuing in 5 seconds ..." 7 60
        sleep 5
    fi
}

do_pacman_sign() {
    SIGN_KERNEL=""
    DIALOG --yesno "Do you want to install a pacman hook\nfor automatic signing /boot/${VMLINUZ} on updates?" 6 60 && SIGN_KERNEL="1"
    if [[ "${SIGN_KERNEL}" == "1" ]]; then
        [[ ! -d "${_DESTDIR}/etc/pacman.d/hooks" ]] &&  mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks/
        HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
        cat << EOF > "${HOOKNAME}"
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbverify --list {} 2>/dev/null | /usr/bin/grep -q "signature certificates"; then /usr/bin/sbsign --key /${KEYDIR}/MOK/MOK.key --cert /${KEYDIR}/MOK/MOK.crt --output {} {}; fi' ;
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF
        DIALOG --infobox "Pacman hook for automatic signing has been installed successfully:\n\n${HOOKNAME}\n\nContinuing in 5 seconds ..." 7 70
        sleep 5
    fi
}

do_efistub_parameters() {
    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    UEFISYS_PATH="EFI/archlinux"
    _bootdev="$(findmnt -vno SOURCE "${_DESTDIR}/boot")"
    _uefisysdev="$(findmnt -vno SOURCE "${_DESTDIR}/${UEFISYS_MP}")"
    UEFISYS_PART_FS_UUID="$(getfsuuid "${_uefisysdev}")"
    if [[ "${UEFISYS_MP}" == "/boot" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _KERNEL="${VMLINUZ_EFISTUB}"
        else
            _KERNEL="${VMLINUZ}"
            if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
                _INITRD_INTEL_UCODE="${INTEL_UCODE}"
            fi
        fi
        if [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "x86_64" ]]; then
            _INITRD_AMD_UCODE="${AMD_UCODE}"
        fi
        _INITRD="${INITRAMFS}"
    else
        # name .efi for uefisys partition
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _KERNEL="${UEFISYS_PATH}/${VMLINUZ_EFISTUB}"
        else
            _KERNEL="${UEFISYS_PATH}/${VMLINUZ}"
            if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
                _INITRD_INTEL_UCODE="${UEFISYS_PATH}/${INTEL_UCODE}"
            fi
        fi
        if [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "x86_64" ]]; then
            _INITRD_AMD_UCODE="${UEFISYS_PATH}/${AMD_UCODE}"
        fi
        _INITRD="${UEFISYS_PATH}/${INITRAMFS}"
    fi
}

do_efistub_copy_to_efisys() {
    if ! [[ "${UEFISYS_MP}" == "/boot" ]]; then
        # clean and copy to efisys
        DIALOG --infobox "Copying kernel, ucode and initramfs to EFI system partition now ..." 4 50
        ! [[ -d "${_DESTDIR}/${UEFISYS_MP}/${UEFISYS_PATH}" ]] && mkdir -p "${_DESTDIR}/${UEFISYS_MP}/${UEFISYS_PATH}"
        rm -f "${_DESTDIR}/${UEFISYS_MP}/${_KERNEL}"
        cp -f "${_DESTDIR}/boot/${VMLINUZ}" "${_DESTDIR}/${UEFISYS_MP}/${_KERNEL}"
        rm -f "${_DESTDIR}/${UEFISYS_MP}/${_INITRD}"
        cp -f "${_DESTDIR}/boot/${INITRAMFS}" "${_DESTDIR}/${UEFISYS_MP}/${_INITRD}"
        if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
            rm -f "${_DESTDIR}/${UEFISYS_MP}/${_INITRD_INTEL_UCODE}"
            cp -f "${_DESTDIR}/boot/${INTEL_UCODE}" "${_DESTDIR}/${UEFISYS_MP}/${_INITRD_INTEL_UCODE}"
        fi
        if [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "x86_64" ]]; then
            rm -f "${_DESTDIR}/${UEFISYS_MP}/${_INITRD_AMD_UCODE}"
            cp -f "${_DESTDIR}/boot/${AMD_UCODE}" "${_DESTDIR}/${UEFISYS_MP}/${_INITRD_AMD_UCODE}"
        fi
        sleep 5
        DIALOG --infobox "Enable automatic copying of system files to EFI system partition on installed system ..." 4 50
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Path]
PathChanged=/boot/${VMLINUZ}
PathChanged=/boot/${INITRAMFS}
CONFEOF
        [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "x86_64" ]] && \
            echo "PathChanged=/boot/${AMD_UCODE}" >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
        [[ "${RUNNING_ARCH}" == "x86_64" ]] && \
            echo "PathChanged=/boot/${INTEL_UCODE}" >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
        cat << CONFEOF >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
Unit=efistub_copy.service
[Install]
WantedBy=multi-user.target
CONFEOF
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Service]
Type=oneshot
ExecStart=/usr/bin/cp -f /boot/${VMLINUZ} ${UEFISYS_MP}/${_KERNEL}
ExecStart=/usr/bin/cp -f /boot/${INITRAMFS} ${UEFISYS_MP}/${_INITRD}
CONFEOF
        [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "x86_64" ]] && \
            echo "ExecStart=/usr/bin/cp -f /boot/${AMD_UCODE} ${UEFISYS_MP}/${_INITRD_AMD_UCODE}" \
            >> "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
        [[ "${RUNNING_ARCH}" == "x86_64" ]] && \
            echo "ExecStart=/usr/bin/cp -f /boot/${INTEL_UCODE} ${UEFISYS_MP}/${_INITRD_INTEL_UCODE}" \
            >> "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
        if [[ "${_DESTDIR}" == "/install" ]]; then
            systemd-nspawn -q -D "${_DESTDIR}" systemctl enable efistub_copy.path >/dev/null 2>&1
        else
            systemctl enable efistub_copy.path >/dev/null 2>&1
        fi
        sleep 5
    fi
}

do_efistub_uefi() {
    do_uefi_common
    do_efistub_parameters
    common_bootloader_checks
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        do_systemd_boot_uefi
    else
        DIALOG --menu "Select which UEFI Boot Manager to install, to provide a menu for the EFISTUB kernels?" 10 55 2 \
            "SYSTEMD-BOOT" "SYSTEMD-BOOT for ${_UEFI_ARCH} UEFI" \
            "rEFInd" "rEFInd for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
        case $(cat "${_ANSWER}") in
            "SYSTEMD-BOOT") do_systemd_boot_uefi ;;
            "rEFInd") do_refind_uefi ;;
        esac
    fi
}

do_systemd_boot_uefi() {
    DIALOG --infobox "Setting up SYSTEMD-BOOT now ..." 3 40
    # create directory structure, if it doesn't exist
    ! [[ -d "${_DESTDIR}/${UEFISYS_MP}/loader/entries" ]] && mkdir -p "${_DESTDIR}/${UEFISYS_MP}/loader/entries"
    echo "title    Arch Linux" > "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    echo "linux    /${_KERNEL}" >> "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    [[ "${RUNNING_ARCH}" == "x86_64" ]] && \
        echo "initrd   /${_INITRD_INTEL_UCODE}" >> "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    [[ "${RUNNING_ARCH}" == "x86_64"  || "${RUNNING_ARCH}" == "aarch64" ]] && \
        echo "initrd   /${_INITRD_AMD_UCODE}" >> "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    cat << GUMEOF >> "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
initrd   /${_INITRD}
options  ${_KERNEL_PARAMS_MOD}
GUMEOF
    cat << GUMEOF > "${_DESTDIR}/${UEFISYS_MP}/loader/loader.conf"
timeout 5
default archlinux-core-main
GUMEOF
    chroot_mount
    chroot "${_DESTDIR}" bootctl --path="${UEFISYS_MP}" install >"${LOG}" 2>&1
    chroot "${_DESTDIR}" bootctl --path="${UEFISYS_MP}" update >"${LOG}" 2>&1
    chroot_umount
    if [[ -e "${_DESTDIR}/${UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        rm -f "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi"  \
              "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        DIALOG --msgbox "You will now be put into the editor to edit:\nloader.conf and menu entry files\n\nAfter you save your changes, exit the editor." 8 50
        geteditor || return 1
        "${EDITOR}" "${_DESTDIR}/${UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
        "${EDITOR}" "${_DESTDIR}/${UEFISYS_MP}/loader/loader.conf"
        DIALOG --infobox "SYSTEMD-BOOT has been setup successfully.\nContinuing in 5 seconds ..." 4 50
        sleep 5
        S_BOOTLOADER="1"
    else
        DIALOG --msgbox "Error installing SYSTEMD-BOOT ..." 0 0
    fi
}

do_refind_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/bin/refind-install" ]]; then
        DIALOG --infobox "Installing refind ..." 0 0
        PACKAGES="refind"
        run_pacman
    fi
    DIALOG --infobox "Setting up rEFInd now. This needs some time ..." 3 60
    ! [[ -d "${_DESTDIR}/${UEFISYS_MP}/EFI/refind" ]] && mkdir -p "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/"
    cp -f "${_DESTDIR}/usr/share/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/icons" "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/fonts" "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/drivers_${_SPEC_UEFI_ARCH}" "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/"
    _REFIND_CONFIG="${_DESTDIR}/${UEFISYS_MP}/EFI/refind/refind.conf"
    cat << CONFEOF > "${_REFIND_CONFIG}"
timeout 20
use_nvram false
resolution 1024 768
scanfor manual,internal,external,optical,firmware
menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    loader   /${_KERNEL}
CONFEOF
    [[ "${RUNNING_ARCH}" == "x86_64" ]] && \
        echo "    initrd   /${_INITRD_INTEL_UCODE}" >> "${_REFIND_CONFIG}"
    [[ "${RUNNING_ARCH}" == "x86_64"  || "${RUNNING_ARCH}" == "aarch64" ]] && \
        echo "    initrd   /${_INITRD_AMD_UCODE}" >> "${_REFIND_CONFIG}"
    cat << CONFEOF >> "${_REFIND_CONFIG}"
    initrd   /${_INITRD}
    options  "${_KERNEL_PARAMS_MOD}"
}
CONFEOF
    if [[ -e "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        _BOOTMGR_LABEL="rEFInd"
        _BOOTMGR_LOADER_DIR="/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        DIALOG --msgbox "You will now be put into the editor to edit:\nrefind.conf\n\nAfter you save your changes, exit the editor." 8 50
        geteditor || return 1
        "${EDITOR}" "${_REFIND_CONFIG}"
        cp -f "${_REFIND_CONFIG}" "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/"
        DIALOG --infobox "rEFInd has been setup successfully.\nContinuing in 5 seconds ..." 4 50
        sleep 5
        S_BOOTLOADER="1"
    else
        DIALOG --msgbox "Error setting up rEFInd." 3 40
    fi
}

do_grub_common_before() {
    ##### Check whether the below limitations still continue with ver 2.00~beta4
    ### Grub(2) restrictions:
    ## - Encryption is not recommended for grub(2) /boot!
    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    common_bootloader_checks
    abort_f2fs_bootpart || return 1
    if ! dmraid -r | grep -q ^no; then
        DIALOG --yesno "Setup detected dmraid device.\nDo you want to install grub on this device?" 6 50 && USE_DMRAID="1"
    fi
    if [[ ! -d "${_DESTDIR}/usr/lib/grub" ]]; then
        DIALOG --infobox "Installing grub ..." 0 0
        PACKAGES="grub"
        run_pacman
    fi
}

do_grub_config() {
    chroot_mount
    BOOT_PART_FS_UUID="$(chroot "${_DESTDIR}" grub-probe --target="fs_uuid" "/boot" 2>/dev/null)"
    BOOT_PART_FS_LABEL="$(chroot "${_DESTDIR}" grub-probe --target="fs_label" "/boot" 2>/dev/null)"
    BOOT_PART_HINTS_STRING="$(chroot "${_DESTDIR}" grub-probe --target="hints_string" "/boot" 2>/dev/null)"
    BOOT_PART_FS="$(chroot "${_DESTDIR}" grub-probe --target="fs" "/boot" 2>/dev/null)"
    BOOT_PART_DRIVE="$(chroot "${_DESTDIR}" grub-probe --target="drive" "/boot" 2>/dev/null)"
    ROOT_PART_FS_UUID="$(chroot "${_DESTDIR}" grub-probe --target="fs_uuid" "/" 2>/dev/null)"
    ROOT_PART_HINTS_STRING="$(chroot "${_DESTDIR}" grub-probe --target="hints_string" "/" 2>/dev/null)"
    ROOT_PART_FS="$(chroot "${_DESTDIR}" grub-probe --target="fs" "/" 2>/dev/null)"
    USR_PART_FS_UUID="$(chroot "${_DESTDIR}" grub-probe --target="fs_uuid" "/usr" 2>/dev/null)"
    USR_PART_HINTS_STRING="$(chroot "${_DESTDIR}" grub-probe --target="hints_string" "/usr" 2>/dev/null)"
    USR_PART_FS="$(chroot "${_DESTDIR}" grub-probe --target="fs" "/usr" 2>/dev/null)"
    if [[ "${GRUB_UEFI}" == "1" ]]; then
        UEFISYS_PART_FS_UUID="$(chroot "${_DESTDIR}" grub-probe --target="fs_uuid" "/${UEFISYS_MP}" 2>/dev/null)"
        UEFISYS_PART_HINTS_STRING="$(chroot "${_DESTDIR}" grub-probe --target="hints_string" "/${UEFISYS_MP}" 2>/dev/null)"
    fi
    if [[ "${ROOT_PART_FS_UUID}" == "${BOOT_PART_FS_UUID}" ]]; then
        subdir="/boot"
        # on btrfs we need to check on subvol
        if mount | grep "${_DESTDIR} " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${_DESTDIR}/" | grep Name | cut -c 11-60)"/boot
        fi
        if mount | grep "${_DESTDIR}/boot " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${_DESTDIR}/boot" | grep Name | cut -c 11-60)"
        fi
    else
        subdir=""
        # on btrfs we need to check on subvol
        if mount | grep "${_DESTDIR}/boot " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${_DESTDIR}/boot" | grep Name | cut -c 11-60)"
        fi
    fi
    ## Move old config file, if any
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        GRUB_CFG="grub${_SPEC_UEFI_ARCH}.cfg"
    else
        GRUB_CFG="grub.cfg"
    fi
    [[ -f "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" ]] && (mv "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}.bak" || true)
    ## Ignore if the insmod entries are repeated - there are possibilities of having /boot in one disk and root-fs in altogether different disk
    ## with totally different configuration.
    cat << EOF > "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
if [ "\${grub_platform}" == "efi" ]; then
    set _UEFI_ARCH="\${grub_cpu}"
    if [ "\${grub_cpu}" == "x86_64" ]; then
        set _SPEC_UEFI_ARCH="x64"
    fi
    if [ "\${grub_cpu}" == "i386" ]; then
        set _SPEC_UEFI_ARCH="ia32"
    fi
    if [ "\${grub_cpu}" == "aarch64" ]; then
        set _SPEC_UEFI_ARCH="aa64"
    fi
fi
# Include modules - required for boot
insmod part_gpt
insmod part_msdos
insmod fat
insmod ${BOOT_PART_FS}
insmod ${ROOT_PART_FS}
insmod ${USR_PART_FS}
insmod search_fs_file
insmod search_fs_uuid
insmod search_label
insmod linux
insmod chain
set pager="1"
# set debug="all"
set locale_dir="\${prefix}/locale"
EOF
    [[ "${USE_RAID}" == "1" ]] && echo "insmod raid" >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    ! [[ "${RAID_ON_LVM}" == "" ]] && echo "insmod lvm" >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    #shellcheck disable=SC2129
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
if [ -e "\${prefix}/\${grub_cpu}-\${grub_platform}/all_video.mod" ]; then
    insmod all_video
else
    if [ "\${grub_platform}" == "efi" ]; then
        insmod efi_gop
        insmod efi_uga
    fi
    if [ "\${grub_platform}" == "pc" ]; then
        insmod vbe
        insmod vga
    fi
    insmod video_bochs
    insmod video_cirrus
fi
insmod font
search --fs-uuid --no-floppy --set=usr_part ${USR_PART_HINTS_STRING} ${USR_PART_FS_UUID}
search --fs-uuid --no-floppy --set=root_part ${ROOT_PART_HINTS_STRING} ${ROOT_PART_FS_UUID}
if [ -e "\${prefix}/fonts/unicode.pf2" ]; then
    set _fontfile="\${prefix}/fonts/unicode.pf2"
else
    if [ -e "(\${root_part})/usr/share/grub/unicode.pf2" ]; then
        set _fontfile="(\${root_part})/usr/share/grub/unicode.pf2"
    else
        if [ -e "(\${usr_part})/share/grub/unicode.pf2" ]; then
            set _fontfile="(\${usr_part})/share/grub/unicode.pf2"
        fi
    fi
fi
if loadfont "\${_fontfile}" ; then
    insmod gfxterm
    set gfxmode="auto"

    terminal_input console
    terminal_output gfxterm
fi
EOF
    [[ -e "/tmp/.device-names" ]] && sort "/tmp/.device-names" >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    if [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] ; then
        GRUB_ROOT_DRIVE="search --fs-uuid --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_UUID}"
    else
        if [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] ; then
            GRUB_ROOT_DRIVE="search --label --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_LABEL}"
        else
            GRUB_ROOT_DRIVE="set root=${BOOT_PART_DRIVE}"
        fi
    fi
    if [[ "${GRUB_UEFI}" == "1" ]]; then
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_MOD}"
    else
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_MOD}"
    fi
    LINUX_MOD_COMMAND=$(echo "${LINUX_UNMOD_COMMAND}" | sed -e 's#   # #g' | sed -e 's#  # #g')
    ## create default kernel entry
    NUMBER="0"
if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}
}
EOF
    NUMBER=$((NUMBER+1))
else
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${INTEL_UCODE} ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}
}
EOF
    NUMBER=$((NUMBER+1))
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
if [ "\${grub_platform}" == "efi" ]; then
    ## UEFI Shell
    #menuentry "UEFI Shell \${_UEFI_ARCH} v2" {
    #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
    #    chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v2.efi
    #}
fi
EOF
    NUMBER=$((NUMBER+1))
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
if [ "\${grub_platform}" == "efi" ]; then
    if [ "\${grub_cpu}" == "x86_64" ]; then
        ## Microsoft Windows 10/11 via x86_64 UEFI
        #menuentry Microsoft Windows 10/11 x86_64 UEFI-GPT {
        #    insmod part_gpt
        #    insmod fat
        #    insmod search_fs_uuid
        #    insmod chain
        #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
        #    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        #}
    fi
fi
EOF
    NUMBER=$((NUMBER+1))
    ## TODO: Detect actual Windows installation if any
    ## create example file for windows
    cat << EOF >> "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
if [ "\${grub_platform}" == "pc" ]; then
    ## Microsoft Windows 10/11 BIOS
    #menuentry Microsoft Windows 10/11 BIOS-MBR {
    #    insmod part_msdos
    #    insmod ntfs
    #    insmod search_fs_uuid
    #    insmod ntldr
    #    search --fs-uuid --no-floppy --set=root <FS_UUID of Windows SYSTEM Partition>
    #    ntldr /bootmgr
    #}
fi
EOF
fi
    ## copy unicode.pf2 font file
    cp -f "${_DESTDIR}/usr/share/grub/unicode.pf2" "${_DESTDIR}/${GRUB_PREFIX_DIR}/fonts/unicode.pf2"
    chroot_umount
    ## Edit grub.cfg config file
    DIALOG --msgbox "You must now review the GRUB(2) configuration file.\n\nYou will now be put into the editor.\nAfter you save your changes, exit the editor." 8 55
    geteditor || return 1
    "${EDITOR}" "${_DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
}

do_uboot() {
    common_bootloader_checks
    check_bootpart
    abort_uboot
    [[ -d "${_DESTDIR}/boot/extlinux" ]] || mkdir -p "${_DESTDIR}/boot/extlinux"
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_rootpart} rootfstype=${ROOTFS} rw ${ROOTFLAGS} ${RAIDARRAYS} ${CRYPTSETUP}"
    _KERNEL_PARAMS_COMMON_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    [[ "${RUNNING_ARCH}" == "aarch64" ]] && _TITLE="ARM 64"
    [[ "${RUNNING_ARCH}" == "riscv64" ]] && _TITLE="RISC-V 64"
    # write extlinux.conf
    DIALOG --infobox "Installing UBOOT ..." 0 0
    cat << EOF >> "${_DESTDIR}/boot/extlinux/extlinux.conf"
menu title Welcome Arch Linux ${_TITLE}
timeout 100
default linux
label linux
    menu label Boot System (automatic boot in 10 seconds ...)
    kernel ${subdir}/${VMLINUZ}
    initrd ${subdir}/${INITRAMFS}
    append ${_KERNEL_PARAMS_COMMON_MOD}
EOF
    DIALOG --infobox "UBOOT has been installed successfully.\n\nContinuing in 5 seconds ..." 5 55
    sleep 5
    S_BOOTLOADER="1"
}

do_grub_bios() {
    do_grub_common_before
    # try to auto-configure GRUB(2)...
    check_bootpart
    # check if raid, raid partition, dmraid or device devicemapper is used
    if echo "${bootdev}" | grep -q /dev/md || echo "${bootdev}" | grep /dev/mapper; then
        # boot from lvm, raid, partitioned raid and dmraid devices is supported
        FAIL_COMPLEX="0"
        if cryptsetup status "${bootdev}"; then
            # encryption devices are not supported
            FAIL_COMPLEX="1"
        fi
    fi
    if [[ "${FAIL_COMPLEX}" == "0" ]]; then
        # check if mapper is used
        if  echo "${bootdev}" | grep -q /dev/mapper; then
            RAID_ON_LVM="0"
            #check if mapper contains a md device!
            for devpath in $(pvs -o pv_name --noheading); do
                if echo "${devpath}" | grep -v "/dev/md.p" | grep /dev/md; then
                    detectedvolumegroup="$(pvs -o vg_name --noheading "${devpath}")"
                    if echo /dev/mapper/"${detectedvolumegroup}"-* | grep "${bootdev}"; then
                        # change bootdev to md device!
                        bootdev=$(pvs -o pv_name --noheading "${devpath}")
                        RAID_ON_LVM="1"
                        break
                    fi
                fi
            done
        fi
        #check if raid is used
        USE_RAID=""
        if echo "${bootdev}" | grep -q /dev/md; then
            USE_RAID="1"
        fi
    fi
    # A switch is needed if complex ${bootdev} is used!
    # - LVM and RAID ${bootdev} needs the MBR of a device and cannot be used itself as ${bootdev}
    # -  grub BIOS install to partition is not supported
    DEVS="$(findbootloaderdisks _)"
    if [[ "${DEVS}" == "" ]]; then
        DIALOG --msgbox "No storage drives were found" 0 0
        return 1
    fi
    #shellcheck disable=SC2086
    DIALOG --menu "Select the boot device where the GRUB(2) bootloader will be installed." 14 55 7 ${DEVS} 2>"${_ANSWER}" || return 1
    bootdev=$(cat "${_ANSWER}")
    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${bootdev}")" == "gpt" ]]; then
        CHECK_BIOS_BOOT_GRUB="1"
        CHECK_UEFISYS_PART=""
        RUN_CFDISK=""
        DISC="${bootdev}"
        check_gpt
    else
        if [[ "${FAIL_COMPLEX}" == "0" ]]; then
            DIALOG --defaultno --yesno "Warning:\nSetup detected no GUID (gpt) partition table.\n\nGrub(2) has only space for approx. 30k core.img file. Depending on your setup, it might not fit into this gap and fail.\n\nDo you really want to install GRUB(2) to a msdos partition table?" 0 0 || return 1
        fi
    fi
    if [[ "${FAIL_COMPLEX}" == "1" ]]; then
        DIALOG --msgbox "Error:\nGRUB(2) cannot boot from ${bootdev}, which contains /boot!\n\nPossible error sources:\n- encrypted devices are not supported" 0 0
        return 1
    fi
    DIALOG --infobox "Setting up GRUB(2) BIOS. This needs some time ..." 3 55
    # freeze and unfreeze xfs filesystems to enable grub(2) installation on xfs filesystems
    freeze_xfs
    chroot_mount
    chroot "${_DESTDIR}" grub-install \
        --directory="/usr/lib/grub/i386-pc" \
        --target="i386-pc" \
        --boot-directory="/boot" \
        --recheck \
        --debug \
        "${bootdev}" &>"/tmp/grub_bios_install.log"
    chroot_umount
    mkdir -p "${_DESTDIR}/boot/grub/locale"
    cp -f "${_DESTDIR}/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "${_DESTDIR}/boot/grub/locale/en.mo"
    if [[ -e "${_DESTDIR}/boot/grub/i386-pc/core.img" ]]; then
        GRUB_PREFIX_DIR="/boot/grub/"
        do_grub_config
        DIALOG --infobox "GRUB(2) BIOS has been installed successfully.\n\nContinuing in 5 seconds ..." 5 55
        sleep 5
        S_BOOTLOADER="1"
    else
        DIALOG --msgbox "Error installing GRUB(2) BIOS.\nCheck /tmp/grub_bios_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${_DESTDIR}.\nDon't forget to bind mount /dev and /proc into ${_DESTDIR} before chrooting." 0 0
        return 1
    fi
}

do_grub_uefi() {
    do_uefi_common
    [[ "${_UEFI_ARCH}" == "X64" ]] && _GRUB_ARCH="x86_64"
    [[ "${_UEFI_ARCH}" == "IA32" ]] && _GRUB_ARCH="i386"
    [[ "${_UEFI_ARCH}" == "AA64" ]] && _GRUB_ARCH="arm64"
    do_grub_common_before
    DIALOG --infobox "Setting up GRUB(2) UEFI. This needs some time ..." 3 55
    chroot_mount
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        # install fedora shim
        [[ ! -d  ${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT ]] && mkdir -p "${_DESTDIR}"/"${UEFISYS_MP}"/EFI/BOOT/
        cp -f /usr/share/archboot/bootloader/shim"${_SPEC_UEFI_ARCH}".efi "${_DESTDIR}"/"${UEFISYS_MP}"/EFI/BOOT/BOOT"${_UEFI_ARCH}".EFI
        cp -f /usr/share/archboot/bootloader/mm"${_SPEC_UEFI_ARCH}".efi "${_DESTDIR}"/"${UEFISYS_MP}"/EFI/BOOT/
        GRUB_PREFIX_DIR="${UEFISYS_MP}/EFI/BOOT/"
    else
        ## Install GRUB
        chroot "${_DESTDIR}" grub-install \
            --directory="/usr/lib/grub/${_GRUB_ARCH}-efi" \
            --target="${_GRUB_ARCH}-efi" \
            --efi-directory="${UEFISYS_MP}" \
            --bootloader-id="grub" \
            --boot-directory="/boot" \
            --no-nvram \
            --recheck \
            --debug &> "/tmp/grub_uefi_${_UEFI_ARCH}_install.log"
        cat "/tmp/grub_uefi_${_UEFI_ARCH}_install.log" >> "${LOG}"
        GRUB_PREFIX_DIR="/boot/grub/"
    fi
    chroot_umount
    GRUB_UEFI="1"
    do_grub_config
    GRUB_UEFI=""
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        # generate GRUB with config embeded
        #remove existing, else weird things are happening
        [[ -f "${_DESTDIR}/${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" ]] && rm "${_DESTDIR}"/"${GRUB_PREFIX_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        # add -v for verbose
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
                if [[ "${_DESTDIR}" == "/install" ]]; then
                    systemd-nspawn -q -D "${_DESTDIR}" grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
                else
                    grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
                fi
        elif [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
                if [[ "${_DESTDIR}" == "/install" ]]; then
                    systemd-nspawn -q -D "${_DESTDIR}" grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
                else
                    grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
                fi
        fi
        cp /"${GRUB_PREFIX_DIR}"/"${GRUB_CFG}" "${UEFISYS_MP}"/EFI/BOOT/grub"${_SPEC_UEFI_ARCH}".cfg
    fi
    if [[ -e "${_DESTDIR}/${UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" && "${_UEFI_SECURE_BOOT}" == "0" && -e "${_DESTDIR}/boot/grub/${_GRUB_ARCH}-efi/core.efi" ]]; then
        _BOOTMGR_LABEL="GRUB"
        _BOOTMGR_LOADER_DIR="/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        DIALOG --infobox "GRUB(2) for ${_UEFI_ARCH} UEFI has been installed successfully.\n\nContinuing in 5 seconds ..." 5 60
        sleep 5
        S_BOOTLOADER="1"
    elif [[ -e "${_DESTDIR}/${UEFISYS_MP}/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.efi" && "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        do_secureboot_keys || return 1
        do_mok_sign
        do_pacman_sign
        do_uefi_secure_boot_efitools
        _BOOTMGR_LABEL="SHIM with GRUB Secure Boot"
        _BOOTMGR_LOADER_DIR="/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        do_uefi_bootmgr_setup
        DIALOG --infobox "SHIM and GRUB(2) Secure Boot for ${_UEFI_ARCH} UEFI\nhas been installed successfully.\n\nContinuing in 5 seconds ..." 6 50
        sleep 5
        S_BOOTLOADER="1"
    else
        DIALOG --msgbox "Error installing GRUB(2) for ${_UEFI_ARCH} UEFI.\nCheck /tmp/grub_uefi_${_UEFI_ARCH}_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${_DESTDIR}.\nDon't forget to bind mount /dev, /sys and /proc into ${_DESTDIR} before chrooting." 0 0
        return 1
    fi
}

install_bootloader_uefi() {
    if [[ "${_EFI_MIXED}" == "1" ]]; then
        _EFISTUB_MENU_LABEL=""
        _EFISTUB_MENU_TEXT=""
    else
        _EFISTUB_MENU_LABEL="EFISTUB"
        _EFISTUB_MENU_TEXT="EFISTUB for ${_UEFI_ARCH} UEFI"
    fi
    if [[ "${_UEFI_SECURE_BOOT}" == "1" ]]; then
        do_grub_uefi
    else
        DIALOG --menu "Which ${_UEFI_ARCH} UEFI bootloader would you like to use?" 9 55 3 \
            "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
            "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
        case $(cat "${_ANSWER}") in
            "EFISTUB") do_efistub_uefi
                       [[ -z "${S_BOOTLOADER}" ]] || do_efistub_copy_to_efisys
                        ;;
            "GRUB_UEFI") do_grub_uefi ;;
        esac
    fi
}

install_bootloader() {
    S_BOOTLOADER=""
    destdir_mounts || return 1
    if [[ "${NAME_SCHEME_PARAMETER_RUN}" == "" ]]; then
        set_device_name_scheme || return 1
    fi
    if [[ "${S_SRC}" == "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman
    if [[ "${_UEFI_BOOT}" == "1" ]]; then
        install_bootloader_uefi
    else
        if [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "riscv64" ]]; then
            do_uboot
        else
            do_grub_bios
        fi
    fi
    if [[ -z "${S_BOOTLOADER}" ]]; then
        NEXTITEM="7"
    else
        NEXTITEM="8"
    fi
}
