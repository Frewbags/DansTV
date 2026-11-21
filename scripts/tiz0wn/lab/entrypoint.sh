#!/bin/sh
# Disposable XRDP desktop for a privately owned Samsung TV Remote PC experiment.
set -eu
: "${TVPROBE_USER:?missing TVPROBE_USER}"
: "${TVPROBE_PASSWORD:?missing TVPROBE_PASSWORD}"
case "$TVPROBE_USER" in ""|*[!a-z0-9_-]*) echo "invalid user" >&2; exit 2 ;; esac
[ "${#TVPROBE_PASSWORD}" -ge 12 ] || { echo "password too short" >&2; exit 2; }
if ! id "$TVPROBE_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$TVPROBE_USER"
fi
printf '%s:%s\n' "$TVPROBE_USER" "$TVPROBE_PASSWORD" | chpasswd
printf '%s\n' 'exec startxfce4' >"/home/$TVPROBE_USER/.xsession"
chown "$TVPROBE_USER:$TVPROBE_USER" "/home/$TVPROBE_USER/.xsession"
chmod 0600 "/home/$TVPROBE_USER/.xsession"
mkdir -p /run/xrdp /var/run/dbus
chmod 0755 /run/xrdp
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
