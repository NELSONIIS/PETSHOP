#!/bin/sh
# Runs inside the backup container: one backup per day at BACKUP_HOUR_UTC, plus one at start-up.
set -eu
while true; do
	/bin/sh /scripts/backup.sh || echo "backup FAILED at $(date -u)" >&2
	now=$(date -u +%s)
	next=$(date -u -d "@$(( (now / 86400 + 1) * 86400 + ${BACKUP_HOUR_UTC:-21} * 3600 ))" +%s 2>/dev/null || echo $((now + 86400)))
	[ "$next" -le "$now" ] && next=$((now + 86400))
	sleep $((next - now > 86400 ? 86400 : next - now))
done
