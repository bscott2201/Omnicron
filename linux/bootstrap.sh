#!/usr/bin/env bash
# One-time Ubuntu setup for Omnicron. Run after setup-storage.sh:
#   sudo ./linux/bootstrap.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
ADMIN="${SUDO_USER:?run via sudo from your normal user}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TZ_NAME="${TZ_NAME:-America/New_York}"
[[ -d /srv/appdata ]] || { echo "Run setup-storage.sh first."; exit 1; }

echo "==> Base system"
timedatectl set-timezone "$TZ_NAME"
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get -y full-upgrade
apt-get install -y ca-certificates curl git rsync zstd unattended-upgrades samba

echo "==> Docker Engine"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
usermod -aG docker "$ADMIN"
install -d /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
JSON
systemctl enable docker && systemctl restart docker

echo "==> Unattended security updates (reboot 04:30 if required)"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
cat > /etc/apt/apt.conf.d/52omnicron <<'CONF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
CONF

echo "==> Journald cap"
install -d /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=500M\n' > /etc/systemd/journald.conf.d/omnicron.conf
systemctl restart systemd-journald

echo "==> Backup + update timers"
for f in "$REPO"/linux/systemd/*; do
  sed "s#__REPO__#$REPO#g" "$f" > "/etc/systemd/system/$(basename "$f")"
done
systemctl daemon-reload
systemctl enable --now omnicron-backup.timer omnicron-update.timer
systemctl enable --now fstrim.timer

echo
echo "Bootstrap complete. Log out and back in (docker group), then: sudo ./linux/setup-samba.sh"
