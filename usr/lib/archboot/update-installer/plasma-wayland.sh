#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_plasma_wayland() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma_wayland() {
    echo -e "Launching \033[1mKDE/Plasma Wayland\033[0m now, logging is done on \033[1m/dev/tty7\033[0m..."
	echo -e "To relaunch \033[1mKDE/Plasma Wayland\033[0m use: \033[92mplasma-wayland\033[0m"
    echo "exec dbus-run-session startplasma-wayland >/dev/tty7 2>&1" > /usr/bin/plasma-wayland
    chmod 755 /usr/bin/plasma-wayland
    plasma-wayland
}
