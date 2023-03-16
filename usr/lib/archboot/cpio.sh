#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
### overwriting mkinitcpio functions

add_firmware() {
    # add a firmware file to the image.
    #   $1: firmware path fragment

    local fw fwpath fwfile
    fwpath=/lib/firmware

    for fw; do
        # shellcheck disable=SC2154
        if ! compgen -G "${BUILDROOT}${fwpath}/${fw}"?(.*) &>/dev/null; then
            if fwfile="$(compgen -G "${fwpath}/${fw}"?(.*))"; then
                add_file "$fwfile"
            fi
        fi
    done
    return 0
}

add_module() {
    # Add a kernel module to the initcpio image. Dependencies will be
    # discovered and added.
    #   $1: module name

    local target='' module='' softdeps=() deps=() field='' value='' firmware=()

    if [[ "$1" == *\? ]]; then
        set -- "${1%?}"
    fi

    target="${1%.ko*}" target="${target//-/_}"

    # skip expensive stuff if this module has already been added
    (( _addedmodules["$target"] == 1 )) && return

    while IFS=':= ' read -r -d '' field value; do
        case "$field" in
            filename)
                # Only add modules with filenames that look like paths (e.g.
                # it might be reported as "(builtin)"). We'll defer actually
                # checking whether or not the file exists -- any errors can be
                # handled during module install time.
                if [[ "$value" == /* ]]; then
                    module="${value##*/}" module="${module%.ko*}"
                    _modpaths[".$value"]=1
                    _addedmodules["${module//-/_}"]=1
                fi
                ;;
            depends)
                IFS=',' read -r -a deps <<< "$value"
                map add_module "${deps[@]}"
                ;;
            firmware)
                firmware+=("$value")
                ;;
            softdep)
                read -ra softdeps <<<"$value"
                for module in "${softdeps[@]}"; do
                    [[ $module == *: ]] && continue
                    add_module "$module?"
                done
                ;;
        esac
    done < <(modinfo -b "$_optmoduleroot" -k "$KERNELVERSION" -0 "$target" 2>/dev/null)

    if (( ${#firmware[*]} )); then
        add_firmware "${firmware[@]}"
    fi
}

add_checked_modules() {
    # Add modules to the initcpio, filtered by the list of autodetected
    # modules.
    #   $@: arguments to all_modules

    local mods

    mapfile -t mods < <(all_modules "$@")

    map add_module "${mods[@]}"

    return $(( !${#mods[*]} ))
}

add_full_dir() {
    # Add a directory and all its contents, recursively, to the initcpio image.
    # No parsing is performed and the contents of the directory is added as is.
    #   $1: path to directory
    if [[ -n $1 && -d $1 ]]; then
        command tar -C /  --hard-dereference -cpf - ."$1" | tar -C "${BUILDROOT}" -xpf - || return 1
    fi
}

add_dir() {
    # add a directory (with parents) to $BUILDROOT
    #   $1: pathname on initcpio
    #   $2: mode (optional)
    local mode="${2:-755}"

    # shellcheck disable=SC2153
    if [[ -d "${BUILDROOT}${1}" ]]; then
        # ignore dir already exists
        return 0
    fi

    command mkdir -p -m "${mode}" "${BUILDROOT}${1}" || return 1
}

add_symlink() {
    # Add a symlink to the initcpio image. There is no checking done
    # to ensure that the target of the symlink exists.
    #   $1: pathname of symlink on image
    #   $2: absolute path to target of symlink (optional, can be read from $1)

    local name="$1" target="${2:-$1}" linkobject

    # find out the link target
    if [[ "$name" == "$target" ]]; then
        linkobject="$(find "$target" -prune -printf '%l')"
        # use relative path if the target is a file in the same directory as the link
        # anything more would lead to the insanity of parsing each element in its path
        if [[ "$linkobject" != *'/'* && ! -L "${name%/*}/${linkobject}" ]]; then
            target="$linkobject"
        else
            target="$(realpath -eq -- "$target")"
        fi
    elif [[ -L "$target" ]]; then
        target="$(realpath -eq -- "$target")"
    fi

    add_dir "${name%/*}"
    ln -sfn "$target" "${BUILDROOT}${name}"
}

add_file() {
    # Add a plain file to the initcpio image. No parsing is performed and only
    # the singular file is added.
    #   $1: path to file
    #   $2: destination on initcpio (optional, defaults to same as source)
    #   $3: mode

    # determine source and destination
    local src="$1" dest="${2:-$1}" mode="$3" srcrealpath

    if [[ ! -e "${BUILDROOT}${dest}" ]]; then
        if [[ "$src" != "$dest" ]]; then
            command tar --hard-dereference --transform="s|$src|$dest|" -C / -cpf - ."$src" | tar -C "${BUILDROOT}" -xpf - || return 1
        else
            command tar --hard-dereference -C / -cpf - ."$src" | tar -C "${BUILDROOT}" -xpf - || return 1
        fi
        if [[ -L "$src" ]]; then
            srcrealpath="$(realpath -- "$src")"
            add_file  "$srcrealpath" "$srcrealpath" "$mode"
        else
            if [[ -n $mode ]]; then
                command chmod "$mode" ${BUILDROOT}${dest}
            fi
        fi
    fi
}

add_binary() {
    # Add a binary file to the initcpio image. library dependencies will
    # be discovered and added.
    #   $1: path to binary
    #   $2: destination on initcpio (optional, defaults to same as source)

    local line='' regex='' binary='' dest='' mode='' sodep=''

    if [[ "${1:0:1}" != '/' ]]; then
        binary="$(type -P "$1")"
    else
        binary="$1"
    fi

    dest="${2:-$binary}"

    add_file "$binary" "$dest"

    # non-binaries
    if ! lddout="$(ldd "$binary" 2>/dev/null)"; then
        return 0
    fi
    # resolve sodeps
    regex='^(|.+ )(/.+) \(0x[a-fA-F0-9]+\)'
    while read -r line; do
        if [[ "$line" =~ $regex ]]; then
            sodep="${BASH_REMATCH[2]}"
        elif [[ "$line" = *'not found' ]]; then
            error "binary dependency '%s' not found for '%s'" "${line%% *}" "$1"
            (( ++_builderrors ))
            continue
        fi

        if [[ -f "$sodep" && ! -e "${BUILDROOT}${sodep}" ]]; then
            add_file "$sodep" "$sodep"
        fi
    done <<< "$lddout"

    return 0
}

install_modules() {

    command tar --hard-dereference -C / -cpf - "$@" | tar -C "${BUILDROOT}" -xpf -

    msg "Generating module dependencies"
    map add_file "$_d_kmoduledir"/modules.{builtin,builtin.modinfo,order}
    depmod -b "$BUILDROOT" "$KERNELVERSION"

    # remove all non-binary module.* files (except devname for on-demand module loading)
    rm "${BUILDROOT}${_d_kmoduledir}"/modules.!(*.bin|devname|softdep)
}
