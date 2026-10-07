#!/usr/bin/env bash
# Nightly appdata snapshot: brief stack stop → tar.zst → restart → prune → optional off-box rsync.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/srv/backups
KEEP_DAYS="${KEEP_DAYS:-14}"
PMS='appdata/plex/Library/Application Support/Plex Media Server'
OUT="$DEST/appdata-$(date +%F).tar.zst"

cd "$REPO/stack"
docker compose stop
trap 'docker compose start' EXIT
tar --zstd -cf "$OUT" -C /srv \
  --exclude="$PMS/Cache" --exclude="$PMS/Codecs" --exclude="$PMS/Media" \
  --exclude="$PMS/Crash Reports" --exclude="$PMS/Logs" \
  appdata
docker compose start
trap - EXIT

find "$DEST" -name 'appdata-*.tar.zst' -mtime +"$KEEP_DAYS" -delete
echo "Backup written: $OUT ($(du -h "$OUT" | cut -f1))"

# Off-box copy: local path (external USB drive) or user@host:path over SSH
if [[ -n "${BACKUP_REMOTE:-}" ]]; then
  if [[ "$BACKUP_REMOTE" == /* ]]; then
    mountpoint -q "$(dirname "${BACKUP_REMOTE%/}")" || mountpoint -q "${BACKUP_REMOTE%/}" || \
      { echo "Backup drive not mounted; skipping off-box copy"; exit 0; }
    mkdir -p "$BACKUP_REMOTE"
    rsync -a --delete "$DEST/" "$BACKUP_REMOTE/appdata/"
    [[ "${BACKUP_MEDIA:-0}" == "1" ]] && rsync -a --delete /srv/media/ "$BACKUP_REMOTE/media/"
  else
    rsync -a --delete -e "ssh -i /root/.ssh/omnicron_backup -o StrictHostKeyChecking=accept-new" \
      "$DEST/" "$BACKUP_REMOTE"
  fi
  echo "Off-box copy → $BACKUP_REMOTE"
fi
