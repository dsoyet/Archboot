#!/usr/bin/env bash
# Created by Tobias Powalowski <tpowa@archlinux.org>
# Settings
APPNAME=$(basename "${0}")
CONFIG=""
TARNAME=""

export TEMPDIR=$(mktemp -d tarball-helper.XXXX)

usage ()
{
    echo "${APPNAME}: usage"
    echo "  -c=CONFIG        Use CONFIG file"
    echo "  -t=TARNAME       Generate a tar image instead of an iso image"
    echo "  -h               This message."
    exit 1
}

[ "$1" == "" ] && usage

while [ $# -gt 0 ]; do
	case $1 in
		-c=*|--c=*) CONFIG="$(echo $1 | awk -F= '{print $2;}')" ;;
		-t=*|--t=*) TARNAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

if [ "${TARNAME}" = "" ]; then 
	echo "ERROR: No image name specified, please use the -t option"
	exit 1
fi

if [ ! -f "${CONFIG}" ]; then
	echo "config file '${CONFIG}' cannot be found, aborting..."
	exit 1
fi

. "${CONFIG}"
export RUNPROGRAM="${APPNAME}"
if [[ "$(uname -m)" == "x86_64" ]]; then
    # export for mkinitcpio
    [ -n "${APPENDBOOTMESSAGE}" ] && export APPENDBOOTMESSAGE
    [ -n "${APPENDOPTIONSBOOTMESSAGE}" ] && export APPENDOPTIONSBOOTMESSAGE

    export BOOTDIRNAME="boot/syslinux"

    [ "${BOOTMESSAGE}" = "" ] && export BOOTMESSAGE=$(mktemp bootmessage.XXXX)
    [ "${OPTIONSBOOTMESSAGE}" = "" ] && export OPTIONSBOOTMESSAGE=$(mktemp optionsbootmessage.XXXX)

    # begin script
    mkdir -p "${TEMPDIR}/${BOOTDIRNAME}/"
    # prepare syslinux bootloader
    install -m755 /usr/lib/syslinux/bios/isolinux.bin ${TEMPDIR}/${BOOTDIRNAME}/isolinux.bin
    for i in /usr/lib/syslinux/bios/*; do
        [ -f $i ] && install -m644 $i ${TEMPDIR}/${BOOTDIRNAME}/$(basename $i)
    done
    install -m644 /usr/share/hwdata/pci.ids ${TEMPDIR}/${BOOTDIRNAME}/pci.ids
    install -m644 $BACKGROUND ${TEMPDIR}/${BOOTDIRNAME}/splash.png

    # Use config file
    echo ":: Creating syslinux.cfg ..."
    if [ "${SYSLINUXCFG}" = "" ]; then
            echo "No syslinux.cfg file specified, aborting ..."
            exit 1
    else
            sed "s|@@PROMPT@@|${PROMPT}|g;s|@@TIMEOUT@@|${TIMEOUT}|g;s|@@KERNEL_BOOT_OPTIONS@@|${KERNEL_BOOT_OPTIONS}|g" \
                    ${SYSLINUXCFG} > ${TEMPDIR}/${BOOTDIRNAME}/syslinux.cfg
            [ ! -s ${TEMPDIR}/${BOOTDIRNAME}/syslinux.cfg ] && echo "No syslinux.cfg found" && exit 1
    fi
fi
if [[ "$(uname -m)" == "aarch64" ]]; then
    mkdir -p "${TEMPDIR}/boot"
fi

# generate initramdisk
echo ":: Calling mkinitcpio CONFIG=${MKINITCPIO_CONFIG} ..." 
echo ":: Creating initramdisk ..."
	mkinitcpio -c ${MKINITCPIO_CONFIG} -k ${ALL_kver} -g ${TEMPDIR}/boot/initrd.img
echo ":: Using ${ALL_kver} as image kernel ..."
    install -m644 ${ALL_kver} ${TEMPDIR}/boot/vmlinuz
if [[ "$(uname -m)" == "x86_64" ]]; then
    install -m644 ${BOOTMESSAGE} ${TEMPDIR}/${BOOTDIRNAME}/boot.msg
    install -m644 ${OPTIONSBOOTMESSAGE} ${TEMPDIR}/${BOOTDIRNAME}/options.msg
    [ ! -s ${TEMPDIR}/${BOOTDIRNAME}/boot.msg ] && echo 'ERROR:no boot.msg found, aborting!' && exit 1
    [ ! -s ${TEMPDIR}/${BOOTDIRNAME}/options.msg ] && echo 'ERROR:no options.msg found, aborting!' && exit 1
fi
if [[ "$(uname -m)" == "aarch64" ]]; then
    	cp -r /boot/dtbs ${TEMPDIR}/boot
fi
# create image
if ! [ "${TARNAME}" = "" ]; then
	echo ":: Creating tar image ..."
	[ -e ${TARNAME} ] && rm ${TARNAME}
	tar cfv ${TARNAME} ${TEMPDIR} > /dev/null 2>&1 && echo ":: tar Image succesfull created at ${TARNAME}"
fi
# clean directory
rm -r ${TEMPDIR}
if [[ "$(uname -m)" == "x86_64" ]]; then
    rm ${BOOTMESSAGE}
    rm ${OPTIONSBOOTMESSAGE}
fi
