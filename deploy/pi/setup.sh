#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Prepares a Raspberry Pi to run Tally. bin/pi-setup copies this folder to the Pi and runs it
# there; it's safe to run again (to change the Ruby version, or after reflashing).
#
# Installs the system packages, mise and Ruby, creates ~/tally (releases, shared data, the
# settings file) and installs the tally service, the nightly backup timer and, when a name
# is given, the tally-name service that announces <name>.local. It doesn't start the app:
# the first bin/deploy does.
#
# Usage (on the Pi): setup.sh <ruby version> <port> [name]

ruby_version="${1:?usage: setup.sh <ruby version> <port> [name]}"
port="${2:?usage: setup.sh <ruby version> <port> [name]}"
name="${3:-}"
here="$(cd "$(dirname "$0")" && pwd)"
base="$HOME/tally"
shared="$base/shared"
mise="$HOME/.local/bin/mise"
user="$(id -un)"
address=""

announce() {
  printf '\033[1m%s\033[0m\n' "$1"
}

sudo -n true 2>/dev/null || { echo "pi-setup: $user needs passwordless sudo"; exit 1; }

announce "Installing system packages..."
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  build-essential pkg-config libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgmp-dev \
  sqlite3 poppler-utils rsync curl ca-certificates avahi-daemon avahi-utils

announce "Installing mise..."
[ -x "$mise" ] || curl -fsSL https://mise.run | sh

# mise uses a precompiled Ruby when there is one; if it has to compile, two make jobs keep
# it inside 512 MB of RAM plus swap.
announce "Installing Ruby $ruby_version (a precompiled build when mise has one, else it compiles for about an hour)..."
MISE_JOBS=1 MAKE_OPTS=-j2 "$mise" install "ruby@$ruby_version"
ruby_bin="$("$mise" where "ruby@$ruby_version")/bin"

announce "Creating $base..."
mkdir -p "$base/releases" "$shared/db" "$shared/storage/imports" "$shared/storage/receipts" "$shared/backups" "$shared/bundle"

# Rewritten every time, so it always points at the Ruby above.
cat > "$base/ruby.env" <<ENV
PATH=$ruby_bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
BUNDLE_DEPLOYMENT=true
BUNDLE_PATH=$shared/bundle
BUNDLE_WITHOUT=development:test:cli
MALLOC_ARENA_MAX=2
ENV

# Written once; your edits are kept.
if [ ! -f "$base/tally.env" ]; then
  cat > "$base/tally.env" <<ENV
# Tally's production settings (config/settings.rb), read by the tally service and bin/deploy.
# After a change: sudo systemctl restart tally
HANAMI_ENV=production
HANAMI_PORT=$port
DATABASE_URL=sqlite://$shared/db/tally.sqlite
IMPORT_STORAGE_DIR=$shared/storage/imports
RECEIPT_STORAGE_DIR=$shared/storage/receipts
BACKUP_DIR=$shared/backups
# Set both for a login, leave both commented out for none.
# BASIC_AUTH_USERNAME=
# BASIC_AUTH_PASSWORD=
# ALLOW_EXPORT_WITHOUT_LOGIN=false
ENV
  chmod 600 "$base/tally.env"
fi
# Added after the first installs: where the Backups page finds the copies.
grep -q '^BACKUP_DIR=' "$base/tally.env" || echo "BACKUP_DIR=$shared/backups" >>"$base/tally.env"

announce "Installing the tally service and the nightly backup..."
for unit in tally.service tally-backup.service tally-backup.timer; do
  sed -e "s|@USER@|$user|g" -e "s|@BASE@|$base|g" -e "s|@RUBY_BIN@|$ruby_bin|g" "$here/$unit" |
    sudo tee "/etc/systemd/system/$unit" >/dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable tally.service
sudo systemctl enable --now tally-backup.timer

if [ -n "$name" ]; then
  announce "Announcing $name.local on the network..."
  sudo install -m 755 "$here/publish-name.sh" /usr/local/bin/tally-publish-name
  sed -e "s|@USER@|$user|g" -e "s|@NAME@|$name|g" "$here/tally-name.service" |
    sudo tee /etc/systemd/system/tally-name.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable tally-name.service
  sudo systemctl restart tally-name.service
  address="http://$name.local:$port"
elif [ -f /etc/systemd/system/tally-name.service ]; then
  announce "Removing the tally-name service..."
  sudo systemctl disable --now tally-name.service
  sudo rm -f /etc/systemd/system/tally-name.service /usr/local/bin/tally-publish-name
  sudo systemctl daemon-reload
fi

announce "Setup complete. Now run bin/deploy on your computer${address:+; then Tally opens at $address}."
