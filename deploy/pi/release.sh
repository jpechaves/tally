#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Finishes a release that bin/deploy unpacked into ~/tally/releases/<commit>: installs the
# gems, backs up the database, migrates it (or creates and seeds it the first time), points
# ~/tally/current at this release, restarts the service and checks that it answers.
# Keeps the last three releases.

release="$(cd "$(dirname "$0")/../.." && pwd)"
base="$HOME/tally"

announce() {
  printf '\033[1m%s\033[0m\n' "$1"
}

set -a
# shellcheck source=/dev/null
. "$base/ruby.env"
# shellcheck source=/dev/null
. "$base/tally.env"
set +a
cd "$release"

announce "Installing gems..."
bundle install --quiet

database="${DATABASE_URL#sqlite://}"
if [ -f "$database" ]; then
  announce "Backing up and migrating the database..."
  bash deploy/pi/backup.sh pre-deploy
  bin/hanami db migrate
else
  announce "Creating the database..."
  bin/hanami db prepare
fi

announce "Switching to $(basename "$release") and restarting..."
ln -sfn "$release" "$base/current.new"
mv -T "$base/current.new" "$base/current"
sudo systemctl restart tally

# 200, or 401 when basic auth is on. Puma takes a while to boot on a Pi Zero.
url="http://127.0.0.1:$HANAMI_PORT/"
for _ in $(seq 1 45); do
  case "$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)" in
    200 | 401)
      find "$base/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | tail -n +4 |
        cut -d' ' -f2- | while read -r old; do rm -rf "$old"; done
      announce "Deployed: Tally answers on port $HANAMI_PORT."
      exit 0
      ;;
  esac
  sleep 2
done

echo "Tally didn't answer on $url. See: sudo journalctl -u tally -n 50" >&2
exit 1
