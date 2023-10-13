#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-cpio.sh - modular tool for building an initramfs image
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

_CONFIG=""
_CPIO=/usr/lib/archboot/cpio/hooks/
_GENERATE_IMAGE=""
_TARGET_DIR=""
declare -A _INCLUDED_MODS _MOD_PATH

_usage() {
    cat <<EOF
ARCHBOOT CPIO
-------------
Tool for creating an archboot initramfs image.

 -h               Display this message and exit

 -c <config>      Use <config> file
 -k <kernel>      Use specified <kernel>

 -g <path>        Generate cpio image and write to specified <path>
 -d <dir>         Generate image into <dir>

usage: ${0##*/} <options>
EOF
    exit 0
}

_abort() {
    echo "Error:" "$@"
    if [[ -n "$_d_workdir" ]]; then
        rm -rf -- "$_d_workdir"
    fi
    exit 1
}

_builtin_modules() {
    # Prime the _INCLUDED_MODS list with the builtins for this kernel.
    # kmod>=27 and kernel >=5.2 required!
    while IFS=.= read -rd '' _MODULE _FIELD _VALUE; do
        _INCLUDED_MODS[${_MODULE//-/_}]=2
        case "$_FIELD" in
            alias)  _INCLUDED_MODS["${_VALUE//-/_}"]=2
                    ;;
        esac
    done <"${_MODULE_DIR}/modules.builtin.modinfo"
}

_map() {
    _RETURN=0
    for i in "${@:2}"; do
        # shellcheck disable=SC1105,SC2210,SC2035
        "${1}" "${i}" || (( $# > 255 ? _RETURN=1 : ++_RETURN ))
    done
    return "${_RETURN}"
}

_filter_modules() {
    # Add modules to the initcpio, filtered by grep.
    #   $@: filter arguments to grep
    #   -f FILTER: ERE to filter found modules
    local -i _COUNT=0
    local _MOD_INPUT="" OPTIND="" OPTARG="" _MOD_FILTER=()
    while getopts ':f:' _FLAG; do
        [[ "${_FLAG}" = "f" ]] && _MOD_FILTER+=("$OPTARG")
    done
    shift $(( OPTIND - 1 ))
    # shellcheck disable=SC2154
    while read -r -d '' _MOD_INPUT; do
        (( ++_COUNT ))
        for f in "${_MOD_FILTER[@]}"; do
            [[ "${_MOD_INPUT}" =~ $f ]] && continue 2
        done
        _MOD_INPUT="${_MOD_INPUT##*/}" _MOD_INPUT="${_MOD_INPUT%.ko*}"
        printf '%s\n' "${_MOD_INPUT//-/_}"
    done < <(find "${_MODULE_DIR}" -name '*.ko*' -print0 2>"${_NO_LOG}" | grep -EZz "$@")
    (( _COUNT ))
}

_all_modules() {
    # Add modules to the initcpio.
    #   $@: arguments to all_modules
    local _MOD_INPUT
    local -a _MODS
    mapfile -t _MODS < <(_filter_modules "$@")
    _map _module "${_MODS[@]}"
    return $(( !${#_MODS[*]} ))
}

_firmware() {
    # add a firmware file to the image.
    #   $1: firmware path fragment
    local _FW _FW_DIR
    local -a _FW_BIN
    _FW_DIR=/lib/firmware
    for _FW; do
        # shellcheck disable=SC2154,SC2153
        if ! compgen -G "${_ROOTFS}${_FW_DIR}/${_FW}?(.*)" &>"${_NO_LOG}"; then
            if read -r _FW_BIN < <(compgen -G "${_FW_DIR}/${_FW}?(.*)"); then
                _map _file "${_FW_BIN[@]}"
                break
            fi
        fi
    done
    return 0
}

_module() {
    # Add a kernel module to the rootfs. Dependencies will be
    # discovered and added.
    #   $1: module name
    local _CHECK="" _MOD="" _SOFT=() _DEPS=() _FIELD="" _VALUE="" _FW=()
    if [[ "${1}" == *\? ]]; then
        set -- "${1%?}"
    fi
    _CHECK="${1%.ko*}" _CHECK="${_CHECK//-/_}"
    # skip expensive stuff if this module has already been added
    (( _INCLUDED_MODS["${_CHECK}"] == 1 )) && return
    while IFS=':= ' read -r -d '' _FIELD _VALUE; do
        case "${_FIELD}" in
            filename)
                # Only add modules with filenames that look like paths (e.g.
                # it might be reported as "(builtin)"). We'll defer actually
                # checking whether or not the file exists -- any errors can be
                # handled during module install time.
                if [[ "${_VALUE}" == /* ]]; then
                    _MOD="${_VALUE##*/}" _MOD="${_MOD%.ko*}"
                    _MOD_PATH[".${_VALUE}"]=1
                    _INCLUDED_MODS["${_MOD//-/_}"]=1
                fi
                ;;
            depends)
                IFS=',' read -r -a _DEPS <<< "${_VALUE}"
                _map _module "${_DEPS[@]}"
                ;;
            firmware)
                _FW+=("${_VALUE}")
                ;;
            softdep)
                read -ra _SOFT <<<"${_VALUE}"
                for i in "${_SOFT[@]}"; do
                    [[ ${i} == *: ]] && continue
                    _module "${i}?"
                done
                ;;
        esac
    done < <(modinfo -b "${_MODULE_DIR}" -k "${_KERNELVERSION}" -0 "${_CHECK}" 2>"${_NO_LOG}")
    if (( ${#_FW[*]} )); then
        _firmware "${_FW[@]}"
    fi
}

_full_dir() {
    # Add a directory and all its contents, recursively, to the rootfs.
    # No parsing is performed and the contents of the directory is added as is.
    #   $1: path to directory
    if [[ -n "${1}" && -d "${1}" ]]; then
        command tar -C / --hard-dereference -cpf - ."${1}" | tar -C "${_ROOTFS}" -xpf - || return 1
    fi
}

_dir() {
    # add a directory (with parents) to $BUILDROOT
    #   $1: pathname on initcpio
    #   $2: mode (optional)
    local _MODE="${2:-755}"
    # shellcheck disable=SC2153
    if [[ -d "${_ROOTFS}${1}" ]]; then
        # ignore dir already exists
        return 0
    fi
    command mkdir -p -m "${_MODE}" "${_ROOTFS}${1}" || return 1
}

_symlink() {
    # Add a symlink to the rootfs. There is no checking done
    # to ensure that the target of the symlink exists.
    #   $1: pathname of symlink on image
    #   $2: absolute path to target of symlink (optional, can be read from $1)
    local _LINK_NAME="${1}" _LINK_SOURCE="${2:-$1}" _LINK_DEST
    # find out the link target
    if [[ "${_LINK_NAME}" == "${_LINK_SOURCE}" ]]; then
        _LINK_DEST="$(find "${_LINK_SOURCE}" -prune -printf '%l')"
        # use relative path if the target is a file in the same directory as the link
        # anything more would lead to the insanity of parsing each element in its path
        if [[ "${_LINK_DEST}" != *'/'* && ! -L "${_LINK_NAME%/*}/${_LINK_DEST}" ]]; then
            _LINK_SOURCE="${_LINK_DEST}"
        else
            _LINK_SOURCE="$(realpath -eq -- "${_LINK_SOURCE}")"
        fi
    elif [[ -L "${_LINK_SOURCE}" ]]; then
        _LINK_SOURCE="$(realpath -eq -- "${_LINK_SOURCE}")"
    fi
    _dir "${_LINK_NAME%/*}"
    command ln -sfn "${_LINK_SOURCE}" "${_ROOTFS}${_LINK_NAME}"
}

_file() {
    # Add a plain file to the rootfs. No parsing is performed and only
    # the singular file is added.
    #   $1: path to file
    #   $2: destination on initcpio (optional, defaults to same as source)
    #   $3: mode
    # determine source and destination
    local _SRC="${1}" _DEST="${2:-$1}" _MODE="${3}"
    if [[ ! -e "${_ROOTFS}${_DEST}" ]]; then
        if [[ "${_SRC}" != "${_DEST}" ]]; then
            command tar --hard-dereference --transform="s|${_SRC}|${_DEST}|" -C / -cpf - ."${_SRC}" | tar -C "${_ROOTFS}" -xpf - || return 1
        else
            command tar --hard-dereference -C / -cpf - ."${_SRC}" | tar -C "${_ROOTFS}" -xpf - || return 1
        fi
        if [[ -L "${_SRC}" ]]; then
            _LINK_SOURCE="$(realpath -- "${_SRC}")"
            _file  "${_LINK_SOURCE}" "${_LINK_SOURCE}" "${_MODE}"
        else
            if [[ -n "${_MODE}" ]]; then
                command chmod "${_MODE}" "${_ROOTFS}${_DEST}"
            fi
        fi
    fi
}

_binary() {
    # Add a binary file to the rootfs. library dependencies will
    # be discovered and added.
    #   $1: path to binary
    #   $2: destination on rootfs (optional, defaults to same as source)
    if [[ "${1:0:1}" != '/' ]]; then
        _BIN="$(type -P "${1}")"
    else
        _BIN="${1}"
    fi
    _ROOTFS_BIN="${2:-${_BIN}}"
    _file "${_BIN}" "${_ROOTFS_BIN}"
    # non-binaries
    if ! _LDD="$(ldd "${_BIN}" 2>"${_NO_LOG}")"; then
        return 0
    fi
    # resolve libraries
    _REGULAR_EXPRESSION='^(|.+ )(/.+) \(0x[a-fA-F0-9]+\)'
    while read -r i; do
        if [[ "${i}" =~ ${_REGULAR_EXPRESSION} ]]; then
            _LIB="${BASH_REMATCH[2]}"
        fi
        if [[ -f "${_LIB}" && ! -e "${_ROOTFS}${_LIB}" ]]; then
            _file "${_LIB}" "${_LIB}"
        fi
    done <<< "${_LDD}"
    return 0
}

_init_rootfs() {
    # creates a temporary directory for the rootfs and initialize it with a
    # basic set of necessary directories and symlinks
    _TMPDIR="$(mktemp -d --tmpdir mkinitcpio.XXXX)"
    _ROOTFS="${2:-${_TMPDIR}/root}"
    # base directory structure
    install -dm755 "${_ROOTFS}"/{new_root,proc,sys,dev,run,tmp,var,etc,usr/{local{,/bin,/sbin,/lib},lib,bin}}
    ln -s "usr/lib" "${_ROOTFS}/lib"
    ln -s "bin" "${_ROOTFS}/usr/sbin"
    ln -s "usr/bin" "${_ROOTFS}/bin"
    ln -s "usr/bin" "${_ROOTFS}/sbin"
    ln -s "/run" "${_ROOTFS}/var/run"
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
            ln -s "lib" "${_ROOTFS}/usr/lib64"
            ln -s "usr/lib" "${_ROOTFS}/lib64"
    fi
    # kernel module dir
    [[ "${_KERNELVERSION}" != 'none' ]] && install -dm755 "${_ROOTFS}/usr/lib/modules/${_KERNELVERSION}/kernel"
    # mount tables
    ln -s ../proc/self/mounts "${_ROOTFS}/etc/mtab"
    : >"${_ROOTFS}/etc/fstab"
    # add a blank ld.so.conf to keep ldconfig happy
    : >"${_ROOTFS}/etc/ld.so.conf"
    echo "${_TMPDIR}"
}

_run_hook() {
    # find script in install dirs
    # shellcheck disable=SC2154
    if ! _HOOK_FILE="$(PATH="${_CPIO}" type -P "${1}")"; then
        _abort "Hook ${1} cannot be found!"
        return 1
    fi
    # source
    unset -f _run
    # shellcheck disable=SC1090
    . "${_HOOK_FILE}"
    if ! declare -f _run >"${_NO_LOG}"; then
        _abort "Hook ${_HOOK_FILE} has no run function!"
        return 1
    fi
    # run
    echo "Running hook:" "${_HOOK_FILE##*/}"
    _run
}

_install_modules() {
    command tar --hard-dereference -C / -cpf - "$@" | tar -C "${_ROOTFS}" -xpf -
    echo "Generating module dependencies..."
    _map _file "${_MODULE_DIR}"/modules.{builtin,builtin.modinfo,order}
    depmod -b "${_ROOTFS}" "${_KERNELVERSION}"
    # remove all non-binary module.* files (except devname for on-demand module loading
    # and builtin.modinfo for checking on builtin modules)
    rm "${_ROOTFS}${_MODULE_DIR}"/modules.!(*.bin|*.modinfo|devname|softdep)
}

_create_cpio() {
    case "${_COMP}" in
        cat)    echo "Creating uncompressed image: ${_GENERATE_IMAGE}"
                unset _COMP_OPTS
                ;;
        *)      echo "Creating ${_COMP} compressed image: ${_GENERATE_IMAGE}"
                ;;&
        xz)     _COMP_OPTS=('-T0' '--check=crc32' "${_COMP_OPTS[@]}")
                ;;
        lz4)    _COMP_OPTS=('-l' "${_COMP_OPTS[@]}")
                ;;
        zstd)   _COMP_OPTS=('-T0' "${_COMP_OPTS[@]}")
                ;;
    esac

    # Reproducibility: set all timestamps to 0
    pushd "${_ROOTFS}" >"${_NO_LOG}" || return
    find . -mindepth 1 -execdir touch -hcd "@0" "{}" +
    find . -mindepth 1 -printf '%P\0' | sort -z | LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            ${_COMP} "${_COMP_OPTS[@]}" > "${_GENERATE_IMAGE}" || _abort "Image creation failed!"
    popd >"${_NO_LOG}" || return
}
