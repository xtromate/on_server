'use strict';

const express = require('express');
const path = require('path');
const { STATE_DIR, ensureStateDir } = require('../config');

const router = express.Router();

// Proves the SQLite part of the stack works without any native compilation
// (Termux's node-gyp toolchain is unreliable) by using Node's built-in
// node:sqlite module, available from Node 22.5+ behind no flag (and earlier
// 22.x behind --experimental-sqlite). If it's unavailable on whatever Node
// version ended up installed, this returns a clear 501 instead of crashing
// anything else in control-api.
router.get('/demo/sqlite', (req, res) => {
  let DatabaseSync;
  try {
    ({ DatabaseSync } = require('node:sqlite'));
  } catch (err) {
    return res.status(501).json({
      ok: false,
      error:
        'node:sqlite is not available on this Node.js build (requires Node 22.5+). ' +
        'Upgrade Node in Termux (pkg upgrade nodejs) to enable this demo route.',
    });
  }

  try {
    ensureStateDir();
    const dbPath = path.join(STATE_DIR, 'demo.sqlite');
    const db = new DatabaseSync(dbPath);
    try {
      db.exec(`
        CREATE TABLE IF NOT EXISTS pings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL
        )
      `);
      const insert = db.prepare('INSERT INTO pings (created_at) VALUES (?)');
      insert.run(new Date().toISOString());

      const rows = db.prepare('SELECT id, created_at FROM pings ORDER BY id DESC LIMIT 10').all();
      const count = db.prepare('SELECT COUNT(*) AS c FROM pings').get();

      res.status(200).json({ ok: true, totalPings: count.c, recent: rows });
    } finally {
      db.close();
    }
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

module.exports = router;
