#!/bin/bash
# source base and common first, contains basic parameters
. /usr/lib/archboot/installer/base.sh
. /usr/lib/archboot/installer/common.sh
# source all other functions
. /usr/lib/archboot/installer/autoconfiguration.sh
. /usr/lib/archboot/installer/autoprepare.sh
. /usr/lib/archboot/installer/blockdevices.sh
. /usr/lib/archboot/installer/bootloader.sh
. /usr/lib/archboot/installer/btrfs.sh
. /usr/lib/archboot/installer/configuration.sh
. /usr/lib/archboot/installer/mountpoints.sh
. /usr/lib/archboot/installer/network.sh
. /usr/lib/archboot/installer/pacman.sh
. /usr/lib/archboot/installer/partition.sh
. /usr/lib/archboot/installer/storage.sh

set_vconsole() {
    if [[ -e /usr/bin/km ]]; then
        km --setup && NEXTITEM="1"
    elif [[ -e /usr/bin/archboot-km.sh ]]; then
        archboot-km.sh --setup && NEXTITEM="1"
    else
        DIALOG --msgbox "Error:\nkm script not found, aborting console and keyboard setting." 0 0
    fi
}

select_source() {
    NEXTITEM="2"
    set_title
    if [[ -e "${LOCAL_DB}" ]]; then
        getsource || return 1
    else
        if [[ ${S_NET} -eq 0 ]]; then
            check_nework || return 1
        fi
        [[ "${RUNNING_ARCH}" == "x86_64" ]] && dotesting
        getsource || return 1
    fi
    NEXTITEM="3"
}

set_clock() {
    if [[ -e /usr/bin/tz ]]; then
        tz --setup && NEXTITEM="4"
    elif [[ -e /usr/bin/archboot-tz.sh ]]; then
        archboot-tz.sh --setup && NEXTITEM="4"
    else
        DIALOG --msgbox "Error:\ntz script not found, aborting clock setting" 0 0
    fi
}

prepare_storagedrive() {
    S_MKFSAUTO=0
    S_MKFS=0
    DONE=0
    NEXTITEM=""
    while [[ "${DONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Prepare Storage Drive" 12 60 5 \
            "1" "Auto-Prepare (erases the ENTIRE storage drive)" \
            "2" "Partition Storage Drives" \
            "3" "Manage Software Raid, Lvm2 and Luks encryption" \
            "4" "Set Filesystem Mountpoints" \
            "5" "Return to Main Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        [[ "${S_MKFSAUTO}" = "1" ]] && DONE=1
        case $(cat ${ANSWER}) in
            "1")
                autoprepare
                [[ "${S_MKFSAUTO}" = "1" ]] && DONE=1
                ;;
            "2")
                partition ;;
            "3")
                create_special ;;
            "4")
                PARTFINISH=""
                ASK_MOUNTPOINTS="1"
                mountpoints ;;
            *)
                DONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="4"
    else
        NEXTITEM="5"
    fi
}

configure_system() {
    destdir_mounts || return 1
    ## PREPROCESSING ##
    auto_mkinitcpio
    ## END PREPROCESS ##
    geteditor || return 1
    check_root_password || return 1
    set_locale || return 1
    FILE=""
    S_CONFIG=""
    # main menu loop
    while true; do
        if [[ -n "${FILE}" ]]; then
            DEFAULT="--default-item ${FILE}"
        else
            DEFAULT=""
        fi
        #shellcheck disable=SC2086
        DIALOG ${DEFAULT} --menu "Configuration" 20 60 16 \
            "/etc/hostname"                 "System Hostname" \
            "/etc/vconsole.conf"            "Virtual Console" \
            "/etc/locale.conf"              "Locale Setting" \
            "/etc/fstab"                    "Filesystem Mountpoints" \
            "/etc/mkinitcpio.conf"          "Initramfs Config" \
            "/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
            "/etc/resolv.conf"              "DNS Servers" \
            "/etc/hosts"                    "Network Hosts" \
            "/etc/locale.gen"               "Glibc Locales" \
            "/etc/pacman.d/mirrorlist"      "Pacman Mirror List" \
            "/etc/pacman.conf"              "Pacman Config File" \
            "Root-Password"                 "Set the root password" \
            "Return"                        "Return to Main Menu" 2>${ANSWER} || break
        FILE="$(cat ${ANSWER})"
        if [[ "${FILE}" = "Return" || -z "${FILE}" ]]; then       # exit
            S_CONFIG=1
            break           
        elif [[ "${FILE}" = "/etc/mkinitcpio.conf" ]]; then       # non-file
            set_mkinitcpio
            run_mkinitcpio
        elif [[ "${FILE}" = "/etc/locale.gen" ]]; then            # non-file
            set_locale
            ${EDITOR} "${DESTDIR}""${FILE}"
        elif [[ "${FILE}" = "Root-Password" ]]; then              # non-file
            set_password
        else                                                      #regular file
            ${EDITOR} "${DESTDIR}""${FILE}"
        fi
    done
    if [[ ${S_CONFIG} -eq 1 ]]; then
        NEXTITEM="7"
    fi
}

mainmenu() {
    if [[ -n "${NEXTITEM}" ]]; then
        DEFAULT="--default-item ${NEXTITEM}"
    else
        DEFAULT=""
    fi
    #shellcheck disable=SC2086
    dialog ${DEFAULT} --backtitle "${TITLE}" --title " MAIN MENU " \
    --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 17 58 14 \
    "0" "Set Console Font And Keymap" \
    "1" "Set up Network" \
    "2" "Select Source" \
    "3" "Set Time And Date" \
    "4" "Prepare Storage Drive" \
    "5" "Install Packages" \
    "6" "Configure System" \
    "7" "Install Bootloader" \
    "8" "Exit Install" 2>${ANSWER}
    NEXTITEM="$(cat ${ANSWER})"
    case $(cat ${ANSWER}) in
        "0")
            set_vconsole ;;
        "1")
            donetwork ;;
        "2")
            select_source || return 1
            update_environment ;;
        "3")
            set_clock ;;
        "4")
            prepare_storagedrive ;;
        "5")
            install_packages ;;
        "6")
            configure_system ;;
        "7")
            install_bootloader ;;
        "8")
            [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
            clear
            echo ""
            echo "If the install finished successfully, you can now type 'reboot'"
            echo "to restart the system."
            echo ""
            exit 0 ;;
        *)
            DIALOG --yesno "Abort Installation?" 6 40 && [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running && clear && exit 0
            ;;
    esac
}

#####################
## begin execution ##
if [[ -e /tmp/.setup-running ]]; then
    DIALOG --msgbox "Attention:\n\nSetup already runs on a different console!\nPlease remove /tmp/.setup-running first to launch setup!" 8 60
    exit 1
fi
: >/tmp/.setup-running
: >/tmp/.setup

set_title

DIALOG --msgbox "Welcome to the Archboot Arch Linux Installation program.\n\nThe install process is fairly straightforward, and you should run through the options in the order they are presented.\n\nIf you are unfamiliar with partitioning/making filesystems, you may want to consult some documentation before continuing.\n\nYou can view all output from commands by viewing your ${VC} console (ALT-F${VC_NUM}). ALT-F1 will bring you back here." 14 65

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
