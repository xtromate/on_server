'use strict';

const { run } = require('./exec');

// Clones repoUrl into dest (which must not already exist). Uses execFile
// (no shell), so repoUrl/branch are never re-interpreted by a shell even
// though they come from user input.
async function clone({ repoUrl, branch, dest }) {
  const args = ['clone'];
  if (branch) args.push('--branch', branch, '--single-branch');
  args.push(repoUrl, dest);
  await run('git', args, { timeout: 120000 });
}

// git pull inside an already-cloned app directory.
async function pull({ dest, branch }) {
  const args = ['pull', 'origin'];
  if (branch) args.push(branch);
  await run('git', args, { cwd: dest, timeout: 120000 });
}

module.exports = { clone, pull };
