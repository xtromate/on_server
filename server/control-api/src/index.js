'use strict';

const express = require('express');
const { loadConfig, ensureStateDir } = require('./config');
const { requireAuth } = require('./auth');

const healthRoute = require('./routes/health');
const servicesRoute = require('./routes/services');
const appsRoute = require('./routes/apps');
const filesRoute = require('./routes/files');
const metricsRoute = require('./routes/metrics');
const botsRoute = require('./routes/bots');
const demoRoute = require('./routes/demo');

ensureStateDir();
const config = loadConfig();

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '2mb' }));

// Permissive CORS so a Flutter-web build (or any browser-based client) can
// hit this from a different origin; native/mobile Flutter clients ignore
// this entirely. Not part of the API contract itself, just a convenience.
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// GET /api/health is the only unauthenticated route — mounted before the
// auth gate below so it never hits requireAuth.
app.use('/api', healthRoute);

app.use('/api', requireAuth);

app.use('/api', servicesRoute);
app.use('/api', appsRoute);
app.use('/api', filesRoute);
app.use('/api', metricsRoute);
app.use('/api', botsRoute);
app.use('/api', demoRoute);

app.use('/api', (req, res) => {
  res.status(404).json({ ok: false, error: 'not found' });
});

// Fallback error handler — anything an individual route forgot to catch
// still comes back as the standard { ok:false, error } shape instead of an
// HTML stack trace.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({ ok: false, error: err.message || 'internal error' });
});

const port = process.env.PORT ? Number(process.env.PORT) : config.port || 8420;
const host = config.host || '0.0.0.0';

app.listen(port, host, () => {
  console.log(`[control-api] listening on http://${host}:${port}`);
  if (!config.token) {
    console.warn('[control-api] no auth token set yet in ~/.on_server/config.json — run scripts/setup-services.sh');
  }
});
