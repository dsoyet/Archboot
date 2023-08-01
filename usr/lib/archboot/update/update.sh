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
        echo -e " \e[1m-update\e[m          Update scripts: setup, quickinst, network, clock and helpers."
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
# vim: set ft=sh ts=4 sw=4 et:
