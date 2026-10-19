#!/bin/sh
# Restore a PETORA database dump into a TARGET database (default: petora_restore_test) for verification,
# or into production during disaster recovery (requires --i-understand-this-overwrites).
#   sh restore.sh /backups/petora-db-XXXX.dump[.age] [target_db] [--i-understand-this-overwrites]
set -eu
FILE=${1:?dump file required}
TARGET=${2:-petora_restore_test}
FORCE=${3:-}
if [ "$TARGET" = "${PGDATABASE:-petora}" ] && [ "$FORCE" != "--i-understand-this-overwrites" ]; then
	echo "Refusing to overwrite the live database without --i-understand-this-overwrites" >&2
	exit 1
fi
TMP=$FILE
case "$FILE" in *.age)
	: "${BACKUP_AGE_IDENTITY:?set BACKUP_AGE_IDENTITY to the age private key file}"
	TMP=$(mktemp); age -d -i "$BACKUP_AGE_IDENTITY" -o "$TMP" "$FILE";;
esac
psql -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$TARGET\"" -c "CREATE DATABASE \"$TARGET\""
pg_restore --no-owner --exit-on-error -d "$TARGET" "$TMP"
psql -d "$TARGET" -At -c "SELECT 'tables=' || count(*) FROM information_schema.tables WHERE table_schema='public'" \
	-c "SELECT 'migrations=' || string_agg(version, ',' ORDER BY version) FROM schema_migrations" \
	-c "SELECT 'users=' || count(*) FROM users" -c "SELECT 'payments=' || count(*) FROM payments"
[ "$TMP" != "$FILE" ] && rm -f "$TMP"
echo "restore into $TARGET complete"
