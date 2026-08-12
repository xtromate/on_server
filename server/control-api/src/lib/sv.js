'use strict';

const { run } = require('./exec');

// Fixed allow-list of termux-services daemons control-api is allowed to touch.
// `sv-enable <name>` installs the service (done once by setup-services.sh);
// this module only ever shells out to `sv status|up|down|restart <name>`
// for names in this list — never for arbitrary user input.
const DAEMONS = ['nginx', 'redis', 'postgresql', 'sshd'];

function isKnownDaemon(name) {
  return DAEMONS.includes(name);
}

// Parses runit's `sv status <name>` output, e.g.:
//   "run: nginx: (pid 1234) 45s"
//   "down: redis: 2s, normally up"
//   "fail: sshd: unable to open supervise/ok: file does not exist"
function parseSvStatus(stdout) {
  const text = (stdout || '').trim();
  const match = /^(run|down|fail)\w*:\s*[^:]*:\s*(?:\(pid\s+(\d+)\)\s*)?(\d+)s/.exec(text);
  if (!match) {
    return { status: 'unknown', pid: null, uptimeSec: null };
  }
  const [, word, pidStr, uptimeStr] = match;
  const status = word === 'run' ? 'running' : word === 'down' ? 'stopped' : 'unknown';
  return {
    status,
    pid: pidStr ? Number(pidStr) : null,
    uptimeSec: uptimeStr ? Number(uptimeStr) : null,
  };
}

async function status(name) {
  if (!isKnownDaemon(name)) {
    return { status: 'unknown', pid: null, uptimeSec: null };
  }
  try {
    const { stdout } = await run('sv', ['status', name]);
    return parseSvStatus(stdout);
  } catch (err) {
    // `sv status` exits non-zero when the service isn't enabled/running yet.
    const combined = `${err.stdout || ''}${err.stderr || ''}`;
    if (combined) return parseSvStatus(combined);
    return { status: 'unknown', pid: null, uptimeSec: null };
  }
}

async function up(name) {
  if (!isKnownDaemon(name)) throw new Error(`unknown daemon: ${name}`);
  await run('sv', ['up', name]);
  return status(name);
}

async function down(name) {
  if (!isKnownDaemon(name)) throw new Error(`unknown daemon: ${name}`);
  await run('sv', ['down', name]);
  return status(name);
}

async function restart(name) {
  if (!isKnownDaemon(name)) throw new Error(`unknown daemon: ${name}`);
  await run('sv', ['restart', name]);
  return status(name);
}

module.exports = { DAEMONS, isKnownDaemon, status, up, down, restart, parseSvStatus };
