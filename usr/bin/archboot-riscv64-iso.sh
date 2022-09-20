#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/iso.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_riscv64_check
[[ "${_GENERATE}" == "1" ]] || _usage
_config
echo "Starting Image creation ..."
_fix_mkinitcpio
_prepare_kernel_initramfs_files_RISCV64 || exit 1
_prepare_extlinux_conf || exit 1
_reproducibility
_prepare_uboot_image || exit 1
_create_cksum || exit 1
_cleanup_iso || exit 1
echo "Finished Image creation."
