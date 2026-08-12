'use strict';

const { loadConfig } = require('./config');

// Bearer-token middleware for every /api/* route except /api/health.
// Token is generated once by scripts/setup-services.sh and stored in
// ~/.on_server/config.json.
function requireAuth(req, res, next) {
  const config = loadConfig();
  const header = req.headers['authorization'] || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  const token = match ? match[1].trim() : null;

  if (!config.token || !token || token !== config.token) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }

  next();
}

module.exports = { requireAuth };
