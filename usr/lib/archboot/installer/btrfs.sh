#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# scan and update btrfs devices
btrfs_scan() {
    btrfs device scan >/dev/null 2>&1
}

# mount btrfs for checks
mount_btrfs() {
    btrfs_scan
    _BTRFSMP="$(mktemp -d /tmp/brtfsmp.XXXX)"
    mount "${_PART}" "${_BTRFSMP}"
}

# unmount btrfs after checks done
umount_btrfs() {
    umount "${_BTRFSMP}"
    rm -r "${_BTRFSMP}"
}

# Set _BTRFS_DEVICES on detected btrfs devices
find_btrfs_raid_devices() {
    btrfs_scan
    if [[ "${_DETECT_CREATE_FILESYSTEM}" == "no" && "${_FSTYPE}" == "btrfs" ]]; then
        for i in $(btrfs filesystem show "${_PART}" | cut -d " " -f 11); do
            _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
        done
    fi
}

find_btrfs_raid_bootloader_devices() {
    btrfs_scan
    _BTRFS_COUNT=1
    if [[ "$(${_LSBLK} _FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_DEVICES=""
        for i in $(btrfs filesystem show "${_BOOTDEV}" | cut -d " " -f 11); do
            _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
            _BTRFS_COUNT=$((_BTRFS_COUNT+1))
        done
    fi
}

# find btrfs subvolume
find_btrfs_subvolume() {
    if [[ "${_DETECT_CREATE_FILESYSTEM}" == "no" ]]; then
        # existing btrfs subvolumes
        mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 9 | grep -v 'var/lib/machines' | grep -v '/var/lib/portables'); do
            echo "${i}"
            [[ "${1}" ]] && echo "${1}"
        done
        umount_btrfs
    fi
}

find_btrfs_bootloader_subvolume() {
    if [[ "$(${_LSBLK} _FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_SUBVOLUMES=""
        _PART="${_BOOTDEV}"
        mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 7); do
            _BTRFS_SUBVOLUMES="${_BTRFS_SUBVOLUMES}#${i}"
        done
        umount_btrfs
    fi
}

# subvolumes already in use
subvolumes_in_use() {
    _SUBVOLUME_IN_USE=""
    while read -r i; do
        echo "${i}" | grep -q ":btrfs:" && _SUBVOLUME_IN_USE="${_SUBVOLUME_IN_USE} $(echo "${i}" | cut -d: -f 9)"
    done < /tmp/.parts
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
check_btrfs_filesystem_creation() {
    _DETECT_CREATE_FILESYSTEM="no"
    _SKIP_FILESYSTEM="no"
    _SKIP_ASK_SUBVOLUME="no"
    #shellcheck disable=SC2013
    for i in $(grep "${_PART}[:#]" /tmp/.parts); do
        if echo "${i}" | grep -q ":btrfs:"; then
            _FSTYPE="btrfs"
            _SKIP_FILESYSTEM="yes"
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | cut -d: -f 4 | grep -q yes && _DETECT_CREATE_FILESYSTEM="yes"
            [[ "${_DETECT_CREATE_FILESYSTEM}" == "yes" ]] && _SKIP_ASK_SUBVOLUME="yes"
        fi
    done
}

# remove devices with no subvolume from list and generate raid device list
btrfs_parts() {
     if [[ -s /tmp/.btrfs-devices ]]; then
         _BTRFS_DEVICES=""
         while read -r i; do
             _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
             # remove device if no subvolume is used!
             [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _PARTS="${_PARTS//${i}\ _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _PARTS="${_PARTS//${_PART}\ _/}"
     fi
}

# choose raid level to use on btrfs device
btrfs_raid_level() {
    _BTRFS_RAIDLEVELS="NONE - raid0 - raid1 - raid5 - raid6 - raid10 - single -"
    _BTRFS_RAID_FINISH=""
    _BTRFS_LEVEL=""
    _BTRFS_DEVICE="${_PART}"
    : >/tmp/.btrfs-devices
    DIALOG --msgbox "BTRFS DATA RAID OPTIONS:\n\nRAID5/6 are for testing purpose. Use with extreme care!\n\nIf you don't need this feature select NONE." 0 0
    while [[ "${_BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        DIALOG --menu "Select the raid data level you want to use:" 14 50 10 ${_BTRFS_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _BTRFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BTRFS_LEVEL}" == "NONE" ]]; then
            echo "${_BTRFS_DEVICE}" >>/tmp/.btrfs-devices
            break
        else
            # take selected device as 1st device, add additional devices in part below.
            select_btrfs_raid_devices
        fi
    done
}

# select btrfs raid devices
select_btrfs_raid_devices () {
    # select the second device to use, no missing option available!
    : >/tmp/.btrfs-devices
    echo "${_BTRFS_DEVICE}" >>/tmp/.btrfs-devices
    #shellcheck disable=SC2001,SC2086
    _BTRFS_PARTS=$(echo ${_PARTS} | sed -e "s#${_BTRFS_DEVICE}\ _##g")
    _RAIDNUMBER=2
    #shellcheck disable=SC2086
    DIALOG --menu "Select device ${_RAIDNUMBER}:" 13 50 10 ${_BTRFS_PARTS} 2>"${_ANSWER}" || return 1
    _BTRFS_PART=$(cat "${_ANSWER}")
    echo "${_BTRFS_PART}" >>/tmp/.btrfs-devices
    while [[ "${_BTRFS_PART}" != "DONE" ]]; do
        _BTRFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
        # RAID5 needs 3 devices
        # RAID6, RAID10 need 4 devices!
        [[ "${_RAIDNUMBER}" -ge 3 && ! "${_BTRFS_LEVEL}" == "raid10" && ! "${_BTRFS_LEVEL}" == "raid6" && ! "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 4 && "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 5 && "${_BTRFS_LEVEL}" == "raid10" || "${_BTRFS_LEVEL}" == "raid6" ]] && _BTRFS_DONE="DONE _"
        # clean loop from used partition and options
        #shellcheck disable=SC2001,SC2086
        _BTRFS_PARTS=$(echo ${_BTRFS_PARTS} | sed -e "s#${_BTRFS_PART}\ _##g")
        # add more devices
        #shellcheck disable=SC2086
        DIALOG --menu "Select device ${_RAIDNUMBER}:" 13 50 10 ${_BTRFS_PARTS} ${_BTRFS_DONE} 2>"${_ANSWER}" || return 1
        _BTRFS_PART=$(cat "${_ANSWER}")
        [[ "${_BTRFS_PART}" == "DONE" ]] && break
        echo "${_BTRFS_PART}" >>/tmp/.btrfs-devices
     done
     # final step ask if everything is ok?
     #shellcheck disable=SC2028
     DIALOG --yesno "Would you like to create btrfs raid data like this?\n\nLEVEL:\n${_BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && _BTRFS_RAID_FINISH="DONE"
}

# prepare new btrfs device
prepare_btrfs() {
    btrfs_raid_level || return 1
    prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
prepare_btrfs_subvolume() {
    _DOSUBVOLUME="no"
    _BTRFS_SUBVOLUME="NONE"
    if [[ "${_SKIP_ASK_SUBVOLUME}" == "no" ]]; then
        DIALOG --defaultno --yesno "Would you like to create a new subvolume on ${_PART}?" 0 0 && _DOSUBVOLUME="yes"
    else
        _DOSUBVOLUME="yes"
    fi
    if [[ "${_DOSUBVOLUME}" == "yes" ]]; then
        _BTRFS_SUBVOLUME="NONE"
        while [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]]; do
            DIALOG --inputbox "Enter the SUBVOLUME name for the device, keep it short\nand use no spaces or special\ncharacters." 10 65 2>"${_ANSWER}" || return 1
            _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
            check_btrfs_subvolume
        done
    else
        _BTRFS_SUBVOLUME="NONE"
    fi
}

# check btrfs subvolume
check_btrfs_subvolume(){
    [[ "${_DOMKFS}" == "yes" && "${_FSTYPE}" == "btrfs" ]] && _DETECT_CREATE_FILESYSTEM="yes"
    if [[ "${_DETECT_CREATE_FILESYSTEM}" == "no" ]]; then
        mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 7); do
            if echo "${i}" | grep -q "${_BTRFS_SUBVOLUME}"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
                _BTRFS_SUBVOLUME="NONE"
            fi
        done
        umount_btrfs
    else
        subvolumes_in_use
        if echo "${_SUBVOLUME_IN_USE}" | grep -Eq "${_BTRFS_SUBVOLUME}"; then
            DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
            _BTRFS_SUBVOLUME="NONE"
        fi
    fi
}

# create btrfs subvolume
create_btrfs_subvolume() {
    mount_btrfs
    btrfs subvolume create "${_BTRFSMP}"/"${_BTRFSSUBVOLUME}" > "${_LOG}"
    # change permission from 700 to 755
    # to avoid warnings during package installation
    chmod 755 "${_BTRFSMP}"/"${_BTRFSSUBVOLUME}"
    umount_btrfs
}

# choose btrfs subvolume from list
choose_btrfs_subvolume () {
    _BTRFS_SUBVOLUME="NONE"
    _SUBVOLUMES_DETECTED="no"
    _SUBVOLUMES=$(find_btrfs_subvolume _)
    # check if subvolumes are present
    [[ -n "${_SUBVOLUMES}" ]] && _SUBVOLUMES_DETECTED="yes"
    subvolumes_in_use
    for i in ${_SUBVOLUME_IN_USE}; do
        #shellcheck disable=SC2001,SC2086
        _SUBVOLUMES="$(echo ${_SUBVOLUMES} | sed -e "s#${i} _##g")"
    done
    if [[ -n "${_SUBVOLUMES}" ]]; then
    #shellcheck disable=SC2086
        DIALOG --menu "Select the subvolume to mount:" 15 50 13 ${_SUBVOLUMES} 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
    else
        if [[ "${_SUBVOLUMES_DETECTED}" == "yes" ]]; then
            DIALOG --msgbox "ERROR: All subvolumes of the device are already in use. Switching to create a new one now." 8 65
            _SKIP_ASK_SUBVOLUME=yes
            prepare_btrfs_subvolume || return 1
        fi
    fi
}

# btrfs subvolume menu
btrfs_subvolume() {
    _FILESYSTEM_FINISH=""
    if [[ "${_FSTYPE}" == "btrfs" && "${_DOMKFS}" == "no" ]]; then
        if [[ "${_ASK_MOUNTPOINTS}" == "1" ]]; then
            # create subvolume if requested
            # choose btrfs subvolume if present
            prepare_btrfs_subvolume || return 1
            if [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]]; then
                choose_btrfs_subvolume || return 1
            fi
        else
            # use device if no subvolume is present
            choose_btrfs_subvolume || return 1
        fi
        btrfs_compress
    fi
    _FILESYSTEM_FINISH="yes"
}

# ask for btrfs compress option
btrfs_compress() {
    _BTRFS_COMPRESS="NONE"
    _BTRFS_COMPRESSLEVELS="zstd - lzo - zlib -"
    if [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]]; then
        DIALOG --yesno "Would you like to compress the data on ${_PART}?" 0 0 && _BTRFS_COMPRESS="compress"
    else
        DIALOG --yesno "Would you like to compress the data on ${_PART} subvolume=${_BTRFS_SUBVOLUME}?" 0 0 && _BTRFS_COMPRESS="compress"
    fi
    if [[ "${_BTRFS_COMPRESS}" == "compress" ]]; then
        #shellcheck disable=SC2086
        DIALOG --menu "Select the compression method you want to use:" 10 50 8 ${_BTRFS_COMPRESSLEVELS} 2>"${_ANSWER}" || return 1
        _BTRFS_COMPRESS="compress=$(cat "${_ANSWER}")"
    fi
}
