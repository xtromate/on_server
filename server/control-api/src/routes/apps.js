'use strict';

const express = require('express');
const fs = require('fs');
const path = require('path');
const { APPS_ROOT, loadApps, saveApps, loadConfig } = require('../config');
const git = require('../lib/git');
const pm2ctl = require('../lib/pm2ctl');
const { runShell } = require('../lib/exec');

const router = express.Router();

const NAME_RE = /^[a-zA-Z0-9_-]{1,64}$/;
const KNOWN_PROCESS_NAMES = ['control-api', 'telegram-bot'];
// Ports we know are (or will be) bound by the fixed daemon stack, so an app
// can't be registered on top of them. control-api's own port is added
// dynamically from config below.
const RESERVED_DAEMON_PORTS = {
  8080: 'nginx',
  6379: 'redis',
  5432: 'postgresql',
  8022: 'sshd',
};

function isSafeName(name) {
  return typeof name === 'string' && NAME_RE.test(name);
}

// Resolves an app's directory from its (already slug-validated) name and
// verifies the result is still inside APPS_ROOT — defense in depth against
// path traversal even though the slug regex already blocks "..".
function resolveAppDir(name) {
  const root = path.resolve(APPS_ROOT);
  const dest = path.resolve(root, name);
  if (dest !== root && !dest.startsWith(root + path.sep)) {
    throw new Error('invalid app path');
  }
  return dest;
}

function getHost(req, config) {
  if (config.publicHost) return config.publicHost;
  const hostHeader = req.headers.host || '';
  return hostHeader.split(':')[0] || 'localhost';
}

async function buildAppView(entry, req, config) {
  const pm2Info = await pm2ctl.describe(entry.name).catch(() => null);
  const status = pm2Info ? pm2Info.status : 'stopped';
  const pid = pm2Info ? pm2Info.pid : null;
  return {
    name: entry.name,
    repoUrl: entry.repoUrl,
    branch: entry.branch || null,
    installCommand: entry.installCommand || null,
    startCommand: entry.startCommand,
    port: entry.port,
    status,
    pid,
    url: `http://${getHost(req, config)}:${entry.port}`,
    createdAt: entry.createdAt,
  };
}

function rmDirSafe(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch (_) {
    // best-effort cleanup
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function writeWrapperScript({ appDir, port, startCommand, env }) {
  const lines = [
    '#!/data/data/com.termux/files/usr/bin/bash',
    `cd ${shellQuote(appDir)}`,
    `export PORT=${shellQuote(String(port))}`,
  ];
  if (env && typeof env === 'object') {
    for (const [key, value] of Object.entries(env)) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue; // skip unsafe keys
      lines.push(`export ${key}=${shellQuote(value)}`);
    }
  }
  lines.push(`exec ${startCommand}`);
  const wrapperPath = path.join(appDir, '.on-server-start.sh');
  fs.writeFileSync(wrapperPath, lines.join('\n') + '\n', { mode: 0o755 });
  fs.chmodSync(wrapperPath, 0o755);
  return wrapperPath;
}

router.get('/apps', async (req, res) => {
  try {
    const config = loadConfig();
    const apps = loadApps();
    const views = await Promise.all(apps.map((a) => buildAppView(a, req, config)));
    res.status(200).json({ apps: views });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

router.post('/apps', async (req, res) => {
  const { name, repoUrl, branch, installCommand, startCommand, port, env } = req.body || {};

  if (!isSafeName(name)) {
    return res.status(400).json({ ok: false, error: 'name must be a safe slug (alnum/dash/underscore only)' });
  }
  if (KNOWN_PROCESS_NAMES.includes(name)) {
    return res.status(400).json({ ok: false, error: `name "${name}" is reserved` });
  }
  if (typeof repoUrl !== 'string' || !repoUrl.trim()) {
    return res.status(400).json({ ok: false, error: 'repoUrl is required' });
  }
  if (typeof startCommand !== 'string' || !startCommand.trim()) {
    return res.status(400).json({ ok: false, error: 'startCommand is required' });
  }
  const portNum = Number(port);
  if (!Number.isInteger(portNum) || portNum < 1024 || portNum > 65535) {
    return res.status(400).json({ ok: false, error: 'port must be an integer between 1024 and 65535' });
  }

  const config = loadConfig();
  const controlApiPort = config.port || 8420;
  const reservedPorts = { ...RESERVED_DAEMON_PORTS, [controlApiPort]: 'control-api' };
  if (reservedPorts[portNum]) {
    return res.status(400).json({ ok: false, error: `port ${portNum} is already used by ${reservedPorts[portNum]}` });
  }

  const apps = loadApps();
  if (apps.some((a) => a.name === name)) {
    return res.status(409).json({ ok: false, error: `app "${name}" already exists` });
  }
  const portConflict = apps.find((a) => a.port === portNum);
  if (portConflict) {
    return res.status(400).json({ ok: false, error: `port ${portNum} is already used by app "${portConflict.name}"` });
  }

  let appDir;
  try {
    appDir = resolveAppDir(name);
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }

  if (fs.existsSync(appDir)) {
    return res.status(409).json({ ok: false, error: `directory for "${name}" already exists` });
  }

  // Stage 1: clone
  try {
    fs.mkdirSync(APPS_ROOT, { recursive: true });
    await git.clone({ repoUrl, branch, dest: appDir });
  } catch (err) {
    rmDirSafe(appDir);
    return res.status(500).json({ ok: false, error: `clone failed: ${err.message}`, stage: 'clone' });
  }

  // Stage 2: install
  if (installCommand && String(installCommand).trim()) {
    try {
      await runShell(installCommand, { cwd: appDir });
    } catch (err) {
      rmDirSafe(appDir);
      return res.status(500).json({ ok: false, error: `install failed: ${err.message}`, stage: 'install' });
    }
  }

  // Stage 3: start under pm2 via a wrapper script (see docs/SETUP.md for why
  // a wrapper is used instead of passing a compound command to pm2 directly)
  try {
    const wrapperPath = writeWrapperScript({ appDir, port: portNum, startCommand, env });
    await pm2ctl.start({ name, script: wrapperPath, cwd: appDir });
  } catch (err) {
    await pm2ctl.delete(name).catch(() => {});
    rmDirSafe(appDir);
    return res.status(500).json({ ok: false, error: `start failed: ${err.message}`, stage: 'start' });
  }

  const entry = {
    name,
    repoUrl,
    branch: branch || null,
    installCommand: installCommand || null,
    startCommand,
    port: portNum,
    env: env || null,
    createdAt: new Date().toISOString(),
  };
  apps.push(entry);
  saveApps(apps);

  const view = await buildAppView(entry, req, config);
  res.status(201).json({ ok: true, app: view });
});

function findAppOr404(req, res) {
  const { name } = req.params;
  if (!isSafeName(name)) {
    res.status(404).json({ ok: false, error: 'app not found' });
    return null;
  }
  const apps = loadApps();
  const entry = apps.find((a) => a.name === name);
  if (!entry) {
    res.status(404).json({ ok: false, error: 'app not found' });
    return null;
  }
  return entry;
}

router.post('/apps/:name/redeploy', async (req, res) => {
  const entry = findAppOr404(req, res);
  if (!entry) return;

  let appDir;
  try {
    appDir = resolveAppDir(entry.name);
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }

  try {
    await git.pull({ dest: appDir, branch: entry.branch });
    if (entry.installCommand && String(entry.installCommand).trim()) {
      await runShell(entry.installCommand, { cwd: appDir });
    }
    await pm2ctl.restart(entry.name);
  } catch (err) {
    return res.status(500).json({ ok: false, error: `redeploy failed: ${err.message}` });
  }

  const config = loadConfig();
  const view = await buildAppView(entry, req, config);
  res.status(200).json({ ok: true, app: view });
});

router.post('/apps/:name/:action(start|stop|restart)', async (req, res) => {
  const entry = findAppOr404(req, res);
  if (!entry) return;
  const { action } = req.params;

  try {
    if (action === 'start') await pm2ctl.startByName(entry.name);
    else if (action === 'stop') await pm2ctl.stop(entry.name);
    else await pm2ctl.restart(entry.name);
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }

  const config = loadConfig();
  const view = await buildAppView(entry, req, config);
  res.status(200).json({ ok: true, app: view });
});

router.get('/apps/:name/logs', async (req, res) => {
  const entry = findAppOr404(req, res);
  if (!entry) return;
  const lines = Math.max(1, Math.min(2000, Number(req.query.lines) || 200));

  try {
    const out = await pm2ctl.logs(entry.name, lines);
    res.status(200).json({ name: entry.name, lines: out });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

router.delete('/apps/:name', async (req, res) => {
  const entry = findAppOr404(req, res);
  if (!entry) return;

  const removeFiles = String(req.query.removeFiles).toLowerCase() === 'true';

  try {
    await pm2ctl.delete(entry.name);
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }

  if (removeFiles) {
    try {
      const appDir = resolveAppDir(entry.name);
      rmDirSafe(appDir);
    } catch (_) {
      // ignore — resolveAppDir already validated the name at registration time
    }
  }

  const apps = loadApps().filter((a) => a.name !== entry.name);
  saveApps(apps);

  res.status(200).json({ ok: true });
});

module.exports = router;
