# Omnicron: Bare-Metal Ubuntu Home Server

**Hardware:** 2019 MacBook Pro (T2), 8-core 2.4 GHz i9, 32 GB DDR4, 2 TB SSD
**Design:** macOS removed → **T2-Ubuntu 26.04** (Ubuntu with the T2 drivers built in) → headless → Plex + Homebridge in Docker.

```
MacBook Pro (T2-Ubuntu 26.04, headless, lid closed)  ·  192.168.1.60
├─ /        OS + /srv on the internal 2 TB SSD (LVM)
│   ├─ media/     ◄── SMB share
│   ├─ appdata/   plex · homebridge
│   └─ backups/   nightly snapshots ──► /mnt/backup (external USB drive)
└─ Docker (host network): plex :32400 · homebridge :8581
```

**Why T2-Ubuntu:** the stock Ubuntu ISO has no T2 drivers. T2-Ubuntu is the community build of the same Ubuntu with the t2linux kernel baked in, so the internal keyboard, trackpad, Wi-Fi (after one firmware step), Bluetooth and fan control all work, and kernel updates arrive through apt. It ships only as a desktop ISO; `setup-t2.sh` switches it to boot headless.

---

## Phase 0: Boot security (5 min, or about 1 hr if macOS must come back)
T2 Macs refuse to boot unsigned or external systems by default. Test it first:

1. Plug in the T2-Ubuntu USB (Phase 1) and power on holding **⌥ (Option)** → **EFI Boot**.
   - **The installer starts** → security was already relaxed. Go to Phase 2.
   - **"Security settings do not allow this Mac to use an external startup disk"** → continue below.
2. Power on holding **⌥⌘R** (Internet Recovery; needs Wi-Fi or Ethernet). Open **Startup Security Utility**.
   - If it lets you authenticate: set **Secure Boot: No Security** and **Allowed Boot Media: Allow booting from external or removable media** → go to Phase 2.
   - If it says **no administrator found**: choose **Reinstall macOS** (about 45 min), create a throwaway admin user, then:
     - Run `curl -fsSL -o ~/firmware.sh https://wiki.t2linux.org/tools/firmware.sh && bash ~/firmware.sh` → **Method 2** → copy `~/Downloads/firmware.tar` to a USB stick or cloud drive. *(Bonus: this saves the Wi-Fi firmware.)*
     - Restart holding **⌘R** → **Startup Security Utility** → set the two options above.
     - The Linux installer erases macOS again in Phase 2.

## Phase 1: Make the USB installer (on your other Mac, 20 min)
⚠️ This erases the external drive.
1. Go to https://github.com/t2linux/T2-Ubuntu/releases/latest and download **`iso.sh`**. Run it; it asks which flavor and version to download:
   ```bash
   cd ~/Downloads && bash iso.sh
   ```
   Choose **Ubuntu** (or **Kubuntu**) **26.04 resolute**. The script downloads the split parts and reassembles them into one ISO (e.g. `ubuntu-26.04-…-t2-resolute.iso`).
2. Flash it. This finds the disk behind `/Volumes/Ubuntu` and asks for confirmation:
   ```bash
   ISO=$(ls ~/Downloads/*-t2-resolute.iso | head -1); echo "$ISO"
   DISK=$(diskutil info /Volumes/Ubuntu | awk -F': *' '/Part of Whole/{print $2}')
   diskutil info /dev/$DISK | grep -E 'Device Node|Media Name|Disk Size|Internal'
   read -p "Erase /dev/$DISK? Type YES: " ok && [ "$ok" = YES ] && \
   diskutil unmountDisk /dev/$DISK && \
   sudo dd if="$ISO" of=/dev/r$DISK bs=4m status=progress && sync && diskutil eject /dev/$DISK
   ```
   **Internal** must read **No**. If macOS then says the disk isn't readable, click **Ignore**.

## Phase 2: Install (30 min)
1. Plug in the USB installer. Wired Ethernet is optional but recommended for a media server.
2. Power on holding **⌥ (Option)** → **EFI Boot** → *Try or Install Ubuntu*.
   *(Black screen after GRUB? See the rEFInd note on wiki.t2linux.org → Ubuntu → Installation.)*
3. The internal keyboard and trackpad work. In the installer:
   - **Interactive installation**, **Default selection** (minimal apps)
   - Skip Wi-Fi for now (no firmware yet) unless Ethernet is plugged in
   - ✅ *Install third-party software* (optional)
   - **Disk:** *Erase disk and install Ubuntu* → **Advanced features → Use LVM** → target the internal **~2 TB APPLE SSD**. **This erases macOS.**
   - **Account:** computer name `omnicron`, user `brad`, ✅ *Require my password to log in*
4. Restart and remove the USB drive when prompted.

## Phase 3: First boot (on the server, 10 min)
1. Get online. Plug in **Ethernet**, or use **iPhone USB tethering** (Personal Hotspot on → plug in → Trust; works out of the box). Then:
   ```bash
   sudo apt update && sudo apt install -y git openssh-server
   ```
2. Get the repo and finish T2 setup. This installs the Wi-Fi firmware, the fan daemon, lid-closed behavior and console-only boot:
   ```bash
   sudo git clone https://github.com/<you>/omnicron.git /opt/omnicron
   sudo chown -R $USER: /opt/omnicron && cd /opt/omnicron
   sudo ./linux/setup-t2.sh online                   # pulls Wi-Fi firmware from Apple's recovery image
   # or, if you saved firmware.tar in Phase 0:
   # sudo ./linux/setup-t2.sh /media/$USER/<usb>/firmware.tar
   ```
3. Join Wi-Fi if you're not on Ethernet: `nmcli device wifi connect "<SSID>" password "<pass>"`
4. **Router:** reserve **192.168.1.60** for the server's MAC address. For Wi-Fi it's `ip link show wlp*`; use the Ethernet adapter's MAC if you're wired.
5. `sudo reboot`. From now on, work from your main Mac: `ssh brad@192.168.1.60`

## Phase 4: Verify hardware (5 min)
```bash
uname -r                   # contains "t2"
systemctl status t2fanrd   # active (running)
nmcli device               # Wi-Fi/Ethernet connected
systemctl get-default      # multi-user.target (no desktop)
```

## Phase 5: Storage + base system (15 min)
```bash
cd /opt/omnicron
sudo ./linux/setup-storage.sh    # /srv: separate volume if LVM has free space, else a folder on root
sudo ./linux/bootstrap.sh        # updates, Docker, auto security patches, timers
exit && ssh brad@192.168.1.60    # re-login for the docker group
cd /opt/omnicron && sudo ./linux/setup-samba.sh
```

## Phase 6: Load media
Finder → **Go → Connect to Server** → `smb://192.168.1.60/media`
```
media/
├── Movies/    Movie Name (2023)/Movie Name (2023).mkv
├── TV Shows/  Show Name/Season 01/Show Name - S01E01.mkv
└── Music/     Artist/Album/01 - Track.flac
```

## Phase 7: Start the stack (10 min)
```bash
cd /opt/omnicron/stack
cp .env.example .env
nano .env                          # paste PLEX_CLAIM from https://plex.tv/claim (expires in 4 min)
docker compose up -d
docker compose ps                  # plex + homebridge running
sed -i 's/^PLEX_CLAIM=.*/PLEX_CLAIM=/' .env
```

## Phase 8: Configure Plex & Homebridge (30 min)
**Plex** at `http://192.168.1.60:32400/web`
1. Libraries: `/media/Movies`, `/media/TV Shows`, `/media/Music`
2. Settings → Library: **Scan automatically: ON**, plus a periodic scan every 6 h
3. Settings → Transcoder: temp directory `/transcode`
4. Remote Access: manual port `32400` → forward **TCP 32400 → 192.168.1.60**
5. Scheduled Tasks: maintenance window **00:00–03:00**
6. On your TV and phone apps: quality **Original / Maximum** (Direct Play)

**Homebridge** at `http://192.168.1.60:8581`
1. Create the admin login → iPhone **Home** → **+** → scan the QR code
2. Install plugins → enable a **Child Bridge** for each plugin
3. Keep the UI's scheduled backups on (they land in `/srv/appdata/homebridge/backups`)

## Phase 9: Backups (15 min)
- **Layer 1 (automatic):** a nightly 03:30 snapshot of `/srv/appdata` goes to `/srv/backups`, kept for 14 days.
- **Layer 2 (off the SSD):** reuse the installer drive, or any USB drive, as the backup target:
  ```bash
  sudo ./linux/setup-backup-drive.sh            # list disks
  sudo ./linux/setup-backup-drive.sh /dev/sdX   # ERASES it, mounts at /mnt/backup
  nano stack/.env                               # BACKUP_REMOTE=/mnt/backup/omnicron/
                                                # BACKUP_MEDIA=1  (if the drive can hold your media)
  sudo systemctl start omnicron-backup.service && journalctl -u omnicron-backup -n 20
  ```
  Leave the drive plugged in. If it's ever missing, the backup still writes Layer 1 and skips the copy.

## Phase 10 (optional): Intel iGPU for hardware transcoding
On T2 MacBook Pros the Intel UHD 630 is hidden behind the AMD GPU by default. With it exposed, Plex (with Plex Pass) can use **Quick Sync**, which turns 4K→1080p transcoding from impossible into easy.
1. Follow the t2linux **Hybrid Graphics** guide: https://wiki.t2linux.org/guides/hybrid-graphics/
2. Verify: `ls /dev/dri` shows `renderD128` (Intel).
3. Uncomment the `devices:` block in `stack/compose.yaml` → `docker compose up -d`.
4. Plex → Settings → Transcoder → ✅ **Use hardware acceleration when available**.

## Phase 11: Acceptance tests
- [ ] `sudo reboot` → Plex and Homebridge back within about 2 minutes, no login needed
- [ ] Lid closed for 30+ min → still streaming, `systemctl status t2fanrd` healthy
- [ ] Pull the power cord for 10 s → still running on battery
- [ ] TV on Wi-Fi shows **Local** + **Direct Play**
- [ ] Remote Access green; plays over cellular
- [ ] Home app accessory toggles; survives a reboot without re-pairing
- [ ] Manual backup lands on `/mnt/backup/omnicron/`

---

## Operations runbook
| Task | Command |
|---|---|
| SSH in | `ssh brad@192.168.1.60` |
| Status | `cd /opt/omnicron/stack && docker compose ps` |
| Logs | `docker compose logs -f plex` / `homebridge` |
| Update containers now | `/opt/omnicron/linux/update.sh` (auto Sundays 05:00) |
| Backup now | `sudo systemctl start omnicron-backup.service` |
| Timers | `systemctl list-timers 'omnicron-*'` |
| Disk usage | `df -h / /srv` |
| Temps / fans | `sensors` · `systemctl status t2fanrd` |
| OS updates | Security patches install automatically (reboot at 04:30 if needed); `sudo apt full-upgrade` monthly |
| Repo changes | `cd /opt/omnicron && git pull && cd stack && docker compose up -d` |

| Schedule | Job |
|---|---|
| 00:00–03:00 | Plex maintenance |
| 03:30 daily | Appdata snapshot → USB drive |
| 04:30 | Reboot, only if a security patch requires it |
| Sun 05:00 | Container image updates |

## Recovery
- **Plex DB corrupted:** `docker compose stop plex` → extract the latest `/srv/backups/appdata-*.tar.zst` over `/srv/appdata/plex` → `docker compose start plex`.
- **Wi-Fi gone after an update:** `sudo ./linux/setup-t2.sh online` re-installs the firmware.
- **Kernel update broke booting:** at the GRUB menu choose *Advanced options* → the previous kernel.
- **OS reinstall:** restore `/srv/appdata` from the USB backup drive, copy media back, re-run Phases 3–5, then `docker compose up -d`.
- **New hardware:** install Ubuntu, restore `/srv/appdata` from the USB drive, copy media, clone the repo, `docker compose up -d`.
- **Back to macOS someday:** power on holding **⌥⌘R** (Internet Recovery) → Disk Utility → erase → reinstall macOS.

## Long-term notes
- **Battery:** an always-plugged-in laptop battery can swell. Check it every few months (look for a lifting trackpad or a bulging case). Removing the battery isn't practical on this model, so keep it well ventilated and watch for that.
- **Thermals:** run it lid-closed, standing vertically or on a vented stand.
- **Later additions:** Tailscale (secure remote admin), Uptime Kuma (alerts).

## Repo layout
| Path | Purpose |
|---|---|
| `linux/setup-t2.sh` | Fan daemon, Wi-Fi firmware, lid/sleep behavior, headless boot (T2 repo if missing) |
| `linux/setup-storage.sh` | Root → 150 GB; dedicated `/srv` LVM volume |
| `linux/bootstrap.sh` | Updates, Docker, unattended upgrades, journald cap, timers |
| `linux/setup-samba.sh` | `media` SMB share |
| `linux/setup-backup-drive.sh` | External USB drive → `/mnt/backup` |
| `linux/backup.sh` · `update.sh` | Nightly snapshot + off-box copy · weekly image updates |
| `linux/systemd/` | Timers |
| `stack/compose.yaml` · `.env.example` | Plex + Homebridge |
