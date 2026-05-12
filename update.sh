#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="RemiX009"
PRIVATE_REPO="Mizan-pos-system"
UPDATE_PATH="deployment/update-mizan-pos.sh"
SCRIPT_REF="${MIZAN_SCRIPT_REF:-main}"
MIZAN_REF="${MIZAN_REF:-v2.5-stable}"

echo "=================================================="
echo "Mizan POS Update Bootstrap"
echo "=================================================="
echo "Project version: $MIZAN_REF"
echo

echo "Installing required tools..."
sudo apt-get update
sudo apt-get install -y curl ca-certificates git

if ! command -v gh >/dev/null 2>&1; then
  echo "Installing GitHub CLI..."

  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null

  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y gh
fi

if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "GitHub login required."
  echo "A short code will appear."
  echo "Open the shown GitHub URL on your normal PC/phone and enter the code."
  echo

  gh auth login --hostname github.com --git-protocol https --web
fi

GITHUB_TOKEN="$(gh auth token)"
UPDATER="$HOME/update-mizan-pos.sh"

echo
echo "Downloading Mizan POS updater..."

curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/${REPO_OWNER}/${PRIVATE_REPO}/contents/${UPDATE_PATH}?ref=${SCRIPT_REF}" \
  -o "$UPDATER"

chmod +x "$UPDATER"

echo
echo "Starting Mizan POS updater..."
echo

sudo GITHUB_TOKEN="$GITHUB_TOKEN" MIZAN_REF="$MIZAN_REF" bash "$UPDATER"
