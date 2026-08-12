# on_server — Termux backend setup

This turns an old Android phone into a personal server: nginx + PHP, Redis,
Postgres, SSH, a file/NAS server, a Telegram status bot, and the flagship
**Apps** feature — deploy any git repo as a running backend reachable at
`http://<phone-ip>:<port>` from any other device.

Everything below runs **inside Termux on the phone itself** (or via
`ssh` into Termux once sshd is up) — not on your regular computer.

## 0. Prerequisites

- [Termux](https://termux.dev) installed (F-Droid build recommended over the
  Play Store build, which is unmaintained).
- (Optional but recommended) [Termux:API](https://f-droid.org/packages/com.termux.api/)
  app installed, for battery metrics in `GET /api/metrics`.
- (Optional) [Termux:Boot](https://f-droid.org/packages/com.termux.boot/)
  app installed and opened once, if you want the stack to auto-start on
  phone reboot.
- This repo present on the phone, e.g. cloned or synced under
  `~/on_server_repo` (any path is fine — the scripts figure out their own
  location).

## 1. Install packages + dependencies

```bash
bash server/scripts/install.sh
```

This installs (via `pkg`): `nodejs`, `python`, `php`, `nginx`, `redis`,
`sqlite`, `postgresql`, `openssh`, `git`, `termux-api`, `termux-services`,
`clang`, `make`, `openssl`; then `npm install -g pm2`; then runs
`termux-setup-storage` (**this pops an Android permission prompt — tap
Allow**) and creates the NAS folder at `~/storage/shared/OnServerNAS`
(also visible from any normal Android file manager app); then runs
`npm install` inside both `server/control-api/` and
`server/services/telegram-bot/`.

## 2. Enable services, generate your token, start pm2

```bash
bash server/scripts/setup-services.sh
```

This:
- `sv-enable`s the termux-services daemons: `nginx`, `redis`, `postgresql`, `sshd`
- runs `initdb` for Postgres on first run
- deploys `server/services/nginx/nginx.conf.template` to
  `$PREFIX/etc/nginx/nginx.conf` (backing up any existing config to
  `nginx.conf.orig` first) — nginx listens on port **8080** (Termux can't
  bind port 80 without root)
- starts `php-fpm` directly (it isn't a termux-services daemon)
- generates your control-api auth token with `openssl rand -hex 32` and
  writes it into `~/.on_server/config.json`
- brings the daemons up with `sv up`
- starts control-api + the telegram bot with
  `pm2 start ecosystem.config.js` (run from `server/control-api/`) and
  persists them with `pm2 save`
- writes `~/.termux/boot/start-on-server.sh` for Termux:Boot auto-start

**At the end it prints your auth token and best-guess LAN IP** — copy the
token now, you'll need it for the Flutter app and for every `curl` example
below. Example of what's printed:

```
================================================================
 on_server setup-services.sh complete
================================================================
 Your control-api token:  6f2e1c9a...        (64 hex chars)
 -> paste this into the Flutter app's Settings screen

 Phone LAN IP (best guess): 192.168.1.42
 control-api:  http://192.168.1.42:8420
 nginx demo:   http://192.168.1.42:8080

 Next: bash server/scripts/setup-tailscale.sh (for remote access
 beyond your local WiFi).
================================================================
```

If the IP guess is wrong (multiple network interfaces, etc.), check
Android's WiFi settings screen for the phone's IP, or run `ip addr` /
`ifconfig` yourself inside Termux.

## 3. Bring up Tailscale (remote access beyond your WiFi)

```bash
bash server/scripts/setup-tailscale.sh
```

Installs `tailscale`, starts `tailscaled --tun=userspace-networking` in the
background (logs at `~/.on_server/tailscaled.log`), runs `tailscale up`
(follow the printed login URL to authenticate the device to your tailnet
the first time), and prints the phone's tailnet IP.

**Important nuance**: Termux can't create a system VPN interface without
root, so this does **not** turn the phone into a full VPN client — it gives
the phone a stable tailnet IP that *other* tailnet devices can reach, which
is exactly what Apps/control-api/nginx need to be reachable remotely. If
you additionally want this phone itself to route its own traffic through
the tailnet as a VPN client, install the official Tailscale Android app
from the Play Store alongside this.

## 4. Verify each piece

```bash
# control-api itself (no auth needed)
curl http://localhost:8420/api/health
# -> {"ok":true,"time":1234567890123}

# daemons
sv status nginx redis postgresql sshd

# pm2-managed processes
pm2 ls

# nginx demo page
curl -I http://localhost:8080/
curl http://localhost:8080/info.php

# an authenticated control-api route (replace TOKEN)
export TOKEN="paste-your-token-here"
curl -H "Authorization: Bearer $TOKEN" http://localhost:8420/api/services
curl -H "Authorization: Bearer $TOKEN" http://localhost:8420/api/metrics

# from a second device once Tailscale is up
curl http://<phone-tailnet-ip>:8420/api/health
```

## 5. Register an app (the flagship feature)

Deploy any git repo as a running backend under pm2, reachable at
`http://<phone-ip>:<port>`:

```bash
curl -X POST http://localhost:8420/api/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-api",
    "repoUrl": "https://github.com/example/my-api.git",
    "branch": "main",
    "installCommand": "npm install",
    "startCommand": "node server.js",
    "port": 9001
  }'
```

On success (`201`) the response includes `app.url`, e.g.
`http://192.168.1.42:9001` (or the phone's tailnet IP if you set
`publicHost` — see below). Other useful routes:

```bash
curl http://localhost:8420/api/apps -H "Authorization: Bearer $TOKEN"
curl -X POST http://localhost:8420/api/apps/my-api/redeploy -H "Authorization: Bearer $TOKEN"
curl -X POST http://localhost:8420/api/apps/my-api/restart  -H "Authorization: Bearer $TOKEN"
curl "http://localhost:8420/api/apps/my-api/logs?lines=100" -H "Authorization: Bearer $TOKEN"
curl -X DELETE "http://localhost:8420/api/apps/my-api?removeFiles=true" -H "Authorization: Bearer $TOKEN"
```

Notes:
- `port` must be free (not used by another app, and not `8080`/`6379`/`5432`/`8022`/control-api's own port), and in the range `1024`–`65535`.
- `name` must be a safe slug (letters/digits/`-`/`_` only) — it's used both as a directory name under `~/on_server/apps/` and as the pm2 process name.
- Internally, control-api writes a small wrapper script
  (`.on-server-start.sh`) into the app's directory instead of passing
  `startCommand` to pm2 directly — pm2's argument parsing mishandles
  compound shell commands like `"npm start"` or `"php -S 0.0.0.0:$PORT"`.
  The wrapper `cd`s into the app dir, `export`s `PORT` (and any `env` you
  passed), then `exec`s your `startCommand` — this is transparent to you as
  the caller, just documented here in case you're debugging a failed start.
- If registration fails partway through, the response includes
  `"stage": "clone" | "install" | "start"` and the partially-cloned
  directory is cleaned up automatically so you can just retry.

To control which host shows up in `app.url` (instead of whatever `Host`
header the request came in on), set `publicHost` in
`~/.on_server/config.json` to the phone's tailnet IP once you have one from
step 3.

## 6. Postgres: create a role + database (manual, no app built on top)

Postgres is installed and running, but nothing is built on top of it by
default — create what you need:

```bash
# as the termux user, connect to the default 'postgres' maintenance db
psql -U $(whoami) -d postgres

-- inside psql:
CREATE ROLE myapp WITH LOGIN PASSWORD 'changeme';
CREATE DATABASE myapp_db OWNER myapp;
\q

# test it
psql -U myapp -d myapp_db -c '\conninfo'
```

Point any app you register via `POST /api/apps` at
`postgres://myapp:changeme@127.0.0.1:5432/myapp_db` through its own env
config.

## 7. Files (NAS)

Everything under `GET/POST/DELETE /api/files*` is scoped to
`~/storage/shared/OnServerNAS` (created in step 1) — also browsable from
any Android file manager app, since it's under the phone's shared storage.

```bash
curl "http://localhost:8420/api/files?path=/" -H "Authorization: Bearer $TOKEN"
curl -X POST http://localhost:8420/api/files/mkdir -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"path":"/backups"}'
curl -X POST "http://localhost:8420/api/files/upload?path=/backups" \
  -H "Authorization: Bearer $TOKEN" -F "file=@/path/to/local/file.txt"
curl "http://localhost:8420/api/files/download?path=/backups/file.txt" \
  -H "Authorization: Bearer $TOKEN" -o file.txt
curl -X DELETE "http://localhost:8420/api/files?path=/backups/file.txt" \
  -H "Authorization: Bearer $TOKEN"
```

## 8. Telegram bot

```bash
curl -X PUT http://localhost:8420/api/bots/telegram \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"token":"<your-telegram-bot-token-from-BotFather>","enabled":true}'
```

This writes the token into `~/.on_server/config.json` (never echoed back in
any API response — only `hasToken: true`) and restarts the `telegram-bot`
pm2 process so it picks it up. Message the bot `/status` in Telegram to
confirm — it replies with a live summary pulled from control-api's own
`/api/services` and `/api/metrics`.

## 9. Where things live

| What | Where |
|---|---|
| Auth token + all control-api config | `~/.on_server/config.json` |
| Registered apps registry | `~/.on_server/apps.json` |
| Deployed app code | `~/on_server/apps/<name>/` |
| NAS root | `~/storage/shared/OnServerNAS` |
| tailscaled log | `~/.on_server/tailscaled.log` |
| Boot auto-start script | `~/.termux/boot/start-on-server.sh` |

## 10. If the phone reboots

With Termux:Boot installed and opened once, `~/.termux/boot/start-on-server.sh`
(written by `setup-services.sh`) brings the daemons back up (`sv up`),
starts `php-fpm`, and runs `pm2 resurrect` to restore control-api,
telegram-bot, and any registered Apps. Tailscale needs a manual restart
after reboot — `tailscaled` isn't wired into the boot script (userspace
networking under Termux needs to be started fresh each time); re-run:

```bash
bash server/scripts/setup-tailscale.sh
```

## Connecting the Flutter app

The `on_server` Flutter app (under `lib/`) is a pure HTTP client to control-api — it
never talks to Termux directly, so it works whether it's installed on this same phone
or on a completely different device.

1. Run the app (`flutter run`, or a built APK installed on any phone/tablet).
2. On first launch it has no saved connection, so it opens straight to **Settings**.
   Fill in:
   - **Host** — the phone's LAN IP printed at the end of step 2 (e.g. `192.168.1.42`)
     for same-WiFi access, or its tailnet IP from step 3 (e.g. `100.x.y.z`, or the
     MagicDNS name) for access from anywhere. If the app is installed on the *same*
     phone running Termux, `localhost` also works.
   - **Port** — `8420` (control-api's default; already pre-filled).
   - **Token** — the 64-character hex token printed at the end of step 2. Paste it
     exactly; it's never shown again by the server (only `hasToken: true` is returned
     from then on), so if it's lost, regenerate by re-running `setup-services.sh`
     (this issues a new token, overwriting the old one in `~/.on_server/config.json`).
3. Tap **Test connection** — this calls `GET /api/health` (no auth needed) and
   confirms the host/port are reachable before saving.
4. Save. The app lands on the bottom-nav shell: **Dashboard**, **Apps** (the flagship
   deploy screen from step 5 above, with a UI form instead of curl), **Services**
   (the daemons from step 2), **Files** (the NAS from step 7), **Bots** (step 8).

If **Test connection** fails: confirm `pm2 ls` shows `control-api` as `online` on the
phone, that the host/port match what step 2/3 printed, and — if connecting from a
second device — that Tailscale is up on both ends (`tailscale status` on each).
