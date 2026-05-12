#!/usr/bin/env bash
set -euo pipefail

REF="${MIZAN_REF:-v2.5-stable}"

echo "=================================================="
echo "Mizan POS updater"
echo "=================================================="
echo "Target version: $REF"
echo

if [ "$EUID" -ne 0 ]; then
  echo "Please run this updater with sudo."
  exit 1
fi

find_project_dir() {
  for dir in \
    "/home/${SUDO_USER:-}/Desktop/POS-System-2.5" \
    /home/*/Desktop/POS-System-2.5
  do
    if [ -d "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
  done

  return 1
}

PROJECT_DIR="$(find_project_dir || true)"

if [ -z "${PROJECT_DIR:-}" ]; then
  echo "Could not find installed POS project under /home/*/Desktop/POS-System-2.5"
  exit 1
fi

PROJECT_OWNER="$(stat -c '%U' "$PROJECT_DIR")"
PROJECT_HOME="$(getent passwd "$PROJECT_OWNER" | cut -d: -f6)"

echo "Project: $PROJECT_DIR"
echo "User:    $PROJECT_OWNER"
echo

cd "$PROJECT_DIR"

CURRENT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BACKUP_DIR="$PROJECT_DIR/backups/update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Current commit: $CURRENT_COMMIT"
echo "$CURRENT_COMMIT" > "$BACKUP_DIR/previous-commit.txt"

echo
echo "---- Stopping services ----"
systemctl stop lightdm 2>/dev/null || true
systemctl stop mizan-server.service 2>/dev/null || true
pkill -f electron 2>/dev/null || true
pkill -f start-pos-production 2>/dev/null || true
pkill -f start-mizan 2>/dev/null || true
pkill -f "npm run dev:api" 2>/dev/null || true
pkill -f "npm run dev:backoffice" 2>/dev/null || true

echo
echo "---- Backing up local env files ----"
for file in \
  "$PROJECT_DIR/.env" \
  "$PROJECT_DIR/apps/api/.env" \
  "$PROJECT_DIR/apps/backoffice-web/.env" \
  "$PROJECT_DIR/apps/pos-desktop/.env"
do
  if [ -f "$file" ]; then
    safe="$(echo "$file" | sed 's#/#_#g')"
    cp "$file" "$BACKUP_DIR/$safe"
  fi
done

echo
echo "---- Fetching latest code from GitHub ----"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  ASKPASS_SCRIPT="$(mktemp)"

  cat > "$ASKPASS_SCRIPT" <<'ASKPASSEOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN:-}" ;;
  *) printf '\n' ;;
esac
ASKPASSEOF

  chmod 755 "$ASKPASS_SCRIPT"

  sudo -u "$PROJECT_OWNER" env \
    GIT_ASKPASS="$ASKPASS_SCRIPT" \
    GIT_TERMINAL_PROMPT=0 \
    GITHUB_TOKEN="$GITHUB_TOKEN" \
    git fetch origin --tags --force

  rm -f "$ASKPASS_SCRIPT"
else
  sudo -u "$PROJECT_OWNER" git fetch origin --tags --force
fi

if sudo -u "$PROJECT_OWNER" git rev-parse -q --verify "refs/tags/$REF^{commit}" >/dev/null; then
  TARGET_REF="refs/tags/$REF"
elif sudo -u "$PROJECT_OWNER" git rev-parse -q --verify "origin/$REF^{commit}" >/dev/null; then
  TARGET_REF="origin/$REF"
else
  echo "Could not find ref '$REF' as a tag or remote branch."
  echo
  echo "Available recent tags:"
  git tag --sort=-creatordate | head -n 10 || true
  exit 1
fi

echo
echo "---- Resetting project to $REF ----"
sudo -u "$PROJECT_OWNER" git reset --hard "$TARGET_REF"

echo
echo "Updated from $CURRENT_COMMIT to:"
git rev-parse --short HEAD

echo
echo "---- Fixing ownership ----"
chown -R "$PROJECT_OWNER:$PROJECT_OWNER" "$PROJECT_DIR"
chown -R "$PROJECT_OWNER:$PROJECT_OWNER" "$PROJECT_HOME/.npm" 2>/dev/null || true

echo
echo "---- Installing dependencies ----"
sudo -u "$PROJECT_OWNER" npm install

echo
echo "---- Starting PostgreSQL and Redis ----"
docker compose up -d postgres redis

until docker exec pos-postgres pg_isready -U pos -d pos_system >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

echo
echo "---- Running Prisma ----"
sudo -u "$PROJECT_OWNER" npm --workspace apps/api exec prisma generate
sudo -u "$PROJECT_OWNER" npm --workspace apps/api exec prisma migrate deploy

echo
echo "---- Building Back Office ----"
sudo -u "$PROJECT_OWNER" npm --workspace apps/backoffice-web run build

echo
echo "---- Rebuilding POS native modules ----"
sudo -u "$PROJECT_OWNER" npm --workspace apps/pos-desktop run rebuild:native

echo
echo "---- Building POS Desktop ----"
rm -rf "$PROJECT_DIR/apps/pos-desktop/dist"
sudo -u "$PROJECT_OWNER" npm --workspace apps/pos-desktop run build

echo
echo "---- Restarting services ----"
systemctl restart mizan-server.service

if systemctl list-unit-files | grep -q '^lightdm.service'; then
  systemctl restart lightdm
fi

echo
echo "---- Health check ----"
sleep 6
curl -fsS http://localhost:3000/api/health || true

echo
echo "=================================================="
echo "Mizan POS update complete."
echo "Backup folder:"
echo "$BACKUP_DIR"
echo "=================================================="
