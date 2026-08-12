'use strict';

const fs = require('fs');
const { run } = require('./exec');

// Thin wrapper around the pm2 CLI (jlist/start/stop/restart/delete + log
// tailing). Used by both services.js (for the control-api/telegram-bot
// processes) and apps.js (for user-deployed backends).

async function jlist() {
  const { stdout } = await run('pm2', ['jlist'], { maxBuffer: 10 * 1024 * 1024 });
  try {
    return JSON.parse(stdout);
  } catch (err) {
    throw new Error(`failed to parse pm2 jlist output: ${err.message}`);
  }
}

function normalizeStatus(pm2Status) {
  if (pm2Status === 'online') return 'running';
  if (pm2Status === 'stopped' || pm2Status === 'stopping') return 'stopped';
  return 'unknown';
}

function toSummary(proc) {
  const env = proc.pm2_env || {};
  const status = normalizeStatus(env.status);
  const uptimeSec =
    status === 'running' && env.pm_uptime ? Math.max(0, Math.round((Date.now() - env.pm_uptime) / 1000)) : null;
  return {
    name: proc.name,
    pid: status === 'running' ? proc.pid : null,
    status,
    uptimeSec,
    outLogPath: env.pm_out_log_path || null,
    errLogPath: env.pm_err_log_path || null,
  };
}

async function list() {
  const procs = await jlist();
  return procs.map(toSummary);
}

async function describe(name) {
  const procs = await jlist();
  const proc = procs.find((p) => p.name === name);
  return proc ? toSummary(proc) : null;
}

// Starts a script under pm2. `script` should be a single executable path
// (e.g. a wrapper shell script for user apps, or a plain .js entry point) —
// never a compound shell command string, since pm2's CLI arg-parsing
// mishandles those. `env` (optional) is merged into the CLI's own process
// env so pm2 captures it for this app at start time.
async function start({ name, script, cwd, env }) {
  const args = ['start', script, '--name', name];
  if (cwd) args.push('--cwd', cwd);
  await run('pm2', args, { env: env ? { ...process.env, ...env } : process.env });
  return describe(name);
}

// Starts an already-registered pm2 process by name (e.g. control-api /
// telegram-bot, registered once via `pm2 start ecosystem.config.js`).
// Unlike start(), this does not take a script path — pm2 already knows it.
async function startByName(name) {
  await run('pm2', ['start', name]);
  return describe(name);
}

async function stop(name) {
  await run('pm2', ['stop', name]);
  return describe(name);
}

async function restart(name) {
  await run('pm2', ['restart', name]);
  return describe(name);
}

async function del(name) {
  try {
    await run('pm2', ['delete', name]);
  } catch (err) {
    // Already gone / never started — not a failure for our purposes.
    if (!/not found/i.test(`${err.stdout || ''}${err.stderr || ''}`)) throw err;
  }
}

// Tails the last `n` lines out of a log file without loading the whole
// thing into memory when it's large.
function tailFile(filePath, n) {
  if (!filePath || !fs.existsSync(filePath)) return [];
  const stat = fs.statSync(filePath);
  const maxBytes = 512 * 1024; // enough for a few hundred lines of typical output
  const start = Math.max(0, stat.size - maxBytes);
  const fd = fs.openSync(filePath, 'r');
  try {
    const length = stat.size - start;
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    const text = buffer.toString('utf8');
    const lines = text.split(/\r?\n/).filter((l, idx, arr) => !(l === '' && idx === arr.length - 1));
    return lines.slice(-n);
  } finally {
    fs.closeSync(fd);
  }
}

async function logs(name, lines = 200) {
  const proc = await describe(name);
  if (!proc) return [];
  const outLines = tailFile(proc.outLogPath, lines).map((l) => l);
  const errLines = tailFile(proc.errLogPath, lines).map((l) => `[err] ${l}`);
  return [...outLines, ...errLines].slice(-lines);
}

module.exports = { list, describe, start, startByName, stop, restart, delete: del, logs };
