#!/usr/bin/env bash
# Finish a T2-Ubuntu install as a headless server.
#   sudo ./linux/setup-t2.sh [/path/to/firmware.tar | online]
#   "online" = download firmware from an Apple recovery image (needs Ethernet or phone USB tethering)
# - Ensures t2linux kernel repo + fan daemon (already present on T2-Ubuntu ISOs)
# - Installs Wi-Fi/Bluetooth firmware from a macOS-extracted firmware.tar (optional)
# - Lid closed = keep running; never suspend; boot to console (no desktop)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
FW_TAR="${1:-}"
. /etc/os-release

if [[ ! -f /etc/apt/sources.list.d/t2.list ]]; then
  echo "==> Adding t2linux apt repo ($VERSION_CODENAME)"
  curl -s --compressed "https://adityagarg8.github.io/t2-ubuntu-repo/KEY.gpg" \
    | gpg --dearmor > /etc/apt/trusted.gpg.d/t2-ubuntu-repo.gpg
  curl -s --compressed -o /etc/apt/sources.list.d/t2.list "https://adityagarg8.github.io/t2-ubuntu-repo/t2.list"
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/t2-ubuntu-repo.gpg] https://github.com/AdityaGarg8/t2-ubuntu-repo/releases/download/${VERSION_CODENAME} ./" \
    >> /etc/apt/sources.list.d/t2.list
fi
apt-get update
echo "==> T2 kernel + fan daemon"
dpkg -l | grep -q '^ii  linux-t2' || apt-get install -y linux-t2
apt-get install -y t2fanrd openssh-server
systemctl enable --now t2fanrd ssh || true

if [[ "$FW_TAR" == "online" ]]; then
  echo "==> Wi-Fi/Bluetooth firmware from Apple recovery image"
  if command -v get-apple-firmware >/dev/null; then
    get-apple-firmware get_from_online
  else
    curl -fsSL -o /tmp/firmware.sh https://wiki.t2linux.org/tools/firmware.sh
    echo ">> Choose Method 5 and a macOS version from Monterey to Sonoma."
    bash /tmp/firmware.sh
  fi
elif [[ -n "$FW_TAR" ]]; then
  echo "==> Wi-Fi/Bluetooth firmware from $FW_TAR"
  tar -v -xC /lib/firmware/brcm -f "$FW_TAR"
  modprobe -r brcmfmac_wcc 2>/dev/null || true
  modprobe -r brcmfmac 2>/dev/null || true; modprobe brcmfmac
  modprobe -r hci_bcm4377 2>/dev/null || true; modprobe hci_bcm4377 || true
fi

echo "==> Lid closed = keep running; never suspend"
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/omnicron.conf <<'CONF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
CONF
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "==> Blank console after 60s"
grep -q 'consoleblank=' /etc/default/grub || \
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
update-grub

if [[ "${KEEP_DESKTOP:-0}" != "1" ]]; then
  echo "==> Boot to console (desktop stays installed; 'sudo systemctl isolate graphical.target' to use it)"
  systemctl set-default multi-user.target
fi

echo; echo "Done. Reboot, then check: uname -r (contains 't2'), systemctl status t2fanrd, nmcli device"
