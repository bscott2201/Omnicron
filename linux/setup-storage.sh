#!/usr/bin/env bash
# Prepare /srv for Omnicron data.
# - If the LVM group has free space (server installer leaves some): root → 150G, rest → dedicated /srv volume.
# - If root already owns the whole disk (desktop installer default): /srv is a directory on root.
#   sudo ./linux/setup-storage.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
ADMIN="${SUDO_USER:?run via sudo from your normal user}"

ROOT_DEV="$(findmnt -n -o SOURCE /)"
VG="$(lvs --noheadings -o vg_name "$ROOT_DEV" 2>/dev/null | xargs || true)"

if mountpoint -q /srv; then
  echo "/srv already mounted."
elif [[ -n "$VG" ]]; then
  lvextend -r -L 150G "$ROOT_DEV" 2>/dev/null || true
  FREE_G="$(vgs --noheadings --units g --nosuffix -o vg_free "$VG" | xargs | cut -d. -f1)"
  if (( FREE_G >= 100 )) && ! lvs "$VG/srv" >/dev/null 2>&1; then
    echo "==> $VG has ${FREE_G}G free → creating dedicated /srv volume"
    lvcreate -y -l 95%FREE -n srv "$VG"
    mkfs.ext4 -L omnicron-data -m 1 "/dev/$VG/srv"
  fi
  if lvs "$VG/srv" >/dev/null 2>&1; then
    grep -q 'LABEL=omnicron-data' /etc/fstab || \
      echo 'LABEL=omnicron-data  /srv  ext4  defaults,noatime  0 2' >> /etc/fstab
    systemctl daemon-reload && mount /srv
  else
    echo "==> No free LVM space; /srv will live on the root filesystem (fine; one volume)."
  fi
else
  echo "==> Root is not on LVM; /srv will live on the root filesystem."
fi

install -d -o "$ADMIN" -g "$ADMIN" /srv/media "/srv/media/Movies" "/srv/media/TV Shows" "/srv/media/Music" \
  /srv/appdata /srv/backups

if mountpoint -q /srv; then
  install -d /etc/systemd/system/docker.service.d
  printf '[Unit]\nRequiresMountsFor=/srv\n' > /etc/systemd/system/docker.service.d/omnicron.conf
  systemctl daemon-reload
fi
df -h / /srv
