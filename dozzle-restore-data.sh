#!/bin/bash

# Restore Dozzle's data directory from one of the archives the `backups`
# container has taken.
#
# That directory is small and entirely irreplaceable: users.yml, which is the
# only thing standing between the internet and every log line on this host, and
# each user's interface settings.
#
#     chmod +x dozzle-restore-data.sh
#     ./dozzle-restore-data.sh
#
# No logs are in here. Dozzle stores none: it streams them from the Docker
# daemon on every page load, which is why it needs no storage backend and no
# index, and why this archive is a few kilobytes.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-dozzle-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-dozzle}"
BACKUP_PATH="${DATA_BACKUPS_PATH:-/srv/dozzle-data/backups}"
RESTORE_PATH="${DATA_PATH:-/data}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

APP_CONTAINER="$(dc ps -aq dozzle | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$APP_CONTAINER" ] || { echo "the dozzle container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

echo "--> All available data backups:"
docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true

echo "--> Copy and paste the backup name from the list above and press [ENTER]
--> Example: dozzle-data-backup-YYYY-MM-DD_hh-mm.tar.gz"
echo -n "--> "
read -r SELECTED
[ -n "$SELECTED" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "tar -tzf '${BACKUP_PATH}/${SELECTED}' > /dev/null"; then
  echo "that file is not a readable tar archive — nothing has been stopped or deleted" >&2
  exit 1
fi
echo "--> $SELECTED was selected and reads as a valid archive"

echo "--> Stopping Dozzle..."
docker stop "$APP_CONTAINER" > /dev/null

echo "--> Restoring the data directory..."
# The archive stores paths relative to /, so it extracts there. The directory
# is emptied first: merging would leave an old users.yml beside a new one and
# no way to tell which is in force.
docker exec "$BACKUPS_CONTAINER" sh -c "rm -rf '${RESTORE_PATH:?}'/* && tar -zxpf '${BACKUP_PATH}/${SELECTED}' -C /"
echo "--> Data recovery completed."

echo "--> Starting Dozzle..."
docker start "$APP_CONTAINER" > /dev/null
echo "--> Sign in with the account the restored users.yml carries. If that file"
echo "--> predates a password change, the old password is the one that works."
