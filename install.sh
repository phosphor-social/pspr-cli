#!/bin/sh
set -euo pipefail

URL="https://raw.githubusercontent.com/phosphor-social/pspr-cli/refs/heads/main/pspr.sh"
DEST="/usr/local/bin/pspr"

# Ensure running with sufficient privileges or re-exec with sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "Elevating privileges to install to ${DEST}..."
  exec sudo -E bash "$0" "$@"
fi

# Create temp file
TMP="$(mktemp)"
cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT

echo "Downloading from ${URL}..."
curl -fsSL "$URL" -o "$TMP"

# Optional: basic sanity check that it looks like a shell script
if ! head -n 1 "$TMP" | grep -Eq '^#!'; then
  echo "Warning: downloaded file does not start with a shebang. Proceeding anyway."
fi

echo "Installing to ${DEST}..."
install -m 0755 "$TMP" "$DEST"

echo "Installed ${DEST}"