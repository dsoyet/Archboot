#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
_ARCHBOOT="archboot-riscv"
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
echo "Starting container creation ..."
[[ -d "${1}" ]] || (echo "Create directory ${1} ..."; mkdir "${1}")
if [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
    _cachedir_check
    _create_pacman_conf "${1}"
    _prepare_pacman "${1}" || exit 1
    _pacman_parameters "${1}"
    _install_base_packages "${1}" || exit 1
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _install_archboot "${1}" || exit 1
    _clean_cache "${1}"
    _umount_special "${1}" || exit 1
    _fix_groups "${1}"
    _clean_container "${1}"
    _clean_archboot_cache
    _generate_keyring "${1}" || exit 1
    _copy_mirrorlist_and_pacman_conf "${1}"
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _pacman_chroot "${1}" "${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}" "${_PACMAN_RISCV64_CHROOT}" || exit 1
    _create_pacman_conf "${1}" "use_container_config"
    _pacman_parameters "${1}" "use_binfmt"
    _install_base_packages "${1}" "use_binfmt" || exit 1
    _install_archboot "${1}" "use_binfmt" || exit 1
    _fix_groups "${1}"
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _clean_container "${1}" 2>/dev/null
fi
_change_pacman_conf "${1}" || exit 1
_reproducibility "${1}"
_set_hostname "${1}" || exit 1
echo "Finished container setup in ${1} ."
