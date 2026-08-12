'use strict';

const { execFile, exec } = require('child_process');

// Small promisified execFile wrapper shared by sv.js / pm2ctl.js / git.js.
// Always uses execFile (never a shell) so arguments are never re-interpreted
// by a shell — important since names/paths here can come from user input
// that has already been validated against an allow-list/registry, but we
// still don't want shell metacharacters to matter.
function run(cmd, args = [], options = {}) {
  return new Promise((resolve, reject) => {
    execFile(
      cmd,
      args,
      {
        timeout: options.timeout || 30000,
        maxBuffer: options.maxBuffer || 5 * 1024 * 1024,
        cwd: options.cwd,
        env: options.env || process.env,
      },
      (err, stdout, stderr) => {
        if (err) {
          err.stdout = stdout;
          err.stderr = stderr;
          return reject(err);
        }
        resolve({ stdout, stderr });
      }
    );
  });
}

// Runs a compound shell command string (e.g. a user-supplied installCommand
// like "npm install" or "pip install -r requirements.txt"). Only ever used
// for commands that inherently need shell interpretation; the app's own
// startCommand is instead written into a wrapper script and never shelled
// out to directly by control-api (see apps.js) since pm2's own arg-parsing
// of compound commands is unreliable.
function runShell(cmd, options = {}) {
  return new Promise((resolve, reject) => {
    exec(
      cmd,
      {
        timeout: options.timeout || 180000,
        maxBuffer: options.maxBuffer || 5 * 1024 * 1024,
        cwd: options.cwd,
        env: options.env || process.env,
      },
      (err, stdout, stderr) => {
        if (err) {
          err.stdout = stdout;
          err.stderr = stderr;
          return reject(err);
        }
        resolve({ stdout, stderr });
      }
    );
  });
}

module.exports = { run, runShell };
