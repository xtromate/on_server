'use strict';

const express = require('express');
const { loadConfig, saveConfig } = require('../config');
const pm2ctl = require('../lib/pm2ctl');

const router = express.Router();

const BOT_PROCESS_NAME = 'telegram-bot';

async function currentStatus() {
  const proc = await pm2ctl.describe(BOT_PROCESS_NAME).catch(() => null);
  return proc ? proc.status : 'stopped';
}

router.get('/bots/telegram', async (req, res) => {
  try {
    const config = loadConfig();
    const status = await currentStatus();
    res.status(200).json({
      enabled: !!config.telegram.enabled,
      hasToken: !!config.telegram.token,
      status,
    });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

router.put('/bots/telegram', async (req, res) => {
  const { token, enabled } = req.body || {};

  if (enabled !== undefined && typeof enabled !== 'boolean') {
    return res.status(400).json({ ok: false, error: 'enabled must be a boolean' });
  }
  if (token !== undefined && typeof token !== 'string') {
    return res.status(400).json({ ok: false, error: 'token must be a string' });
  }

  const config = loadConfig();
  if (token !== undefined) config.telegram.token = token || null;
  if (enabled !== undefined) config.telegram.enabled = enabled;
  saveConfig(config);

  // Restart/stop the pm2-managed bot process so it picks up the new
  // token/enabled state. telegram-bot reads its token from
  // ~/.on_server/config.json at startup, so a restart is enough — no need
  // to pass the token through pm2's env.
  try {
    if (config.telegram.enabled && config.telegram.token) {
      const proc = await pm2ctl.describe(BOT_PROCESS_NAME);
      if (proc) await pm2ctl.restart(BOT_PROCESS_NAME);
      else await pm2ctl.startByName(BOT_PROCESS_NAME);
    } else {
      const proc = await pm2ctl.describe(BOT_PROCESS_NAME);
      if (proc) await pm2ctl.stop(BOT_PROCESS_NAME);
    }
  } catch (err) {
    // Config is saved either way; surface the pm2 hiccup as a soft warning
    // rather than failing the whole request (e.g. ecosystem not started yet).
    console.error(`[bots] failed to apply telegram-bot process state: ${err.message}`);
  }

  const status = await currentStatus();
  res.status(200).json({
    ok: true,
    bot: {
      enabled: !!config.telegram.enabled,
      hasToken: !!config.telegram.token,
      status,
    },
  });
});

module.exports = router;
