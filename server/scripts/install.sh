#!/data/data/com.termux/files/usr/bin/bash
# on_server — step 1: install packages + project dependencies.
#
# Run this from inside Termux (NOT adb shell, NOT a regular Linux distro —
# this script assumes the Termux package manager `pkg` and Termux's
# filesystem layout under $PREFIX / $HOME).
#
#   bash server/scripts/install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> on_server install.sh starting"
echo "    server dir: $SERVER_DIR"

echo "==> Updating package lists"
pkg update -y

echo "==> Installing base packages (this can take a while on first run)"
# nodejs        control-api + telegram-bot runtime
# python        general scripting / apps that need it
# php           demo php-fpm page behind nginx
# nginx         reverse proxy + static/php demo
# redis         installed + enabled via sv, no app built on top per plan
# sqlite        sqlite3 CLI (control-api itself uses node:sqlite, no native build)
# postgresql    installed + enabled via sv; role/db creation documented in SETUP.md
# openssh       sshd daemon, remote shell access
# git           clone/pull for the Apps feature
# termux-api    battery status etc. for /api/metrics (needs the Termux:API app too)
# termux-services  sv-enable / sv up/down/restart for daemons
# clang, make   build tools some npm/pip packages may need at install time
# openssl       `openssl rand -hex 32` for generating the control-api auth token
pkg install -y \
  nodejs \
  python \
  php \
  nginx \
  redis \
  sqlite \
  postgresql \
  openssh \
  git \
  termux-api \
  termux-services \
  clang \
  make \
  openssl

echo "==> Installing pm2 globally"
npm install -g pm2

echo "==> Setting up shared storage access"
echo "    termux-setup-storage will show an Android permission prompt —"
echo "    please tap 'Allow' when it appears so the NAS folder is visible"
echo "    from normal Android file manager apps too."
termux-setup-storage
# termux-setup-storage runs async / may need a moment for ~/storage to populate.
sleep 2

NAS_ROOT="$HOME/storage/shared/OnServerNAS"
mkdir -p "$NAS_ROOT"
echo "==> NAS root ready at: $NAS_ROOT"

echo "==> Installing control-api dependencies"
(cd "$SERVER_DIR/control-api" && npm install)

echo "==> Installing telegram-bot dependencies"
(cd "$SERVER_DIR/services/telegram-bot" && npm install)

echo ""
echo "==> install.sh complete."
echo "    Next: bash server/scripts/setup-services.sh"
