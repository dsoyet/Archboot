#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.launcher"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Launcher"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_show_login() {
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    clear
    echo ""
    agetty --show-issue
    echo ""
    cat /etc/motd
}

_check_desktop() {
    _DESKTOP=()
    update | grep -q Gnome && _DESKTOP+=( "GNOME" "Simple Beautiful Elegant" )
    update | grep -q KDE && _DESKTOP+=( "PLASMA" "Simple By Default" )
    update | grep -q Sway && _DESKTOP+=( "SWAY" "Tiling Wayland Compositor" )
    update | grep -q Xfce && _DESKTOP+=( "XFCE" "Leightweight Desktop" )
}

_check_manage() {
    _MANAGE=()
    update | grep -q full && _MANAGE+=( "FULL" "Switch To Full Arch Linux System" )
    update | grep -q latest && _MANAGE+=( "UPDATE" "Update Archboot Environment" )
    update | grep -q image && _MANAGE+=( "IMAGE" "Create New Archboot Images" )
}

_desktop () {
    _dialog --title " Desktop Menu " --menu "" 10 40 6 "${_DESKTOP[@]}" 2>${_ANSWER} || _launcher
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "GNOME" ]]; then
        if _dialog --defaultno --yesno "Gnome Desktop:\nDo you want to use the Wayland Backend?" 6 45; then
            clear
            update -gnome-wayland
        else
            clear
            update -gnome
        fi
    elif [[ "${_EXIT}" == "PLASMA" ]]; then
        if _dialog --defaultno --yesno "KDE/Plasma Desktop:\nDo you want to use the Wayland Backend?" 6 45; then
            clear
            update -plasma-wayland
        else
            clear
            update -plasma
        fi
    elif [[ "${_EXIT}" == "SWAY" ]]; then
        clear
        update -sway
    elif [[ "${_EXIT}" == "XFCE" ]]; then
        clear
        update -xfce
    fi
    exit 0
}

_manage() {
    _dialog --title " Manage Archboot Menu " --menu "" 9 50 5 "${_MANAGE[@]}" 2>${_ANSWER} || _launcher
    clear
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "FULL" ]]; then
        update -full-system
    elif [[ "${_EXIT}" == "UPDATE" ]]; then
        if update | grep -q latest-install; then
            update -latest-install
        else
            update -latest
        fi
    elif [[ "${_EXIT}" == "IMAGE" ]]; then
        update -latest-image
    fi
    exit 0
}

_exit() {
    #shellcheck disable=SC2086
    _dialog --title " EXIT MENU " --menu "" 9 30 5 \
    "1" "Exit Program" \
    "2" "Reboot System" \
    "3" "Poweroff System" 2>${_ANSWER} || _launcher
    _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "1" ]]; then
        _show_login
    elif [[ "${_EXIT}" == "2" ]]; then
        _dialog --infobox "Rebooting in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
        sleep 10
        clear
        reboot
    elif [[ "${_EXIT}" == "3" ]]; then
        _dialog --infobox "Powering off in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
        sleep 10
        clear
        poweroff
    fi
}

_launcher() {
    _MENU=()
    if [[ -n "${_DESKTOP[@]}" ]]; then
        _MENU+=( "2" "Launch Desktop Environment" )
    fi
    if [[ -n "${_MANAGE[@]}" ]]; then
        _MENU+=( "3" "Manage Archboot Environment" )
    fi
    _dialog --title " Main Menu " --menu "" 10 40 6 \
    "1" "Launch Archboot Setup" \
    "${_MENU[@]}" \
    "4" "Exit Program" 2>${_ANSWER}
    case $(cat ${_ANSWER}) in
        "1")
            [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
            setup
            exit 0 ;;
        "2")
            _desktop
            ;;
        "3")
            _manage
            ;;
        "4")
            _exit
            ;;
        *)
            if _dialog --yesno "Abort Arch Linux Setup Launcher?" 6 40; then
                _show_login
                exit 1
            fi
            ;;
    esac
}

if [[ -e /tmp/.launcher-running ]]; then
    echo "launcher already runs on a different console!"
    echo "Please remove /tmp/.launcher-running first to launch launcher!"
    exit 1
fi
: >/tmp/.launcher
: >/tmp/.launcher-running
_check_desktop
_check_manage
_launcher
# vim: set ts=4 sw=4 et: