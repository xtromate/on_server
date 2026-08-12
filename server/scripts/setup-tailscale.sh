#!/data/data/com.termux/files/usr/bin/bash
# on_server — step 3: install + bring up Tailscale in userspace-networking
# mode, so the phone gets a stable tailnet IP reachable from any other
# tailnet device (this is what makes "run my backend from my phone, access
# it from anywhere" actually work for the Apps feature).
#
# IMPORTANT — read before running:
# Termux is an unprivileged app and cannot create a system-wide VPN
# interface (that requires root, or Android's VpnService which only the
# official Tailscale Android app has access to). Running tailscaled here in
# --tun=userspace-networking mode does NOT turn this phone into a full
# tailnet VPN client — it does NOT route this phone's own outbound traffic
# through the tailnet, and it does NOT let this phone reach other tailnet
# devices' services transparently. What it DOES do: gives this phone a
# real, stable tailnet IP address that other tailnet devices can connect to
# directly, which is exactly what's needed for control-api / nginx / Apps
# ports to be reachable remotely. If you also want this phone to act as a
# full VPN client on the tailnet, install the official Tailscale app from
# the Play Store instead/alongside this.
#
# Run after setup-services.sh:
#   bash server/scripts/setup-tailscale.sh
#
set -euo pipefail

: "${PREFIX:?PREFIX is not set — this script must be run inside Termux}"

echo "==> on_server setup-tailscale.sh starting"
echo "    (see the comment block at the top of this script for what"
echo "    userspace-networking mode does and doesn't give you)"

echo "==> Installing tailscale"
pkg install -y tailscale

STATE_DIR="$HOME/.on_server"
mkdir -p "$STATE_DIR"
TAILSCALED_LOG="$STATE_DIR/tailscaled.log"
TAILSCALED_SOCK="$PREFIX/var/run/tailscale/tailscaled.sock"
mkdir -p "$(dirname "$TAILSCALED_SOCK")"

if pgrep -f "tailscaled --tun=userspace-networking" >/dev/null 2>&1; then
  echo "==> tailscaled already running, skipping start"
else
  echo "==> Starting tailscaled in userspace-networking mode (background, logging to $TAILSCALED_LOG)"
  # nohup + background so it survives this script exiting; a Termux session
  # dying still kills it though, hence also wiring it into
  # ~/.termux/boot/start-on-server.sh separately would be needed for full
  # boot persistence (left as a documented step in SETUP.md — tailscaled
  # under Termux:Boot needs the same nohup treatment).
  nohup tailscaled --tun=userspace-networking --socket="$TAILSCALED_SOCK" \
    > "$TAILSCALED_LOG" 2>&1 &
  disown
  sleep 2
fi

echo "==> Bringing the tailnet interface up (tailscale up)"
echo "    This will print a login URL if this phone isn't authenticated to"
echo "    your tailnet yet — open it in a browser and approve the device."
tailscale --socket="$TAILSCALED_SOCK" up

echo "==> Fetching tailnet IP"
TAILNET_IP="$(tailscale --socket="$TAILSCALED_SOCK" ip -4 2>/dev/null | head -n1)"

echo ""
echo "================================================================"
echo " on_server setup-tailscale.sh complete"
echo "================================================================"
if [ -n "$TAILNET_IP" ]; then
  echo " Tailnet IP: $TAILNET_IP"
  echo " control-api reachable at: http://$TAILNET_IP:8420"
  echo " nginx demo reachable at:  http://$TAILNET_IP:8080"
else
  echo " Could not determine tailnet IP automatically."
  echo " Run: tailscale --socket=$TAILSCALED_SOCK ip -4"
fi
echo ""
echo " Reminder: this gives the phone a reachable tailnet address, it is"
echo " NOT a system-wide VPN client (see comment block at top of this"
echo " script / docs/SETUP.md for why, and what to use instead if you"
echo " need that)."
echo "================================================================"
