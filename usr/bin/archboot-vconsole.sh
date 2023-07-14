#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.vconsole"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Vconsole Configuration"
_LIST_MAPS="localectl list-keymaps --no-pager"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_abort() {
    if _dialog --yesno "Abort Arch Linux Vconsole Configuration?" 5 45; then
        [[ -e /tmp/.vconsole-running ]] && rm /tmp/.vconsole-running
        [[ -e /tmp/.vconsole ]] && rm /tmp/.vconsole
        clear
        exit 1
    else
        _CONTINUE=""
    fi
}

_do_vconsole() {
    _dialog --infobox "Setting vconsole font ${_FONT} and keymap ${_KEYMAP}..." 3 80
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 3
    _dialog --infobox "Vconsole configuration completed successfully." 3 50
    sleep 3
    return 0
}

_set_vconsole() {
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        if grep -q '^FONT=.*32' /etc/vconsole.conf; then
            _FONTS="ter-v32n Worldwide latarcyrheb-sun32 Worldwide"
        else
            _FONTS="ter-v16n Worldwide latarcyrheb-sun16 Worldwide eurlatgr Europe"
        fi
        #shellcheck disable=SC2086
        if _dialog --title " Vconsole Font " --menu "" 9 40 3 ${_FONTS} 2>${_ANSWER}; then
            #shellcheck disable=SC2086
            _FONT=$(cat ${_ANSWER})
            _CONTINUE=1
        else
            _abort
        fi
    done
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        # get list of 2 sign locale
        #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
        _KEYMAPS="us English de German es Spanish fr French pt Portuguese OTHER More"
        _OTHER_KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Dansk et Estonian fi Finnish gr Greek hu Hungarian it Italian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian ru Russian sk Slovak sr Serbian sv Swedish uk Ukrainian"
        #shellcheck disable=SC2086
        if _dialog --title " Keymap Region " --menu "" 12 40 6 ${_KEYMAPS} 2>${_ANSWER}; then
            _KEYMAP=$(cat ${_ANSWER})
            if [[ "${_KEYMAP}" == "OTHER" ]]; then
                while [[ -z "${_CONTINUE}" ]]; do
                    #shellcheck disable=SC2086
                    if _dialog --title " Keymap Region " --menu "" 17 40 11 ${_OTHER_KEYMAPS} 2>${_ANSWER}; then
                        _KEYMAP=$(cat ${_ANSWER})
                        _CONTINUE=1
                    else
                        _abort
                    fi
                done
            fi
            _CONTINUE=1
        else
            _abort
        fi
    done
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        _KEYMAPS=""
        for i in $(${_LIST_MAPS} | grep "^${_KEYMAP}" | grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
            _KEYMAPS="${_KEYMAPS} ${i} -"
        done
        #shellcheck disable=SC2086
        if _dialog --title " Keymap Layout " --menu "" 13 40 7 ${_KEYMAPS} 2>${_ANSWER}; then
            #shellcheck disable=SC2086
            _KEYMAP=$(cat ${_ANSWER})
            _CONTINUE=1
        else
            _abort
        fi
    done
}

if [[ -e /tmp/.vconsole-running ]]; then
    echo "vconsole already runs on a different vconsole!"
    echo "Please remove /tmp/.vconsole-running first to launch vconsole!"
    exit 1
fi 
: >/tmp/.vconsole-running
if ! _set_vconsole; then
    [[ -e /tmp/.vconsole ]] && rm /tmp/.vconsole
    [[ -e /tmp/.vconsole-running ]] && rm /tmp/.vconsole-running
    clear
    exit 1
fi
[[ -e /tmp/.vconsole-running ]] && rm /tmp/.vconsole-running
_do_vconsole
clear
exit 0
# vim: set ts=4 sw=4 et: