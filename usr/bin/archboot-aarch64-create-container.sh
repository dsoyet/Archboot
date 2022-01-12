#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR=""$1"/var/cache/pacman/pkg"
_CLEANUP_CACHE=""
_SAVE_RAM=""
_LINUX_FIRMWARE=""
_DIR=""
_LOG=""
LATEST_ARM64="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

usage () {
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "This will create an archboot container for an archboot image."
	echo "Usage: ${_BASENAME} <directory> <options>"
	echo " Options:"
	echo "  -cc    Cleanup container eg. remove manpages, includes ..."
	echo "  -cp    Cleanup container package cache"
        echo "  -lf    add linux-firmware to container"
	echo "  -alf   add archboot-linux-firmware to container"
	echo "  -log   show logging on active tty"
	exit 0
}

[[ -z "${1}" ]] && usage

_DIR="$1"

while [ $# -gt 0 ]; do
	case ${1} in
		-cc|--cc) _SAVE_RAM="1" ;;
		-cp|--cp) _CLEANUP_CACHE="1" ;;
		-lf|--lf) _LINUX_FIRMWARE="linux-firmware" ;;
		-alf|--alf) _LINUX_FIRMWARE="archboot-linux-firmware" ;;
                -log|--log) _LOG="yes" ;;
        esac
	shift
done

if [[ "${_LOG}" == "yes" ]]; then
    _LOG=""
else
    _LOG=">/dev/null 2>&1"
fi

[[ -z "${_LINUX_FIRMWARE}" ]] && _LINUX_FIRMWARE="linux-firmware"

### check for root
if ! [[ ${UID} -eq 0 ]]; then
	echo "ERROR: Please run as root user!"
	exit 1
fi

echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir "${_DIR}"
if [[ "$(uname -m)" == "aarch64" ]]; then
    # prepare pacman dirs
    echo "Create directories in ${_DIR} ..."
    mkdir -p "${_DIR}"/var/lib/pacman
    mkdir -p "${_CACHEDIR}"
    [[ -e "${_DIR}/proc" ]] || mkdir -m 555 "${_DIR}/proc"
    [[ -e "${_DIR}/sys" ]] || mkdir -m 555 "${_DIR}/sys"
    [[ -e "${_DIR}/dev" ]] || mkdir -m 755 "${_DIR}/dev"
    # mount special filesystems to ${_DIR}
    echo "Mount special filesystems in ${_DIR} ..."
    mount proc ""${_DIR}"/proc" -t proc -o nosuid,noexec,nodev 
    mount sys ""${_DIR}"/sys" -t sysfs -o nosuid,noexec,nodev,ro 
    mount udev ""${_DIR}"/dev" -t devtmpfs -o mode=0755,nosuid 
    mount devpts ""${_DIR}"/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm ""${_DIR}"/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    # install archboot
    echo "Installing packages base firmware and archboot to ${_DIR} ..."
    pacman --root "${_DIR}" -Sy base archboot-arm "${_LINUX_FIRMWARE}" --noconfirm --ignore systemd-resolvconf --cachedir "${_PWD}"/"${_CACHEDIR}" ${_LOG}
    # umount special filesystems
    echo "Umount special filesystems in to ${_DIR} ..."
    umount -R ""${_DIR}"/proc"
    umount -R ""${_DIR}"/sys"
    umount -R ""${_DIR}"/dev"
fi
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "Downloading archlinuxarm aarch64..."
    ! [[ -f ArchLinuxARM-aarch64-latest.tar.gz ]] && wget ${LATEST_ARM64} ${_LOG}
    bsdtar -xf ArchLinuxARM-aarch64-latest.tar.gz -C "${_DIR}"
    echo "Removing installation tarball ..."
    rm ArchLinuxARM-aarch64-latest.tar.gz
fi
# generate locales
echo "Create locales in container ..."
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen" ${_LOG}
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen" ${_LOG}
systemd-nspawn -D "${_DIR}" locale-gen ${_LOG}
# generate pacman keyring
echo "Generate pacman keyring in container ..."
systemd-nspawn -D "${_DIR}" pacman-key --init ${_LOG}
systemd-nspawn -D "${_DIR}" pacman-key --populate archlinuxarm ${_LOG}
# disable checkspace option in pacman.conf, to allow to install packages in environment
sed -i -e 's:^CheckSpace:#CheckSpace:g' "${_DIR}"/etc/pacman.conf
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}"/etc/pacman.conf
if [[ "$(uname -m)" == "x86_64" ]]; then
    # fix network in container
    rm "${_DIR}/etc/resolv.conf"
    echo "nameserver 8.8.8.8" > "${_DIR}/etc/resolv.conf"
    # update container to latest packages
    echo "Update container to latest packages..."
    systemd-nspawn -D "${_DIR}" pacman -Syu --noconfirm ${_LOG}
    # remove linux hook to speedup
    echo "Remove 60-linux-aarch64.hook from container..."
    rm "${_DIR}/usr/share/libalpm/hooks/60-linux-aarch64.hook"
    echo "Installing archboot-arm and firmware to container..."
    systemd-nspawn -D "${_DIR}" /bin/bash -c "yes | pacman -S archboot-arm ${_LINUX_FIRMWARE}" ${_LOG}
fi
echo "Setting hostname to archboot ..."
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo archboot > /etc/hostname" ${_LOG}
if [[ "${_SAVE_RAM}" ==  "1" ]]; then
    # clean container from not needed files
    echo "Clean container, delete not needed files from ${_DIR} ..."
    rm -r "${_DIR}"/usr/include
    rm -r "${_DIR}"/usr/share/{man,doc}
fi
if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
    # clean cache
    echo "Clean pacman cache from ${_DIR} ..."
    rm -r "${_DIR}"/var/cache/pacman
fi
echo "Finished container setup in ${_DIR} ."
