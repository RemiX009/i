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

if [ ! -r /dev/tty ]; then
  echo "No interactive terminal detected."
  echo
  echo "Run this instead:"
  echo "bash <(curl -fsSL https://remix009.github.io/i/install.sh)"
  exit 1
fi

sudo apt-get update
sudo apt-get install -y curl ca-certificates git tmux

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
  echo "A short code will appear. Open the shown URL on your normal PC/phone and enter the code."
  echo

  gh auth login --hostname github.com --git-protocol https --web < /dev/tty > /dev/tty 2>&1
fi

GITHUB_TOKEN="$(gh auth token)"

INSTALLER="$HOME/install-mizan-pos-standalone.sh"

echo
echo "Downloading Mizan POS installer..."

curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/${REPO_OWNER}/${PRIVATE_REPO}/contents/${INSTALLER_PATH}?ref=${REF}" \
  -o "$INSTALLER"

chmod +x "$INSTALLER"

echo
echo "Starting Mizan POS installer..."
echo

if [ -n "${TMUX:-}" ] || [ "${MIZAN_NO_TMUX:-}" = "1" ]; then
  sudo GITHUB_TOKEN="$GITHUB_TOKEN" bash "$INSTALLER"
else
  if command -v tmux >/dev/null 2>&1 && [ -t 1 ]; then
    TOKEN_FILE="$HOME/.mizan-github-token"
    RUNNER="$HOME/.mizan-install-runner.sh"

    printf "%s" "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"

    cat > "$RUNNER" <<'RUNNEREOF'
#!/usr/bin/env bash
set -euo pipefail

TOKEN_FILE="$HOME/.mizan-github-token"
INSTALLER="$HOME/install-mizan-pos-standalone.sh"

GITHUB_TOKEN="$(cat "$TOKEN_FILE")"

sudo GITHUB_TOKEN="$GITHUB_TOKEN" bash "$INSTALLER"

rm -f "$TOKEN_FILE"

echo
read -rp "Installer finished. Press Enter to close..."
RUNNEREOF

    chmod 700 "$RUNNER"

    echo "Opening tmux session: mizan-install"
    echo "If SSH disconnects, reconnect and run:"
    echo "tmux attach -t mizan-install"
    echo

    tmux new-session -s mizan-install "bash '$RUNNER'" < /dev/tty > /dev/tty 2>&1
  else
    echo "tmux is not available or no terminal was detected, running installer directly."
    sudo GITHUB_TOKEN="$GITHUB_TOKEN" bash "$INSTALLER"
  fi
fi
