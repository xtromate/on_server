'use strict';

const express = require('express');
const { loadConfig, saveConfig } = require('../config');

const router = express.Router();

// Both routes here are intentionally unauthenticated — they exist so the
// in-app Setup Wizard can pair itself with a control-api that was just
// installed headlessly (via Termux RUN_COMMAND, with no terminal visible to
// the user to read the token off of). There is no other secure channel
// available at that point. The token is exposed at most once: /claim flips
// tokenClaimed to true on first successful call and every call after that
// gets a 409 instead of the token. Both routes only ever reveal whether a
// token exists/has been claimed, never the token value itself except that
// one time.

router.get('/setup/status', (req, res) => {
  const config = loadConfig();
  res.status(200).json({
    ready: Boolean(config.token),
    claimed: Boolean(config.tokenClaimed),
  });
});

router.post('/setup/claim', (req, res) => {
  const config = loadConfig();
  if (!config.token) {
    return res.status(409).json({ ok: false, error: 'not set up yet' });
  }
  if (config.tokenClaimed) {
    return res.status(409).json({ ok: false, error: 'token already claimed' });
  }
  config.tokenClaimed = true;
  saveConfig(config);
  res.status(200).json({ ok: true, token: config.token });
});

module.exports = router;
