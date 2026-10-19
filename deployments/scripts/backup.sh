#!/bin/sh
# Logical backup of PostgreSQL (custom format) + media archive. Encrypted with age when BACKUP_AGE_RECIPIENT is set.
# Usage (inside the backup container or any host with pg_dump 16):  sh backup.sh
set -eu
umask 077
OUT=${BACKUP_OUT:-/backups}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT"
DB_FILE="$OUT/petora-db-$STAMP.dump"
MEDIA_FILE="$OUT/petora-media-$STAMP.tar.gz"

pg_dump --format=custom --compress=6 --no-owner --file="$DB_FILE"
pg_restore --list "$DB_FILE" >/dev/null   # sanity check: archive is readable
if [ -d /media ]; then tar -C /media -czf "$MEDIA_FILE" . ; fi

if [ -n "${BACKUP_AGE_RECIPIENT:-}" ]; then
	for f in "$DB_FILE" "$MEDIA_FILE"; do
		[ -f "$f" ] || continue
		age -r "$BACKUP_AGE_RECIPIENT" -o "$f.age" "$f" && rm -f "$f"
	done
else
	echo "WARNING: BACKUP_AGE_RECIPIENT not set; backups are NOT encrypted" >&2
fi

find "$OUT" -name 'petora-*' -type f -mtime +"${BACKUP_RETENTION_DAYS:-14}" -delete
ls -lh "$OUT" | tail -5
echo "backup complete: $STAMP"
