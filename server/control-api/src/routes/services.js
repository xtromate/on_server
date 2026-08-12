'use strict';

const express = require('express');
const sv = require('../lib/sv');
const pm2ctl = require('../lib/pm2ctl');

const router = express.Router();

// pm2-managed processes that count as built-in "services" (as opposed to
// user-deployed apps, which live in apps.json and are handled by apps.js).
const KNOWN_PROCESSES = ['control-api', 'telegram-bot'];

function isKnownService(name) {
  return sv.isKnownDaemon(name) || KNOWN_PROCESSES.includes(name);
}

async function describeDaemon(name) {
  const s = await sv.status(name);
  return { name, kind: 'daemon', status: s.status, uptimeSec: s.uptimeSec, pid: s.pid };
}

async function describeProcess(name) {
  const p = await pm2ctl.describe(name);
  if (!p) return { name, kind: 'process', status: 'stopped', uptimeSec: null, pid: null };
  return { name, kind: 'process', status: p.status, uptimeSec: p.uptimeSec, pid: p.pid };
}

async function describeService(name) {
  if (sv.isKnownDaemon(name)) return describeDaemon(name);
  if (KNOWN_PROCESSES.includes(name)) return describeProcess(name);
  return null;
}

router.get('/services', async (req, res) => {
  try {
    const daemons = await Promise.all(sv.DAEMONS.map(describeDaemon));
    const processes = await Promise.all(KNOWN_PROCESSES.map(describeProcess));
    res.status(200).json({ services: [...daemons, ...processes] });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

router.post('/services/:name/:action(start|stop|restart)', async (req, res) => {
  const { name, action } = req.params;

  // Block anything not in the fixed allow-list before touching the shell.
  if (!isKnownService(name)) {
    return res.status(404).json({ ok: false, error: `unknown service: ${name}` });
  }

  try {
    if (sv.isKnownDaemon(name)) {
      if (action === 'start') await sv.up(name);
      else if (action === 'stop') await sv.down(name);
      else await sv.restart(name);
      const service = await describeDaemon(name);
      return res.status(200).json({ ok: true, service });
    }

    // pm2-managed process
    if (action === 'start') await pm2ctl.startByName(name);
    else if (action === 'stop') await pm2ctl.stop(name);
    else await pm2ctl.restart(name);
    const service = await describeProcess(name);
    return res.status(200).json({ ok: true, service });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

router.get('/services/:name/logs', async (req, res) => {
  const { name } = req.params;
  const lines = Math.max(1, Math.min(2000, Number(req.query.lines) || 200));

  if (!isKnownService(name)) {
    return res.status(404).json({ ok: false, error: `unknown service: ${name}` });
  }

  try {
    if (sv.isKnownDaemon(name)) {
      // termux-services log output lives under the service's ./log/main
      // virtual-logger directory; simplest reliable path is via svlogtail
      // if present, otherwise fall back to an empty list rather than fail.
      const path = require('path');
      const fs = require('fs');
      const os = require('os');
      // Termux sets $PREFIX to its usr dir (normally
      // /data/data/com.termux/files/usr); fall back to deriving it from
      // $HOME's sibling "usr" dir on the off chance PREFIX isn't set.
      const prefix = process.env.PREFIX || path.join(os.homedir(), '..', 'usr');
      const logDir = path.join(prefix, 'var', 'service', name, 'log', 'main');
      let out = [];
      try {
        const candidate = path.join(logDir, 'current');
        if (fs.existsSync(candidate)) {
          const raw = fs.readFileSync(candidate, 'utf8');
          out = raw.split(/\r?\n/).filter(Boolean).slice(-lines);
        }
      } catch (_) {
        out = [];
      }
      return res.status(200).json({ name, lines: out });
    }

    const out = await pm2ctl.logs(name, lines);
    return res.status(200).json({ name, lines: out });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

module.exports = router;
