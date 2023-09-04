#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_configure_plasma() {
    echo "Configuring KDE..."
    sed -i -e "s#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,applications:${_STANDARD_BROWSER}.desktop,applications:gparted.desktop,applications:archboot.desktop</default>#g" /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure..."
    cat << EOF >/etc/xdg/menus/applications.menu
 <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<!-- Search the default locations -->
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Separator/>
		<Menuname>More</Menuname>
	</DefaultLayout>
	<Layout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Menuname>Applications</Menuname>
	</Layout>
	<Menu>
		<Name>Settingsmenu</Name>
		<Directory>kf5-settingsmenu.directory</Directory>
		<Include>
			<Category>Settings</Category>
		</Include>
	</Menu>
	<DefaultMergeDirs/>
	<Include>
	<Filename>archboot.desktop</Filename>
	<Filename>${_STANDARD_BROWSER}.desktop</Filename>
	<Filename>org.kde.dolphin.desktop</Filename>
	<Filename>gparted.desktop</Filename>
	<Filename>org.kde.konsole.desktop</Filename>
	</Include>
</Menu>
EOF
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=konsole -p colors=Linux -e /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        _prepare_graphic "${_PACKAGES}"
        _configure_plasma >"${_LOG}" 2>&1
    fi
}

_install_plasma_wayland() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_install_plasma() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma_wayland() {
    _progress "100" "Launching Plasma/KDE Wayland now, logging is done on ${_LOG}..."
    sleep 2
    echo "MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland exec dbus-run-session startplasma-wayland >${_LOG} 2>&1" > /usr/bin/plasma-wayland
    chmod 755 /usr/bin/plasma-wayland
    plasma-wayland
}

_start_plasma() {
    _progress "100" "Launching Plasma/KDE now, logging is done on ${_LOG}..."
    sleep 2
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >${_LOG} 2>&1
}
# vim: set ft=sh ts=4 sw=4 et:
