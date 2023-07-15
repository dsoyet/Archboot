#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_check_root_password() {
    # check if empty password is set
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        _dialog --infobox "Setup detected no password set for root user,\nplease set new password now." 6 50
        sleep 3
        _set_password || return 1
    fi
    # check if account is locked
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        _dialog --infobox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        _set_password || return 1
    fi
}

_set_mkinitcpio() {
    _HOOK_ERROR=""
    ${_EDITOR} "${_DESTDIR}""${_FILE}"
    #shellcheck disable=SC2013
    for i in $(grep ^HOOKS "${_DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
        [[ -e ${_DESTDIR}/usr/lib/initcpio/install/${i} ]] || _HOOK_ERROR=1
    done
    if [[ -n "${_HOOK_ERROR}" ]]; then
        _dialog --title " ERROR " --infobox "Detected error in 'HOOKS=' line,\nplease correct HOOKS= in /etc/mkinitcpio.conf!" 6 70
        sleep 5
    else
        _run_mkinitcpio
    fi
}

_set_locale() {
    if [[ -z ${_S_LOCALE} ]]; then
        _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER More"
        _CHECK_LOCALES="$(grep 'UTF' "${_DESTDIR}"/etc/locale.gen | sed -e 's:#::g' -e 's: UTF-8.*$::g')"
        _OTHER_LOCALES=""
        for i in ${_CHECK_LOCALES}; do
            _OTHER_LOCALES="${_OTHER_LOCALES} ${i} -"
        done
        #shellcheck disable=SC2086
        _dialog --no-cancel --title " Locale " --menu "" 12 40 7 ${_LOCALES} 2>${_ANSWER} || return 1
        _SET_LOCALE=$(cat "${_ANSWER}")
        if [[ "${_SET_LOCALE}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            _dialog --no-cancel --title " Other Locale " --menu "" 18 40 12 ${_OTHER_LOCALES} 2>${_ANSWER} || return 1
            _SET_LOCALE=$(cat "${_ANSWER}")
        fi
        sed -i -e "s#LANG=.*#LANG=${_SET_LOCALE}.UTF-8#g" "${_DESTDIR}"/etc/locale.conf
        _dialog --infobox "Setting locale LANG=${_SET_LOCALE}.UTF-8 on installed system..." 3 70
        _S_LOCALE=1
        sleep 2
        _auto_set_locale
        _run_locale_gen
    fi
}

_set_password() {
    _PASSWORD=""
    _PASS=""
    _PASS2=""
    while [[ -z "${_PASSWORD}" ]]; do
        while [[ -z "${_PASS}" ]]; do
            _dialog --title " New Root Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS=$(cat "${_ANSWER}")
        done
        while [[ -z  "${_PASS2}" ]]; do
            _dialog --title " Retype Root Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_PASS}" == "${_PASS2}" ]]; then
            _PASSWORD=${_PASS}
            echo "${_PASSWORD}" > /tmp/.password
            echo "${_PASSWORD}" >> /tmp/.password
            _PASSWORD=/tmp/.password
        else
            _dialog --title " ERROR " --infobox "Password didn't match, please enter again." 5 50
            _PASSWORD=""
            _PASS=""
            _PASS2=""
        fi
    done
    chroot "${_DESTDIR}" passwd root < /tmp/.password &>"${_NO_LOG}"
    rm /tmp/.password
}

_run_mkinitcpio() {
    _dialog --infobox "Rebuilding initramfs on installed system..." 3 70
    _chroot_mount
    echo "Initramfs progress..." > /tmp/mkinitcpio.log
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}"-"${_RUNNING_ARCH}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log &>"${_NO_LOG}"
    else
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log &>"${_NO_LOG}"
    fi
    echo $? > /tmp/.mkinitcpio-retcode
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        echo -e "\nMkinitcpio FAILED." >>/tmp/mkinitcpio.log
    else
        echo -e "\nMkinitcpio Complete." >>/tmp/mkinitcpio.log
    fi
    local _result=''
    # mkinitcpio finished, display scrollable output on error
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        _result="Mkinitcpio Failed (see errors below)"
        _dialog --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/mkinitcpio.log" 18 70 || return 1
    fi
    rm /tmp/.mkinitcpio-retcode
    _chroot_umount
    sleep 2
}

_run_locale_gen() {
    _dialog --infobox "Rebuilding glibc locales on installed system..." 3 70
    _locale_gen
    sleep 2
}
# vim: set ft=sh ts=4 sw=4 et:
