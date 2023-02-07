#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# don't run ttyS0 as first device

_welcome () {
    [[ "$(uname -m)" == "x86_64" ]] && echo -e "\033[1mWelcome to \033[36mArchboot\033[0m\033[1m - Arch Linux\033[0m"
    [[ "$(uname -m)" == "aarch64" ]] && echo -e "\033[1mWelcome to \033[36mArchboot\033[0m\033[1m - Arch Linux ARM\033[0m"
    [[ "$(uname -m)" == "riscv64" ]] && echo -e "\033[1mWelcome to \033[36mArchboot\033[0m\033[1m - Arch Linux RISC-V 64\033[0m"
    echo -e "\033[1m--------------------------------------------------------------------\033[0m"
    _local_mode
}

_local_mode () {
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "You are running in \033[92m\033[1mLocal mode\033[0m, with \033[1mlocal package repository\033[0m enabled.\033[0m"
        if [[ -e /usr/bin/setup ]] ; then
            echo -e "To \033[1mswitch\033[0m to \033[1mOnline mode\033[0m:\033[1m\033[91m# rm /var/cache/pacman/pkg/archboot.db\033[0m\033[1m"
            echo ""
        fi
    fi
}

_enter_shell() {
    # dbus sources profiles again
    if ! pgrep -x dbus-run-sessio &>/dev/null; then
        cd /
        echo -e "Hit \033[1m\033[92mENTER\033[0m for \033[1mshell\033[0m login."
        read -r
        clear
    fi
}

_run_latest() {
    echo -e "\033[1mStarting\033[0m assembling of archboot environment \033[1mwithout\033[0m package cache..."
    echo -e "\033[1mRunning now: \033[92mupdate-installer -latest\033[0m"
    update-installer -latest | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_latest_install() {
    echo -e "\033[1mStarting\033[0m assembling of archboot environment \033[1mwith\033[0m package cache..."
    echo -e "\033[1mRunning now: \033[92mupdate-installer -latest-install\033[0m"
    update-installer -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_update_installer() {
    [[ -z $TTY ]] && TTY=$(tty)
    TTY=${TTY#/dev/}
    cd /
    echo -e "\033[1m\033[92mMemory checks run successfully:\033[0m"
    echo -e "\033[93mGo and get a cup of coffee. Depending on your system setup,\033[0m"
    echo -e "\033[93myou can \033[1mstart\033[0m\033[93m with your tasks in about \033[1m5\033[0m\033[93m minutes...\033[0m"
    echo ""
    if [[ "${TTY}" == "tty1" ]]; then
        echo -e "\033[1m\033[91m10 seconds\033[0;25m time to hit \033[1m\033[92mCTRL-C\033[0m to \033[1m\033[91mstop\033[0m the process \033[1m\033[1mnow...\033[0m"
        sleep 10
        echo ""
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 ]]; then
            _run_latest
        else
            _run_latest_install
        fi
    elif [[ "${TTY}" == "ttyS0" || "${TTY}" == "ttyAMA0" || "${TTY}" == "ttyUSB0" || "${TTY}" == "pts/0" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 ]]; then
            echo -e "Running \033[1m\033[92mupdate-installer -latest-install\033[0m on \033[1mtty1\033[0m, please wait...\033[0m"
        else
            echo -e "\033[1mRunning now: \033[92mupdate-installer -latest\033[0m"
        fi
        echo -e "\033[1mProgress is shown here...\033[0m"
    fi
}

if ! [[ -e "/.vconsole-run" ]]; then
    touch /.vconsole-run
    FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" | sed -e 's#.*:##g')"
    if [[ "${FB_SIZE}" -gt '1900' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    echo KEYMAP=us > /etc/vconsole.conf
    echo FONT=ter-v${SIZE}n >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
fi

if [[ -e /usr/bin/setup ]]; then
    _local_mode
    _enter_shell
    if ! [[ -e /tmp/.setup ]]; then
        setup
    fi
# latest image, fail if less than 2GB RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 1970000 ]]; then
    _welcome
    echo -e "\033[1m\033[91mMemory check failed:\033[0m"
    echo -e "\033[91m- Not engough memory detected! \033[0m"
    echo -e "\033[93m- Please add \033[1mmore\033[0m\033[93m than \033[1m2.0GB\033[0m\033[93m RAM.\033[0m"
    echo -e "\033[91mAborting...\033[0m"
    _enter_shell
# local image, fail if less than 2.6GB  RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 &&\
-e "/var/cache/pacman/pkg/archboot.db" ]]; then
    _welcome
    echo -e "\033[1m\033[91mMemory check failed:\033[0m"
    echo -e "\033[91m- Not engough memory detected! \033[0m"
    echo -e "\033[93m- Please add \033[1mmore\033[0m\033[93m than \033[1m2.6GB\033[0m\033[93m RAM.\033[0m"
    echo -e "\033[91mAborting...\033[0m"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
# vim: set ft=sh ts=4 sw=4 et:
