#! /bin/bash
DIRECTORY="$(date +%Y.%m)"
ARCH="aarch64"
BUILDDIR="/home/tobias/Arch/iso/${ARCH}"
SERVER="pkgbuild.com"
HOME="/home/tpowa/"
SERVER_DIR="/home/tpowa/public_html/archboot-images"
USER="tobias"
GROUP="users"
GPG="--detach-sign --batch --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

### check for tpowa's build server
if [[ ! "$(cat /etc/hostname)" == "T-POWA-LX" ]]; then
    echo "This script should only be run on tpowa's build server. Aborting..."
    exit 1
fi

# create release in "${BUILDDIR}"
cd "${BUILDDIR}"
[[ -e "${DIRECTORY}" ]] && rm -r "${DIRECTORY}"
archboot-"${ARCH}"-release.sh "${DIRECTORY}"
# set user rights on files
chown -R "${USER}" "${DIRECTORY}"
chgrp -R "${GROUP}" "${DIRECTORY}"
cd "${DIRECTORY}"
# remove sha256sum and install image
rm sha256sum.txt
rm ArchLinuxARM-aarch64-latest.tar.gz
# sign files and create new sha256sum.txt
for i in *; do
    [[ -f "${i}" ]] && sudo -u "${USER}" gpg ${GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
for i in boot/*; do
    [[ -f "${i}" ]] && sudo -u "${USER}" gpg ${GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
cd ..
# copy files to server
sudo -u "${USER}" scp -r "${DIRECTORY}" "${SERVER}":"${HOME}"
# move files on server, create symlink and remove 3 month old release
sudo -u "${USER}" ssh "${SERVER}" <<EOF
rm -r "${SERVER_DIR}"/"${ARCH}"/"${DIRECTORY}"
rm -r "${SERVER_DIR}"/"${ARCH}"/"$(date -d "$(date +) - 3 month" +%Y.%m)"
mv "${DIRECTORY}" "${SERVER_DIR}"/"${ARCH}"
cd "${SERVER_DIR}"/"${ARCH}"
rm latest
ln -s "${DIRECTORY}" latest
EOF
