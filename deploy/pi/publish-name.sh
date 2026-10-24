#!/bin/sh
# Announces <name>.local on the network over mDNS (Bonjour), pointing at this Pi's first
# address, so Tally opens at http://<name>.local:<port>. Run by the tally-name service, which
# restarts it when it exits; restart that service after the Pi's address changes.
#
# Usage: publish-name.sh <name>

name="${1:?usage: publish-name.sh <name>}"
address="$(hostname -I | cut -d ' ' -f 1)"
[ -n "$address" ] || { echo "publish-name: no network address yet"; exit 1; }

# -R: no reverse record, the Pi's own hostname keeps that.
exec avahi-publish -a -R "$name.local" "$address"
