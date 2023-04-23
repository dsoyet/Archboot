#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_APPNAME=${0##*/}
_usage () {
    echo "Check on missing binaries in archboot environment"
    echo "-------------------------------------------------"
    echo "usage: ${_APPNAME} <package>"
    echo "This will check binaries from package, if they exist"
    echo "and report missing to binary.txt"
    exit 0
}
[[ -z "${1}" ]] && _usage
if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi
# update pacman db first
pacman -Sy
if [[ "${1}" == "base" ]]; then
    _PACKAGE="$(pacman -Qi base | grep Depends | cut -d ":" -f2)"
else
    _PACKAGE="${1}"
fi
echo "${_PACKAGE}" >binary.txt
#shellcheck disable=SC2086
for i in $(pacman -Ql ${_PACKAGE} | grep "/usr/bin/..*"$ | cut -d' ' -f2); do
	command -v "${i}" &>/dev/null || echo "${i}" >>binary.txt
done
# vim: set ft=sh ts=4 sw=4 et: archboot-bootloader.sh archboot-copy-mountpoint.sh archboot-hwsim.sh archboot-km.sh archboot-mkkeys.sh archboot-quickinst.sh archboot-restore-usbstick.sh archboot-rsync-backup.sh archboot-secureboot-keys.sh archboot-setup.sh archboot-tz.sh archboot-update-installer.sh
