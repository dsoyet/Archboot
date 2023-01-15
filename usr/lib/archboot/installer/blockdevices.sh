#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_getfstype()
{
    ${_LSBLK} FSTYPE "${1}"
}

_getfsuuid()
{
    ${_LSBLK} UUID "${1}"
}

_getfslabel()
{
    ${_LSBLK} LABEL "${1}"
}

_getpartuuid()
{
    ${_LSBLK} PARTUUID "${1}"
}

_getpartlabel()
{
    ${_LSBLK} PARTLABEL "${1}"
}

# lists linux blockdevices
_blockdevices() {
     # all available block disk devices
     for dev in $(${_LSBLK} NAME,TYPE | grep "disk$" | cut -d' ' -f1); do
         # exclude checks:
         #- iso9660 devices
         #  (${_LSBLK} FSTYPE ${dev} | grep "iso9660"
         #- fakeraid isw devices
         #  ${_LSBLK} FSTYPE ${dev} | grep "isw_raid_member"
         #- fakeraid ddf devices
         #  ${_LSBLK} FSTYPE ${dev} | grep "ddf_raid_member"
         # - zram devices
         #  echo "${dev}" | grep -q 'zram'
         if ! ${_LSBLK} FSTYPE "${dev}" | grep -q "iso9660" && ! ${_LSBLK} FSTYPE "${dev}" | grep -q "isw_raid_member" && ! ${_LSBLK} FSTYPE "${dev}" | grep -q "ddf_raid_member" && ! echo "${dev}" | grep -q 'zram'; then
             echo "${dev}"
             [[ "${1}" ]] && echo "${1}"
         fi
     done
}

# lists linux blockdevice partitions
_blockdevices_partitions() {
    # all available block devices partitions
    # _printk off needed cause of parted usage
    _printk off
    for part in $(${_LSBLK} NAME,TYPE | grep -v '^/dev/md' | grep "part$"| cut -d' ' -f1); do
        # exclude checks:
        #- part of raid device
        #  ${_LSBLK} FSTYPE ${part} | grep "linux_raid_member"
        #- part of lvm2 device
        #  ${_LSBLK} FSTYPE /dev/${part} | grep "LVM2_member"
        #- part of luks device
        #  ${_LSBLK} FSTYPE /dev/${part} | grep "crypto_LUKS"
        #- extended partition
        #  sfdisk -l 2>/dev/null | grep "${part}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "(LBA)$"
        #- bios_grub partitions
        #  "echo ${part} | grep "[a-z]$(parted -s $(${_LSBLK} PKNAME ${part}) print 2>/dev/null | grep bios_grub | cut -d " " -f 2)$"
        #- iso9660 devices
        #  "${_LSBLK} FSTYPE -s ${part} | grep "iso9660"
        if ! ${_LSBLK} FSTYPE "${part}" | grep -q "linux_raid_member" && ! ${_LSBLK} FSTYPE "${part}" | grep -q "LVM2_member" && ! ${_LSBLK} FSTYPE "${part}" | grep -q "crypto_LUKS" && ! ${_LSBLK} FSTYPE -s "${part}" | grep -q "iso9660" && ! sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" && ! sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" && ! echo "${part}" | grep -q "[a-z]$(parted -s "$(${_LSBLK} PKNAME "${part}" 2>/dev/null)" print 2>/dev/null | grep bios_grub | cut -d " " -f 2)$"; then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    _printk on
}

# list none partitionable raid md devices
_raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "ddf_raid_member"
        if ! ${_LSBLK} FSTYPE "${dev}" | grep -q "LVM2_member" && ! ${_LSBLK} FSTYPE "${dev}" | grep -q "crypto_LUKS" && ! ${_LSBLK} FSTYPE "${dev}" -s | grep -q "isw_raid_member" && ! ${_LSBLK} FSTYPE "${dev}" -s | grep -q "ddf_raid_member" && ! find "$dev"*p* -type f -exec echo {} \; 2>/dev/null; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# lists linux partitionable raid devices partitions
_partitionable_raid_devices_partitions() {
    for part in $(${_LSBLK} NAME,TYPE | grep "part$" | grep "^/dev/md.*p" 2>/dev/null | cut -d' ' -f 1 | sort -u) ; do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${part} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${part} | grep "crypto_LUKS"
        # - extended partition
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "(LBA)$"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "ddf_raid_member"
        if ! ${_LSBLK} FSTYPE "${part}" | grep -q "LVM2_member" && ! ${_LSBLK} FSTYPE "${part}" | grep -q "crypto_LUKS" && ! sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" && ! sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" && ! ${_LSBLK} FSTYPE "${dev}" -s | grep -q "isw_raid_member" && ! ${_LSBLK} FSTYPE "${dev}" -s | grep -q "ddf_raid_member"; then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

_dmraid_devices() {
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE 2>/dev/null | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" | grep "isw_raid_member$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE 2>/dev/null | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" | grep "ddf_raid_member$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

_dmraid_partitions() {
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>/dev/null | grep "isw_raid_member$" | cut -d' ' -f 1; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>/dev/null | grep "ddf_raid_member$" | cut -d' ' -f 1; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# dm_devices
# - show device mapper devices:
#   lvm2 and cryptdevices
_dm_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep -e "lvm$" -e "crypt$" | cut -d' ' -f1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of raid device
        #   ${_LSBLK} FSTYPE ${dev} | grep "linux_raid_member$"
        # - part of running raid on encrypted device
        #   ${_LSBLK} TYPE ${dev} | grep "raid.*$
        if ! ${_LSBLK} FSTYPE "${dev}" | grep -q "crypto_LUKS$" && ! ${_LSBLK} FSTYPE "${dev}" | grep -q "LVM2_member$" && ! ${_LSBLK} FSTYPE "${dev}" | grep -q "linux_raid_member$" && ! ${_LSBLK} TYPE "${dev}" | grep -q "raid.*$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

_finddisks() {
    _blockdevices "${1}"
    _dmraid_devices "${1}"
}

_finddevices() {
    _blockdevices_partitions "${1}"
    _dm_devices "${1}"
    _dmraid_partitions "${1}"
    _raid_devices "${1}"
    _partitionable_raid_devices_partitions "${1}"
}

# don't check on raid devices!
_findbootloaderdisks() {
    if [[ -z "${_USE_DMRAID}" ]]; then
        _blockdevices "${1}"
    else
        _dmraid_devices "${1}"
    fi
}

_activate_lvm2()
{
    _LVM2_READY=""
    if [[ -e /usr/bin/lvm ]]; then
        _OLD_LVM2_GROUPS=${_LVM2_GROUPS}
        _OLD_LVM2_VOLUMES=${_LVM2_VOLUMES}
        _dialog --infobox "Scanning logical volumes..." 0 0
        lvm vgscan --ignorelockingfailure &>"${_NO_LOG}"
        _dialog --infobox "Activating logical volumes..." 0 0
        lvm vgchange --ignorelockingfailure --ignoremonitoring -ay &>"${_NO_LOG}"
        _LVM2_GROUPS="$(vgs -o vg_name --noheading 2>/dev/null)"
        _LVM2_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)"
        [[ "${_OLD_LVM2_GROUPS}" == "${_LVM2_GROUPS}" && "${_OLD_LVM2_VOLUMES}" == "${_LVM2_VOLUMES}" ]] && _LVM2_READY="1"
    fi
}

_activate_md()
{
    _RAID_READY=""
    if [[ -e /usr/bin/mdadm ]]; then
        _dialog --infobox "Activating RAID arrays..." 0 0
        mdadm --assemble --scan &>"${_NO_LOG}" || _RAID_READY="1"
    fi
}

_activate_luks()
{
    _LUKS_READY=""
    if [[ -e /usr/bin/cryptsetup ]]; then
        _dialog --infobox "Scanning for luks encrypted devices..." 0 0
        if ${_LSBLK} FSTYPE | grep -q "crypto_LUKS"; then
            for part in $(${_LSBLK} NAME,FSTYPE | grep " crypto_LUKS$" | cut -d' ' -f 1); do
                # skip already encrypted devices, device mapper!
                if ! ${_LSBLK} TYPE "${part}" | grep -q "crypt$"; then
                    _RUN_LUKS=""
                    _dialog --yesno "Setup detected luks encrypted device, do you want to activate ${part} ?" 0 0 && _RUN_LUKS=1
                    [[ -n "${_RUN_LUKS}" ]] && _enter_luks_name && _enter_luks_passphrase && _opening_luks
                    [[ -z "${_RUN_LUKS}" ]] && _LUKS_READY="1"
                else
                    _LUKS_READY="1"
                fi
            done
        else
            _LUKS_READY="1"
        fi
    fi
}

# activate special devices:
# activate lvm2 and raid devices, if not already activated during bootup!
# run it more times if needed, it can be hidden by each other!
_activate_special_devices()
{
    _RAID_READY=""
    _LUKS_READY=""
    _LVM2_READY=""
    while [[ -n "${_LVM2_READY}" && -n "${_RAID_READY}" && -n "${_LUKS_READY}" ]]; do
        _activate_md
        _activate_lvm2
        _activate_luks
    done
}

_set_device_name_scheme() {
    _NAME_SCHEME_PARAMETER=""
    _NAME_SCHEME_LEVELS=""
    _MENU_DESC_TEXT=""
    ## util-linux root=PARTUUID=/root=PARTLABEL= support - https://git.kernel.org/?p=utils/util-linux/util-linux.git;a=commitdiff;h=fc387ee14c6b8672761ae5e67ff639b5cae8f27c;hp=21d1fa53f16560dacba33fffb14ffc05d275c926
    ## mkinitcpio's init root=PARTUUID= support - https://projects.archlinux.org/mkinitcpio.git/tree/init_functions#n185
    if [[ -n "${_UEFI_BOOT}" ]]; then
        _NAME_SCHEME_LEVELS="${_NAME_SCHEME_LEVELS} PARTUUID PARTUUID=<partuuid> PARTLABEL PARTLABEL=<partlabel>"
        _MENU_DESC_TEXT="\nPARTUUID and PARTLABEL are specific to GPT disks.\nIn GPT disks, PARTUUID is recommended.\nIn MBR/msdos disks,"
    fi
    _NAME_SCHEME_LEVELS="${_NAME_SCHEME_LEVELS} FSUUID UUID=<uuid> FSLABEL LABEL=<label> KERNEL /dev/<kernelname>"
    #shellcheck disable=SC2086
    _dialog --menu "Select the device name scheme you want to use in config files. ${_MENU_DESC_TEXT} FSUUID is recommended." 15 70 9 ${_NAME_SCHEME_LEVELS} 2>"${_ANSWER}" || return 1
    _NAME_SCHEME_PARAMETER=$(cat "${_ANSWER}")
    _NAME_SCHEME_PARAMETER_RUN=1
}

_clean_disk() {
    # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
    sgdisk -Z "${1}" &>"${_NO_LOG}"
    wipefs -a --force "${1}" &>"${_NO_LOG}"
    dd if=/dev/zero of="${1}" bs=512 count=2048 &>"${_NO_LOG}"
}

_getavaildisks()
{
    #shellcheck disable=SC2119
    for i in $(_finddisks); do
        ${_LSBLK} NAME,SIZE -d "${i}"
    done
}

_getavailpartitions()
{
    #shellcheck disable=SC2119
    for i in $(_finddevices); do
        ${_LSBLK} NAME,SIZE -d "${i}"
    done
}

# Disable swap and all mounted partitions for the destination system. Unmount
# the destination root partition last!
_umountall()
{
    if [[ "${_DESTDIR}" == "/install" ]] && mountpoint -q "${_DESTDIR}"; then
        swapoff -a &>"${_NO_LOG}"
        for i in $(findmnt --list --submounts "${_DESTDIR}" -o TARGET -n | tac); do
            umount "$i"
        done
        _dialog --infobox "Disabled swapspace,\nunmounted already mounted disk devices in ${_DESTDIR} ...\n\nContinuing in 3 seconds..." 7 60
        sleep 3
    fi
}

_stopmd()
{
    if grep -q ^md /proc/mdstat 2>/dev/null; then
        _DISABLEMD=""
        _dialog --defaultno --yesno "Setup detected already running raid devices, do you want to delete them completely?" 0 0 && _DISABLEMD=1
        if [[ -n "${_DISABLEMD}" ]]; then
            _umountall
            _dialog --infobox "Disabling all software raid devices..." 0 0
            # shellcheck disable=SC2013
            for i in $(grep ^md /proc/mdstat | sed -e 's# :.*##g'); do
                mdadm --manage --stop "/dev/${i}" >"${_LOG}" 2>&1
                wipefs -a "/dev/${i}" &>"${_NO_LOG}"
            done
        fi
    fi
    _DISABLEMDSB=""
    if ${_LSBLK} FSTYPE | grep -q "linux_raid_member"; then
        _dialog --defaultno --yesno "Setup detected superblock of raid devices, do you want to delete the superblock of them?" 0 0 && _DISABLEMDSB=1
        if [[ -n "${_DISABLEMDSB}" ]]; then
            _umountall
        fi
    fi
    if [[ -n "${_DISABLEMD}" || -n "${_DISABLEMDSB}" ]]; then
        _dialog --infobox "Deleting superblocks of all software raid devices..." 0 0
        for i in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d' ' -f 1); do
            _clean_disk "${i}"
        done
    fi
}

_stoplvm()
{
    _DISABLELVM=""
    _DETECTED_LVM=""
    _LV_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)"
    _LV_GROUPS="$(vgs -o vg_name --noheading 2>/dev/null)"
    _LV_PHYSICAL="$(pvs -o pv_name --noheading 2>/dev/null)"
    [[ -n "${_LV_VOLUMES}" ]] && _DETECTED_LVM=1
    [[ -n "${_LV_GROUPS}" ]] && _DETECTED_LVM=1
    [[ -n "${_LV_PHYSICAL}" ]] && _DETECTED_LVM=1
    if [[ -n "${_DETECTED_LVM}" ]]; then
        _dialog --defaultno --yesno "Setup detected lvm volumes, volume groups or physical devices, do you want to remove them completely?" 0 0 && _DISABLELVM=1
    fi
    if [[ -n "${_DISABLELVM}" ]]; then
        _umountall
        _dialog --infobox "Removing logical volumes ..." 0 0
        for i in ${_LV_VOLUMES}; do
            lvremove -f "/dev/mapper/${i}" 2>/dev/null>"${_LOG}"
        done
        _dialog --infobox "Removing logical groups ..." 0 0
        for i in ${_LV_GROUPS}; do
            vgremove -f "${i}" 2>/dev/null >"${_LOG}"
        done
        _dialog --infobox "Removing physical volumes ..." 0 0
        for i in ${_LV_PHYSICAL}; do
            pvremove -f "${i}" 2>/dev/null >"${_LOG}"
        done
    fi
}

_stopluks()
{
    _DISABLELUKS=""
    _DETECTED_LUKS=""
    _LUKSDEV=""
    # detect already running luks devices
    _LUKSDEV="$(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d' ' -f1)"
    [[ -z "${_LUKSDEV}" ]] || _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected running luks encrypted devices, do you want to remove them completely?" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        _umountall
        _dialog --infobox "Removing luks encrypted devices ..." 0 0
        for i in ${_LUKSDEV}; do
            _LUKS_REAL_DEV="$(${_LSBLK} NAME,FSTYPE -s "${_LUKSDEV}" | grep " crypto_LUKS$" | cut -d' ' -f1)"
            cryptsetup remove "${i}" >"${_LOG}"
            # delete header from device
            wipefs -a "${_LUKS_REAL_DEV}" &>"${_NO_LOG}"
        done
    fi
    _DISABLELUKS=""
    _DETECTED_LUKS=""
    # detect not running luks devices
    ${_LSBLK} FSTYPE | grep -q "crypto_LUKS" && _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected not running luks encrypted devices, do you want to remove them completely?" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        _dialog --infobox "Removing not running luks encrypted devices ..." 0 0
        for i in $(${_LSBLK} NAME,FSTYPE | grep "crypto_LUKS$" | cut -d' ' -f1); do
           # delete header from device
           wipefs -a "${i}" &>"${_NO_LOG}"
        done
    fi
    [[ -e /tmp/.crypttab ]] && rm /tmp/.crypttab
}

_helpmd()
{
_dialog --msgbox "LINUX SOFTWARE RAID SUMMARY:\n
-----------------------------\n\n
Linear mode:\n
You have two or more partitions which are not necessarily the same size\n
(but of course can be), which you want to append to each other.\n
Spare-disks are not supported here. If a disk dies, the array dies with\n
it.\n\n
RAID-0:\n
You have two or more devices, of approximately the same size, and you want\n
to combine their storage capacity and also combine their performance by\n
accessing them in parallel. Like in Linear mode, spare disks are not\n
supported here either. RAID-0 has no redundancy, so when a disk dies, the\n
array goes with it.\n\n
RAID-1:\n
You have two devices of approximately same size, and you want the two to\n
be mirrors of each other. Eventually you have more devices, which you\n
want to keep as stand-by spare-disks, that will automatically become a\n
part of the mirror if one of the active devices break.\n\n
RAID-4:\n
You have three or more devices of roughly the same size and you want\n
a way that protects data against loss of any one disk.\n
Fault tolerance is achieved by adding an extra disk to the array, which\n
is dedicated to storing parity information. The overall capacity of the\n
array is reduced by one disk.\n
The storage efficiency is 66 percent. With six drives, the storage\n
efficiency is 87 percent. The main disadvantage is poor performance for\n
multiple,\ simultaneous, and independent read/write operations.\n
Thus, if any disk fails, all data stay intact. But if two disks fail,\n
all data is lost.\n\n
RAID-5:\n
You have three or more devices of roughly the same size, you want to\n
combine them into a larger device, but still to maintain a degree of\n
redundancy fordata safety. Eventually you have a number of devices to use\n
as spare-disks, that will not take part in the array before another device\n
fails. If you use N devices where the smallest has size S, the size of the\n
entire array will be (N-1)*S. This \"missing\" space is used for parity\n
(redundancy) information. Thus, if any disk fails, all data stay intact.\n
But if two disks fail, all data is lost.\n\n
RAID-6:\n
You have four or more devices of roughly the same size and you want\n
a way that protects data against loss of any two disks.\n
Fault tolerance is achieved by adding an two extra disk to the array,\n
which is dedicated to storing parity information. The overall capacity\n
of the array is reduced by 2 disks.\n
Thus, if any two disks fail, all data stay intact. But if 3 disks fail,\n
all data is lost.\n\n
RAID-10:\n
Shorthand for RAID1+0, a mirrored striped array and needs a minimum of\n
two disks. It provides superior data security and can survive multiple\n
disk failures. The main disadvantage is cost, because 50% of your\n
storage is duplication." 0 0
}

_createmd()
{
    _MDFINISH=""
    while [[ "${_MDFINISH}" != "DONE" ]]; do
        _activate_special_devices
        : >/tmp/.raid
        : >/tmp/.raid-spare
        # check for devices
        # Remove all raid devices with children
        _RAID_BLACKLIST="$(_raid_devices;_partitionable_raid_devices_partitions)"
        #shellcheck disable=SC2119
        _DEVS="$(for i in $(_finddevices); do
                echo "${_RAID_BLACKLIST}" | grep -qw "${i}" || echo "${i}" _
                done)"
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "All devices in use. No more devices left for new creation." 0 0
            return 1
        fi
        # enter raid device name
        _RAIDDEV=""
        while [[ -z "${_RAIDDEV}" ]]; do
            _dialog --inputbox "Enter the node name for the raiddevice:\n/dev/md[number]\n/dev/md0\n/dev/md1\n\n" 12 50 "/dev/md0" 2>"${_ANSWER}" || return 1
            _RAIDDEV=$(cat "${_ANSWER}")
            if grep -q "^${_RAIDDEV//\/dev\//}" /proc/mdstat; then
                _dialog --msgbox "ERROR: You have defined 2 identical node names! Please enter another name." 8 65
                _RAIDDEV=""
            fi
        done
        _RAIDLEVELS="linear - raid0 - raid1 - raid4 - raid5 - raid6 - raid10 -"
        #shellcheck disable=SC2086
        _dialog --menu "Select the raid level you want to use:" 14 50 7 ${_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _LEVEL=$(cat "${_ANSWER}")
        # raid5 and raid10 support parity parameter
        _PARITY=""
        if [[ "${_LEVEL}" == "raid5" || "${_LEVEL}" == "raid6" || "${_LEVEL}" == "raid10" ]]; then
            _PARITYLEVELS="left-asymmetric - left-symmetric - right-asymmetric - right-symmetric -"
            #shellcheck disable=SC2086
            _dialog --menu "Select the parity layout you want to use (default is left-symmetric):" 21 50 13 ${_PARITYLEVELS} 2>"${_ANSWER}" || return 1
            _PARITY=$(cat "${_ANSWER}")
        fi
        # show all devices with sizes
        _dialog --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)" 0 0
        # select the first device to use, no missing option available!
        _RAIDNUMBER=1
        #shellcheck disable=SC2086
        _dialog --menu "Select device ${_RAIDNUMBER}:" 21 50 13 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.raid
        while [[ "${_DEV}" != "DONE" ]]; do
            _RAIDNUMBER=$((_RAIDNUMBER + 1))
            # clean loop from used partition and options
            _DEVS="$(echo "${_DEVS}" | sed -e "s#${_DEV}\ _##g" -e 's#MISSING\ _##g' -e 's#SPARE\ _##g')"
            # raid0 doesn't support missing devices
            ! [[ "${_LEVEL}" == "raid0" || "${_LEVEL}" == "linear" ]] && _MDEXTRA="MISSING _"
            # add more devices
            #shellcheck disable=SC2086
            _dialog --menu "Select additional device ${_RAIDNUMBER}:" 21 50 13 ${_DEVS} ${_MDEXTRA} DONE _ 2>"${_ANSWER}" || return 1
            _DEV=$(cat "${_ANSWER}")
            _SPARE=""
            ! [[ "${_LEVEL}" == "raid0" || "${_LEVEL}" == "linear" ]] && _dialog --yesno --defaultno "Would you like to use ${_DEV} as spare device?" 0 0 && _SPARE=1
            [[ "${_DEV}" == "DONE" ]] && break
            if [[ "${_DEV}" == "MISSING" ]]; then
                _dialog --yesno "Would you like to create a degraded raid on ${_RAIDDEV}?" 0 0 && _DEGRADED="missing"
                echo "${_DEGRADED}" >>/tmp/.raid
            else
                if [[ -n "${_SPARE}" ]]; then
                    echo "${_DEV}" >>/tmp/.raid-spare
                else
                    echo "${_DEV}" >>/tmp/.raid
                fi
            fi
        done
        # final step ask if everything is ok?
        # shellcheck disable=SC2028
        _dialog --yesno "Would you like to create ${_RAIDDEV} like this?\n\nLEVEL:\n${_LEVEL}\n\nDEVICES:\n$(while read -r i;do echo "${i}\n"; done < /tmp/.raid)\nSPARES:\n$(while read -r i;do echo "${i}\n"; done < tmp/.raid-spare)" 0 0 && _MDFINISH="DONE"
    done
    _umountall
    _DEVS="$(echo -n "$(cat /tmp/.raid)")"
    _SPARES="$(echo -n "$(cat /tmp/.raid-spare)")"
    # combine both if spares are available, spares at the end!
    [[ -n ${_SPARES} ]] && _DEVS="${_DEVS} ${_SPARES}"
    # get number of devices
    _RAID_DEVS="$(wc -l < /tmp/.raid)"
    _SPARE_DEVS="$(wc -l < /tmp/.raid-spare)"
    # generate options for mdadm
    _RAIDOPTIONS="--force --run --level=${_LEVEL}"
    ! [[ "${_RAID_DEVS}" == 0 ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --raid-devices=${_RAID_DEVS}"
    ! [[ "${_SPARE_DEVS}" == 0 ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --spare-devices=${_SPARE_DEVS}"
    [[ -n "${_PARITY}" ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --layout=${_PARITY}"
    _dialog --infobox "Creating ${_RAIDDEV}..." 0 0
    #shellcheck disable=SC2086
    if mdadm --create ${_RAIDDEV} ${_RAIDOPTIONS} ${_DEVS} >"${_LOG}" 2>&1; then
        _dialog --infobox "${_RAIDDEV} created successfully.\n\nContinuing in 3 seconds..." 5 50
        sleep 3
    else
        _dialog --msgbox "Error creating ${_RAIDDEV} (see ${_LOG} for details)." 0 0
        return 1
    fi
    if [[ -n ${_RAID_DEVITION} ]]; then
        # switch for mbr usage
        _set_guid
        if [[ -z "${_GUIDPARAMETER}" ]]; then
            _dialog --msgbox "Now you'll be put into the cfdisk program where you can partition your raiddevice to your needs." 6 70
            cfdisk "${_RAIDDEV}"
        else
            _DISK="${_RAIDDEV}"
            _RUN_CFDISK=1
            _CHECK_BIOS_BOOT_GRUB=""
            _CHECK_UEFISYSDEV=""
            _check_gpt
        fi
    fi
}

_helplvm()
{
_dialog --msgbox "LOGICAL VOLUME SUMMARY:\n
-----------------------------\n\n
LVM is a Logical Volume Manager for the Linux kernel. With LVM you can\n
abstract your storage space and have \"virtual partitions\" which are easier\n
to modify.\n\nThe basic building block of LVM are:\n
- Physical volume (PV):\n
  Partition on storage disk (or even storage disk itself or loopback file) on\n
  which you can have virtual groups. It has a special header and is\n
  divided into physical extents. Think of physical volumes as big building\n
  blocks which can be used to build your storage drive.\n
- Volume group (VG):\n
  Group of physical volumes that are used as storage volume (as one disk).\n
  They contain logical volumes. Think of volume groups as storage drives.\n
- Logical volume(LV):\n
  A \"virtual/logical partition\" that resides in a volume group and is\n
  composed of physical extents. Think of logical volumes as normal\n
  partitions." 0 0
}

_createpv()
{
    _PVFINISH=""
    while [[ "${_PVFINISH}" != "DONE" ]]; do
        _activate_special_devices
        : >/tmp/.pvs-create
        # Remove all lvm devices with children
        _LVM_BLACKLIST="$(for i in $(${_LSBLK} NAME,TYPE | grep " lvm$" | cut -d' ' -f1 | sort -u); do
                    echo "$(${_LSBLK} NAME "${i}")" _
                    done)"
        #shellcheck disable=SC2119
        _DEVS="$(for i in $(_finddevices); do
                ! echo "${_LVM_BLACKLIST}" | grep -E "${i} _" && echo "${i}" _
                done)"
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "No devices left for physical volume creation." 0 0
            return 1
        fi
        # show all devices with sizes
        _dialog --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)\n\n" 0 0
        # select the first device to use
        _DEVNUMBER=1
        #shellcheck disable=SC2086
        _dialog --menu "Select device number ${_DEVNUMBER} for physical volume:" 15 50 12 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.pvs-create
        while [[ "${_DEV}" != "DONE" ]]; do
            _DEVNUMBER="$((_DEVNUMBER + 1))"
            # clean loop from used partition and options
            _DEVS="${_DEVS//${_DEV}\ _/}"
            # add more devices
            #shellcheck disable=SC2086
            _dialog --menu "Select additional device number ${_DEVNUMBER} for physical volume:" 15 60 12 ${_DEVS} DONE _ 2>"${_ANSWER}" || return 1
            _DEV=$(cat "${_ANSWER}")
            [[ "${_DEV}" == "DONE" ]] && break
            echo "${_DEV}" >>/tmp/.pvs-create
        done
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create physical volume on devices below?\n$(sed -e 's#$#\\n#g' /tmp/.pvs-create)" 0 0 && _PVFINISH="DONE"
    done
    _dialog --infobox "Creating physical volume on ${_DEV}..." 0 0
    _DEV="$(echo -n "$(cat /tmp/.pvs-create)")"
    #shellcheck disable=SC2028,SC2086
    _umountall
    #shellcheck disable=SC2086
    if pvcreate -y ${_DEV} >"${_LOG}" 2>&1; then
        _dialog --infobox "Creating physical volume on ${_DEV} successful.\n\nContinuing in 3 seconds..." 6 75
        sleep 3
    else
        _dialog --msgbox "Error creating physical volume on ${_DEV} (see ${_LOG} for details)." 0 0; return 1
    fi
    # run udevadm to get values exported
    udevadm trigger
    udevadm settle
}

#find physical volumes that are not in use
_findpv()
{
    for i in $(${_LSBLK} NAME,FSTYPE | grep " LVM2_member$" | cut -d' ' -f1 | sort -u); do
         # exclude checks:
         #-  not part of running lvm2
         # ! "$(${_LSBLK} TYPE ${i} | grep "lvm")"
         #- not part of volume group
         # $(pvs -o vg_name --noheading ${i} | grep " $")
         if ! ${_LSBLK} TYPE "${i}" | grep -q "lvm" && pvs -o vg_name --noheading "${i}" | grep -q " $"; then
             echo "${i}"
             [[ "${1}" ]] && echo "${1}"
         fi
    done
}

_getavailablepv()
{
    for i in $(${_LSBLK} NAME,FSTYPE | grep " LVM2_member$" | cut -d' ' -f1 | sort -u); do
        # exclude checks:
        #-  not part of running lvm2
        # ! "$(${_LSBLK} TYPE ${i} | grep "lvm")"
        #- not part of volume group
        # $(pvs -o vg_name --noheading ${i} | grep " $")
        if ! ${_LSBLK} TYPE "${i}" | grep "lvm" && pvs -o vg_name --noheading "${i}" | grep -q " $"; then
            ${_LSBLK} NAME,SIZE "${i}"
        fi
    done
}

#find volume groups that are not already full in use
_findvg()
{
    for dev in $(vgs -o vg_name --noheading);do
        if ! vgs -o vg_free --noheading --units m "${dev}" | grep -q " 0m$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

_getavailablevg()
{
    for i in $(vgs -o vg_name,vg_free --noheading --units m); do
        if ! echo "${i}" | grep -q " 0m$"; then
            #shellcheck disable=SC2028
            echo "${i}\n"
        fi
    done
}

_createvg()
{
    _VGFINISH=""
    while [[ "${_VGFINISH}" != "DONE" ]]; do
        : >/tmp/.pvs
        _VGDEV=""
        _PVS=$(_findpv _)
        # break if all devices are in use
        if [[ -z "${PVS}" ]]; then
            _dialog --msgbox "No devices left for Volume Group creation." 0 0
            return 1
        fi
        # enter volume group name
        _VGDEV=""
        while [[ -z "${_VGDEV}" ]]; do
            _dialog --inputbox "Enter the Volume Group name:\nfoogroup\n<yourvolumegroupname>\n\n" 11 40 "foogroup" 2>"${_ANSWER}" || return 1
            _VGDEV=$(cat "${_ANSWER}")
            if vgs -o vg_name --noheading | grep -q "^  ${_VGDEV}"; then
                _dialog --msgbox "ERROR: You have defined 2 identical Volume Group names! Please enter another name." 8 65
                _VGDEV=""
            fi
        done
        # show all devices with sizes, which are not in use
        #shellcheck disable=SC2086
        _dialog --cr-wrap --msgbox "Physical Volumes:\n$(getavailablepv)" 0 0
        # select the first device to use, no missing option available!
        _PVNUMBER=1
        #shellcheck disable=SC2086
        _dialog --menu "Select Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 ${_PVS} 2>"${_ANSWER}" || return 1
        _PV=$(cat "${_ANSWER}")
        echo "${_PV}" >>/tmp/.pvs
        while [[ "${_PVS}" != "DONE" ]]; do
            _PVNUMBER=$((_PVNUMBER + 1))
            # clean loop from used partition and options
            #shellcheck disable=SC2001,SC2086
            _PVS="$(echo ${_PVS} | sed -e "s#${_PV} _##g")"
            # add more devices
            #shellcheck disable=SC2086
            _dialog --menu "Select additional Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 ${_PVS} DONE _ 2>"${_ANSWER}" || return 1
            _PV=$(cat "${_ANSWER}")
            [[ "${_PV}" == "DONE" ]] && break
            echo "${_PV}" >>/tmp/.pvs
        done
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Volume Group like this?\n\n${_VGDEV}\n\nPhysical Volumes:\n$(sed -e 's#$#\\n#g' /tmp/.pvs)" 0 0 && _VGFINISH="DONE"
    done
    _dialog --infobox "Creating Volume Group ${_VGDEV}..." 0 0
    _PV="$(echo -n "$(cat /tmp/.pvs)")"
    _umountall
    #shellcheck disable=SC2086
    if vgcreate ${_VGDEV} ${_PV} >"${_LOG}" 2>&1; then
        _dialog --infobox "Creating Volume Group ${_VGDEV} successful.\n\nContinuing in 3 seconds..." 5 50
        sleep 3
    else
        _dialog --msgbox "Error creating Volume Group ${_VGDEV} (see ${_LOG} for details)." 0 0
        return 1
    fi
}

_createlv()
{
    _LVFINISH=""
    while [[ "${_LVFINISH}" != "DONE" ]]; do
        _LVDEV=""
        _LV_SIZE_SET=""
        _LVS=$(_findvg _)
        # break if all devices are in use
        if [[ -z "${_LVS}" ]]; then
            _dialog --msgbox "No Volume Groups with free space available for Logical Volume creation." 0 0
            return 1
        fi
        # show all devices with sizes, which are not 100% in use!
        _dialog --cr-wrap --msgbox "Volume Groups:\n$(getavailablevg)" 0 0
        #shellcheck disable=SC2086
        _dialog --menu "Select Volume Group:" 11 50 5 ${_LVS} 2>"${_ANSWER}" || return 1
        _LV=$(cat "${_ANSWER}")
        # enter logical volume name
        _LVDEV=""
        while [[ -z "${_LVDEV}" ]]; do
            _dialog --inputbox "Enter the Logical Volume name:\nfooname\n<yourvolumename>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
            _LVDEV=$(cat "${_ANSWER}")
            if lvs -o lv_name,vg_name --noheading | grep -q " ${_LVDEV} ${_LV}$"; then
                _dialog --msgbox "ERROR: You have defined 2 identical Logical Volume names! Please enter another name." 8 65
                _LVDEV=""
            fi
        done
        while [[ -z "${_LV_SIZE_SET}" ]]; do
            _LV_ALL=""
            _dialog --inputbox "Enter the size (MB) of your Logical Volume,\nMinimum value is > 0.\n\nVolume space left: $(vgs -o vg_free --noheading --units m "${_LV}")B\n\nIf you enter no value, all free space left will be used." 10 65 "" 2>"${_ANSWER}" || return 1
                _LV_SIZE=$(cat "${_ANSWER}")
                if [[ -z "${_LV_SIZE}" ]]; then
                    _dialog --yesno "Would you like to create Logical Volume with no free space left?" 0 0 && _LV_ALL=1
                    if [[ -z "${_LV_ALL}" ]]; then
                         _LV_SIZE=0
                    fi
                fi
                if [[ "${_LV_SIZE}" == 0 ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_LV_SIZE}" -ge "$(vgs -o vg_free --noheading --units m | sed -e 's#m##g')" ]]; then
                        _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        _LV_SIZE_SET=1
                    fi
                fi
        done
        #Contiguous doesn't work with +100%FREE
        _LV_CONTIGUOUS=""
        [[ -z "${_LV_ALL}" ]] && _dialog --defaultno --yesno "Would you like to create Logical Volume as a contiguous partition, that means that your space doesn't get partitioned over one or more disks nor over non-contiguous physical extents.\n(usefull for swap space etc.)?" 0 0 && _LV_CONTIGUOUS=1
        if [[ -n "${_LV_CONTIGUOUS}" ]]; then
            _CONTIGUOUS=yes
            _LV_EXTRA="-C y"
        else
            _CONTIGUOUS=no
            _LV_EXTRA=""
        fi
        [[ -z "${_LV_SIZE}" ]] && _LV_SIZE="All free space left"
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Logical Volume ${_LVDEV} like this?\nVolume Group:\n${_LV}\nVolume Size:\n${_LV_SIZE}\nContiguous Volume:\n${_CONTIGUOUS}" 0 0 && _LVFINISH="DONE"
    done
    _umountall
    if [[ -n "${_LV_ALL}" ]]; then
        #shellcheck disable=SC2086
        if lvcreate ${_LV_EXTRA} -l +100%FREE ${_LV} -n ${_LVDEV} >"${_LOG}" 2>&1; then
            _dialog --infobox "Creating Logical Volume ${_LVDEV} successful.\n\nContinuing in 3 seconds..." 5 50
            sleep 3
        else
            _dialog --msgbox "Error creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    else
        #shellcheck disable=SC2086
        if lvcreate ${_LV_EXTRA} -L ${_LV_SIZE} ${_LV} -n ${_LVDEV} >"${_LOG}" 2>&1; then
            _dialog --infobox "Creating Logical Volume ${_LVDEV} successful.\n\nContinuing in 3 seconds..." 5 50
            sleep 3
        else
            _dialog --msgbox "Error creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    fi
}

_enter_luks_name() {
    _LUKSDEV=""
    while [[ -z "${_LUKSDEV}" ]]; do
        _dialog --inputbox "Enter the name for luks encrypted device ${_DEV}:\nfooname\n<yourname>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
        _LUKSDEV=$(cat "${_ANSWER}")
        if ! cryptsetup status "${_LUKSDEV}" | grep -q inactive; then
            _dialog --msgbox "ERROR: You have defined 2 identical luks encryption device names! Please enter another name." 8 65
            _LUKSDEV=""
        fi
    done
}

_enter_luks_passphrase () {
    _LUKSPASSPHRASE=""
    while [[ -z "${LUKSPASSPHRASE}" ]]; do
        _dialog --insecure --passwordbox "Enter passphrase for luks encrypted device ${_DEV}:" 0 0 2>"${_ANSWER}" || return 1
        _LUKSPASS=$(cat "${_ANSWER}")
        _dialog --insecure --passwordbox "Retype passphrase for luks encrypted device ${_DEV}:" 0 0 2>"${_ANSWER}" || return 1
        _LUKSPASS2=$(cat "${_ANSWER}")
        if [[ -n "${_LUKSPASS}" && -n "${_LUKSPASS2}" && "${_LUKSPASS}" == "${_LUKSPASS2}" ]]; then
            _LUKSPASSPHRASE=${_LUKSPASS}
            echo "${_LUKSPASSPHRASE}" > "/tmp/passphrase-${_LUKSDEV}"
            _LUKSPASSPHRASE="/tmp/passphrase-${_LUKSDEV}"
        else
             _dialog --msgbox "Passphrases didn't match or was empty, please enter again." 0 0
        fi
    done
}

_opening_luks() {
    _dialog --infobox "Opening encrypted ${_DEV}..." 0 0
    _LUKSOPEN_SUCCESS=""
    while [[ -z "${_LUKSOPEN_SUCCESS}" ]]; do
        cryptsetup luksOpen "${_DEV}" "${_LUKSDEV}" <"${_LUKSPASSPHRASE}" >"${_LOG}" && _LUKSOPEN_SUCCESS=1
        if [[ -z "${_LUKSOPEN_SUCCESS}" ]]; then
            _dialog --msgbox "Error: Passphrase didn't match, please enter again." 0 0
            _enter_luks_passphrase || return 1
        fi
    done
    _dialog --yesno "Would you like to save the passphrase of luks device in /etc/$(basename "${_LUKSPASSPHRASE}")?\nName:${_LUKSDEV}" 0 0 || _LUKSPASSPHRASE="ASK"
    echo "${_LUKSDEV}" "${_DEV}" "/etc/$(basename "${_LUKSPASSPHRASE}")" >> /tmp/.crypttab
}

_helpluks()
{
_dialog --msgbox "LUKS ENLUKSION SUMMARY:\n
-----------------------------\n\n
Encryption is useful for two (related) reasons.\n
Firstly, it prevents anyone with physical access to your computer,\n
and your storage drive in particular, from getting the data from it\n
(unless they have your passphrase/key).\n
Secondly, it allows you to wipe the data on your storage drive with\n
far more confidence in the event of you selling or discarding\n
your drive.\n
Basically, it supplements the access control mechanisms of the operating\n
system (like file permissions) by making it harder to bypass the operating\n
system by inserting a bootable medium, for example. Encrypting the root\n
partition prevents anyone from using this method to insert viruses or\n
trojans onto your computer.\n\n
ATTENTION:\n
Having encrypted partitions does not protect you from all possible\n
attacks. The encryption is only as good as your key management, and there\n
are other ways to break into computers, while they are running." 0 0
}

_createluks()
{
    _NAME_SCHEME_PARAMETER_RUN=""
    _LUKSFINISH=""
    while [[ "${_LUKSFINISH}" != "DONE" ]]; do
        _activate_special_devices
        # Remove all crypt devices with children
        _LUKS_BLACKLIST="$(for i in $(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d' ' -f1 | sort -u); do
                    ${_LSBLK} NAME "${i}"
                    done)"
        #shellcheck disable=SC2119
        _DEVS="$(for i in $(_finddevices); do
                echo "${_LUKS_BLACKLIST}" | grep -wq "${i}" || echo "${i}" _;
                done)"
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "No devices left for luks encryption." 0 0
            return 1
        fi
        # show all devices with sizes
        _dialog --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)\n\n" 0 0
        #shellcheck disable=SC2086
        _dialog --menu "Select device for luks encryption:" 15 50 12 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        # enter luks name
        _enter_luks_name || return 1
        ### TODO: offer more options for encrypt!
        ###       defaults are used only
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to encrypt luks device below?\nName:${_LUKSDEV}\nDevice:${_DEV}\n" 0 0 && _LUKSFINISH="DONE"
    done
    _enter_luks_passphrase || return 1
    _umountall
    _dialog --infobox "Encrypting ${_DEV}..." 0 0
    cryptsetup -q luksFormat "${_DEV}" <"${_LUKSPASSPHRASE}" >"${_LOG}"
    _opening_luks
}
