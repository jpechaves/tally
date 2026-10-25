#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Copies the live database with SQLite's online backup, checks the copy and keeps the newest
# copies with the same name, 5 by default (TALLY_BACKUP_KEEP in ~/tally/tally.env). Run
# nightly by tally-backup.timer ("nightly") and before each migration by bin/deploy
# ("pre-deploy"). bin/pull-backup copies them off the SD card.
#
# Usage: backup.sh [name]    reads DATABASE_URL from the environment

name="${1:-nightly}"
dir="$HOME/tally/shared/backups"
keep="${TALLY_BACKUP_KEEP:-5}"
database="${DATABASE_URL#sqlite://}"

[ -f "$database" ] || { echo "backup: no database at $database yet"; exit 0; }

mkdir -p "$dir"
copy="$dir/$name-$(date +%Y%m%d-%H%M%S).sqlite"
sqlite3 "$database" ".backup '$copy'"
check="$(sqlite3 "$copy" "PRAGMA integrity_check")"
[ "$check" = "ok" ] || { echo "backup: $copy failed the integrity check: $check" >&2; exit 1; }
echo "backup: $copy"

find "$dir" -maxdepth 1 -name "$name-*.sqlite" | sort -r | tail -n +$((keep + 1)) | while read -r old; do rm -f "$old"; done
