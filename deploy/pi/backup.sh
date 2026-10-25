#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Copies the live database with SQLite's online backup, checks the copy and keeps the newest
# copies with the same name, 5 by default (TALLY_BACKUP_KEEP in ~/tally/tally.env). Run
# nightly by tally-backup.timer ("nightly") and before each migration by bin/deploy
# ("pre-deploy"). bin/pull-backup copies them off the SD card. Each run adds a line to
# log.jsonl (the last 100 kept), which the app's Backups page and home warning read.
#
# Usage: backup.sh [name]    reads DATABASE_URL from the environment

name="${1:-nightly}"
dir="$HOME/tally/shared/backups"
keep="${TALLY_BACKUP_KEEP:-5}"
database="${DATABASE_URL#sqlite://}"

[ -f "$database" ] || { echo "backup: no database at $database yet"; exit 0; }

mkdir -p "$dir"
copy="$dir/$name-$(date +%Y%m%d-%H%M%S).sqlite"

# One JSON line per run: time (UTC), kind, file, size and the check's result.
log() {
  printf '{"time":"%s","kind":"%s","file":"%s","bytes":%s,"check":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$(basename "$copy")" "$1" "$(printf '%s' "$2" | tr -d "\"\\\\" | tr '\n' ' ')" >>"$dir/log.jsonl"
  tail -n 100 "$dir/log.jsonl" >"$dir/log.jsonl.tmp" && mv "$dir/log.jsonl.tmp" "$dir/log.jsonl"
}

if ! error="$(sqlite3 "$database" ".backup '$copy'" 2>&1)"; then
  rm -f "$copy"
  log 0 "backup failed: $error"
  echo "backup: $copy failed: $error" >&2
  exit 1
fi
check="$(sqlite3 "$copy" "PRAGMA integrity_check" 2>&1)" || true
if [ "$check" != "ok" ]; then
  rm -f "$copy"
  log 0 "$check"
  echo "backup: $copy failed the integrity check: $check" >&2
  exit 1
fi
log "$(stat -c %s "$copy")" ok
echo "backup: $copy"

find "$dir" -maxdepth 1 -name "$name-*.sqlite" | sort -r | tail -n +$((keep + 1)) | while read -r old; do rm -f "$old"; done
