#!/usr/bin/env bash
# Nightly backup of the CISO Assistant data volume (SQLite DB + attachments).
#
# Streams a .tar.gz out of the running backend container: a consistent online
# copy of the database (sqlite3 backup API, safe while the app is writing) plus
# the attachments directory. Keeps BACKUP_KEEP_DAYS days of archives.
#
# Cron (wern): 30 3 * * * /home/wern/atomRepos/ciso-assistant/deploy/pi/backup.sh >> /mnt/ssd/backups/ciso-assistant/backup.log 2>&1
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/mnt/ssd/backups/ciso-assistant}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"

# Container names change on every Coolify deploy, so find the backend by what it
# mounts (the compose volume is named <app-uuid>_ciso-db) and the image it runs.
container=""
for name in $(docker ps --format '{{.Names}}'); do
  info=$(docker inspect "$name" --format '{{.Config.Image}} {{range .Mounts}}{{.Name}} {{end}}')
  if [[ "$info" == *"/backend:"* && "$info" == *"_ciso-db "* ]]; then
    container="$name"
    break
  fi
done
if [[ -z "$container" ]]; then
  echo "$(date -Is) ERROR: no running CISO Assistant backend container found" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
out="$BACKUP_DIR/ciso-assistant-$(date +%Y%m%d-%H%M%S).tar.gz"
tmp="$out.partial"
trap 'rm -f "$tmp"' EXIT

docker exec -i "$container" python3 - > "$tmp" <<'PY'
import io, os, sqlite3, sys, tarfile, tempfile

db_dir = "/code/db"
src = sqlite3.connect(os.path.join(db_dir, "ciso-assistant.sqlite3"))
with tempfile.NamedTemporaryFile(dir="/tmp", suffix=".sqlite3") as snap:
    dst = sqlite3.connect(snap.name)
    src.backup(dst)
    dst.close()
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|gz") as tar:
        tar.add(snap.name, arcname="ciso-assistant.sqlite3")
        attachments = os.path.join(db_dir, "attachments")
        if os.path.isdir(attachments):
            tar.add(attachments, arcname="attachments")
PY

# A truncated stream must not replace a good archive.
gzip -t "$tmp"
mv "$tmp" "$out"
echo "$(date -Is) OK $out ($(du -h "$out" | cut -f1)) from $container"

find "$BACKUP_DIR" -name 'ciso-assistant-*.tar.gz' -mtime +"$BACKUP_KEEP_DAYS" -delete
