#!/usr/bin/env bash
# Turn an external USB drive (e.g. the old installer drive) into the off-box backup target at /mnt/backup.
#   sudo ./linux/setup-backup-drive.sh            # list disks
#   sudo ./linux/setup-backup-drive.sh /dev/sdX   # ERASES that drive
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
DEV="${1:-}"
if [[ -z "$DEV" ]]; then lsblk -d -o NAME,SIZE,TRAN,MODEL; echo; echo "Usage: sudo $0 /dev/sdX (a USB disk)"; exit 1; fi
[[ "$(lsblk -dn -o TRAN "$DEV")" == "usb" ]] || { echo "$DEV is not a USB disk. Refusing."; exit 1; }
read -rp "ERASE $DEV ($(lsblk -dn -o SIZE,MODEL "$DEV")) for backups? Type YES: " ok
[[ "$ok" == "YES" ]] || exit 1
umount "${DEV}"* 2>/dev/null || true
parted -s "$DEV" mklabel gpt mkpart omnicron-backup ext4 0% 100%
udevadm settle
mkfs.ext4 -F -L omnicron-backup "${DEV}1"
install -d /mnt/backup
grep -q 'LABEL=omnicron-backup' /etc/fstab || \
  echo 'LABEL=omnicron-backup  /mnt/backup  ext4  defaults,noatime,nofail,x-systemd.device-timeout=10  0 2' >> /etc/fstab
systemctl daemon-reload && mount /mnt/backup
df -h /mnt/backup
echo "Set BACKUP_REMOTE=/mnt/backup/omnicron/ in stack/.env"
