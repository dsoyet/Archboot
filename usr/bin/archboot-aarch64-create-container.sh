#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/common.sh
source /usr/lib/archboot/container.sh
_ARCHBOOT="archboot-arm"
_KEYRING="archlinuxarm"
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
echo "Starting container creation ..."
[[ -d "${1}" ]] || (echo "Create directory ${1} ..."; mkdir "${1}")
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _prepare_pacman "${1}" || exit 1
    _install_base_packages "${1}" || exit 1
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _install_archboot "${1}" || exit 1
    _umount_special "${1}" || exit 1
    _generate_locales "${1}"
    _clean_container "${1}"
    _clean_archboot_cache
    _generate_keyring "${1}" || exit 1
    _copy_mirrorlist_and_pacman_conf "${1}"
    _change_pacman_conf "${1}" || exit 1
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _aarch64_pacman_chroot "${1}" || exit 1
    _aarch64_install_base_packages "${1}" || exit 1
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _aarch64_install_archboot "${1}" || exit 1
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _generate_locales "${1}"
    _clean_container "${1}" 2>/dev/null
fi
_reproducibility "${1}"
_set_hostname "${1}" || exit 1
echo "Finished container setup in ${1} ."
