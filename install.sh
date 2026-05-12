#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="RemiX009"
PRIVATE_REPO="Mizan-pos-system"
INSTALLER_PATH="deployment/install-mizan-pos-standalone.sh"
REF="${MIZAN_REF:-main}"

echo "=================================================="
echo "Mizan POS Bootstrap Installer"
echo "=================================================="
echo

if ! command -v curl >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
  echo "Installing required tools..."
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates tmux
fi

read -rsp "GitHub token for private POS repo: " GITHUB_TOKEN </dev/tty
echo >/dev/tty

if [ -z "$GITHUB_TOKEN" ]; then
  echo "GitHub token is required because the POS repository is private."
  exit 1
fi

INSTALLER="/tmp/install-mizan-pos-standalone.sh"

echo "Downloading Mizan POS installer from GitHub..."

curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/${REPO_OWNER}/${PRIVATE_REPO}/contents/${INSTALLER_PATH}?ref=${REF}" \
  -o "$INSTALLER"

chmod +x "$INSTALLER"

echo
echo "Starting installer inside tmux session: mizan-install"
echo "If SSH disconnects, reconnect and run:"
echo "tmux attach -t mizan-install"
echo

export GITHUB_TOKEN

tmux new -s mizan-install "sudo GITHUB_TOKEN=\"$GITHUB_TOKEN\" bash \"$INSTALLER\"; echo; read -rp 'Installer finished. Press Enter to close...'"

unset GITHUB_TOKEN
