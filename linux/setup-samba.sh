#!/usr/bin/env bash
# SMB share of /srv/media so Macs/PCs can copy media in: smb://<server-ip>/media
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
ADMIN="${SUDO_USER:?run via sudo from your normal user}"

if ! grep -q '^\[media\]' /etc/samba/smb.conf; then
cat >> /etc/samba/smb.conf <<CONF

[media]
   path = /srv/media
   valid users = $ADMIN
   read only = no
   browseable = yes
   create mask = 0664
   directory mask = 0775
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   veto files = /._*/.DS_Store/
   delete veto files = yes
CONF
fi
testparm -s >/dev/null
echo "Set the SMB password for '$ADMIN' (used when connecting from Finder):"
smbpasswd -a "$ADMIN"
systemctl enable --now smbd && systemctl restart smbd
echo "Share ready: smb://$(hostname -I | awk '{print $1}')/media"
