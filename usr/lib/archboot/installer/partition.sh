#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_check_gpt() {
    _GUID_DETECTED=""
    [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_DISK}")" == "gpt" ]] && _GUID_DETECTED=1
    if [[ -z "${_GUID_DETECTED}" ]]; then
        _dialog --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${_DISK}.\n\nDo you want to convert the existing MBR table in ${_DISK} to a GUID (gpt) partition table?" 0 0 || return 1
        sgdisk --mbrtogpt "${_DISK}" >"${_LOG}" && _GUID_DETECTED=1
        # reread partitiontable for kernel
        partprobe "${_DISK}" >"${_LOG}"
        if [[ -z "${_GUID_DETECTED}" ]]; then
            _dialog --defaultno --yesno "Conversion failed on ${_DISK}.\nSetup detected no GUID (gpt) partition table on ${_DISK}.\n\nDo you want to create a new GUID (gpt) table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
            _clean_disk "${_DISK}"
            # create fresh GPT
            sgdisk --clear "${_DISK}" &>"${_NO_LOG}"
            _RUN_CFDISK=1
            _GUID_DETECTED=1
        fi
    fi
    if [[ -n "${_GUID_DETECTED}" ]]; then
        if [[ -n "${_CHECK_BIOS_BOOT_GRUB}" ]]; then
            if ! sgdisk -p "${_DISK}" | grep -q 'EF02'; then
                _dialog --msgbox "Setup detected no BIOS BOOT PARTITION in ${_DISK}. Please create a >=1M BIOS BOOT PARTITION for grub BIOS GPT support." 0 0
                _RUN_CFDISK=1
            fi
        fi
    fi
    if [[ -n "${_RUN_CFDISK}" ]]; then
        _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/guid-partition.txt)" 0 0
        clear
        cfdisk "${_DISK}"
        _RUN_CFDISK=""
        # reread partitiontable for kernel
        partprobe "${_DISK}"
    fi
}

_partition() {
    # stop special devices, else weird things can happen during partitioning
    _stopluks
    _stoplvm
    _stopmd
    _set_guid
    # Select disk to partition
    _DISKS=$(_finddisks)
    _DISKS="${_DISKS} OTHER _ DONE +"
    _DISK=""
    while true; do
        # Prompt the user with a list of known disks
        #shellcheck disable=SC2086
        _dialog --cancel-label "Back" --menu "Select the device you want to partition:" 14 45 7 ${_DISKS} 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
        if [[ "${_DISK}" == "OTHER" ]]; then
            _dialog --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>"${_ANSWER}" || _DISK=""
            _DISK=$(cat "${_ANSWER}")
        fi
        # Leave our loop if the user is done partitioning
        [[ "${_DISK}" == "DONE" ]] && break
        _MSDOS_DETECTED=""
        if [[ -n "${_DISK}" ]]; then
            if [[ -n "${_GUIDPARAMETER}" ]]; then
                _CHECK_BIOS_BOOT_GRUB=""
                _RUN_CFDISK=1
                _check_gpt
            else
                [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_DISK}")" == "dos" ]] && _MSDOS_DETECTED=1

                if [[ -z "${_MSDOS_DETECTED}" ]]; then
                    _dialog --defaultno --yesno "Setup detected no MBR/BIOS partition table on ${_DISK}.\nDo you want to create a MBR/BIOS partition table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
                   _clean_disk "${_DISK}"
                    parted -a optimal -s "${_DISK}" mktable msdos >"${_LOG}"
                fi
                # Partition disc
                _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/mbr-partition.txt)" 0 0
                clear
                cfdisk "${_DISK}"
                # reread partitiontable for kernel
                partprobe "${_DISK}"
            fi
        fi
    done
    _NEXTITEM="3"
}
# vim: set ft=sh ts=4 sw=4 et:
