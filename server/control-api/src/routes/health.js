'use strict';

const express = require('express');

const router = express.Router();

// No auth — used by the Flutter app's "test connection" and by anyone
// verifying the server is up at all.
router.get('/health', (req, res) => {
  res.status(200).json({ ok: true, time: Date.now() });
});

module.exports = router;
