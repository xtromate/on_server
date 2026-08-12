'use strict';

const path = require('path');

// pm2 process list for the two always-on Node services (control-api itself
// and the telegram bot). Both are plain `node <entry>` scripts, so unlike
// user-deployed Apps they don't need the wrapper-script trick — pm2 handles
// simple script paths like these fine.
//
// NOTE: script paths are kept relative to each app's own `cwd` (rather than
// relative to this file, e.g. "../services/telegram-bot/index.js") because
// pm2's script-vs-cwd path resolution has historically been inconsistent
// between CLI and programmatic starts. Using an absolute `cwd` + a bare
// "index.js"/"src/index.js" script name sidesteps that ambiguity entirely.
//
// Start with: pm2 start ecosystem.config.js && pm2 save
module.exports = {
  apps: [
    {
      name: 'control-api',
      script: 'src/index.js',
      cwd: __dirname,
      env: {
        NODE_ENV: 'production',
      },
    },
    {
      name: 'telegram-bot',
      script: 'index.js',
      cwd: path.join(__dirname, '..', 'services', 'telegram-bot'),
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
