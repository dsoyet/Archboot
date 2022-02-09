#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/iso_functions
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_x86_64_check
[[ "${_GENERATE}" == "1" ]] || _usage
_config
echo "Starting ISO creation ..."
_prepare_kernel_initramfs_files
_prepare_fedora_shim_bootloaders_x86_64 || exit 1
_download_uefi_shell_tianocore || exit 1
_prepare_efitools_uefi || exit 1
_prepare_uefi_X64_GRUB_USB_files || exit 1
_prepare_uefi_IA32_GRUB_USB_files || exit 1
_prepare_uefi_image || exit 1
_grub_mkrescue || exit 1
_create_cksum || exit 1
_cleanup_iso || exit 1
echo "Finished ISO creation."
