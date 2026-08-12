'use strict';

const express = require('express');
const fs = require('fs');
const os = require('os');
const { run } = require('../lib/exec');
const { NAS_ROOT } = require('../config');

const router = express.Router();

function readLoadAvg() {
  try {
    const raw = fs.readFileSync('/proc/loadavg', 'utf8').trim();
    const [load1, load5, load15] = raw.split(/\s+/).map(Number);
    return { load1, load5, load15 };
  } catch (_) {
    // /proc/loadavg is Linux-only; fall back to Node's own loadavg() so this
    // route still returns something sane if the file isn't readable.
    const [load1, load5, load15] = os.loadavg();
    return { load1, load5, load15 };
  }
}

function readMem() {
  try {
    const raw = fs.readFileSync('/proc/meminfo', 'utf8');
    const grab = (key) => {
      const m = new RegExp(`^${key}:\\s+(\\d+)\\s*kB`, 'm').exec(raw);
      return m ? Number(m[1]) : null;
    };
    const totalKb = grab('MemTotal');
    const availableKb = grab('MemAvailable');
    const freeKb = availableKb !== null ? availableKb : grab('MemFree');
    const usedKb = totalKb !== null && freeKb !== null ? totalKb - freeKb : null;
    return { totalKb, usedKb, freeKb };
  } catch (_) {
    const totalKb = Math.round(os.totalmem() / 1024);
    const freeKb = Math.round(os.freemem() / 1024);
    return { totalKb, usedKb: totalKb - freeKb, freeKb };
  }
}

async function readDisk(mountPath) {
  try {
    const { stdout } = await run('df', ['-k', mountPath], { timeout: 5000 });
    const lines = stdout.trim().split('\n').filter(Boolean);
    const dataLine = lines[lines.length - 1];
    const fields = dataLine.trim().split(/\s+/);
    // Filesystem, 1K-blocks, Used, Available, Use%, Mounted on
    if (fields.length < 6) throw new Error('unexpected df output');
    const totalKb = Number(fields[1]);
    const usedKb = Number(fields[2]);
    const freeKb = Number(fields[3]);
    const reportedMount = fields.slice(5).join(' ') || mountPath;
    return { totalKb, usedKb, freeKb, mountPath: reportedMount };
  } catch (err) {
    return { totalKb: null, usedKb: null, freeKb: null, mountPath };
  }
}

async function readBattery() {
  try {
    const { stdout } = await run('termux-battery-status', [], { timeout: 5000 });
    const data = JSON.parse(stdout);
    return {
      percentage: typeof data.percentage === 'number' ? data.percentage : null,
      status: data.status || null,
      temperature: typeof data.temperature === 'number' ? data.temperature : null,
    };
  } catch (_) {
    // termux-api isn't installed/available (or this isn't a phone) — battery
    // is documented as nullable for exactly this case.
    return null;
  }
}

router.get('/metrics', async (req, res) => {
  try {
    const cpu = readLoadAvg();
    const mem = readMem();
    // df needs a path that actually exists; fall back to $HOME if the NAS
    // folder hasn't been created yet (e.g. before termux-setup-storage ran).
    const diskTarget = fs.existsSync(NAS_ROOT) ? NAS_ROOT : os.homedir();
    const disk = await readDisk(diskTarget);
    const battery = await readBattery();
    res.status(200).json({ cpu, mem, disk, battery, timestamp: Date.now() });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

module.exports = router;
