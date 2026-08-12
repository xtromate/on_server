'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

// All of control-api's own state lives under ~/.on_server as plain JSON files.
// Deliberately avoids native modules (e.g. better-sqlite3) since Termux's
// node-gyp toolchain is unreliable — see docs/SETUP.md.
const HOME = os.homedir();
const STATE_DIR = path.join(HOME, '.on_server');
const CONFIG_PATH = path.join(STATE_DIR, 'config.json');
const APPS_PATH = path.join(STATE_DIR, 'apps.json');

// Where user-deployed backends get cloned into.
const APPS_ROOT = path.join(HOME, 'on_server', 'apps');

// NAS root, created by scripts/install.sh via termux-setup-storage.
const NAS_ROOT = path.join(HOME, 'storage', 'shared', 'OnServerNAS');

const DEFAULT_CONFIG = {
  port: 8420,
  host: '0.0.0.0',
  publicHost: null, // if set, used instead of the request's Host header for app URLs
  token: null,
  // True once the freshly-generated token has been fetched exactly once via
  // POST /api/setup/claim (used by the in-app Setup Wizard to pair itself
  // with a headless install with no other secure channel available). See
  // routes/setup.js.
  tokenClaimed: false,
  telegram: {
    enabled: false,
    token: null,
  },
};

function ensureStateDir() {
  if (!fs.existsSync(STATE_DIR)) {
    fs.mkdirSync(STATE_DIR, { recursive: true });
  }
}

function readJsonSafe(filePath, fallback) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    if (err.code === 'ENOENT') return fallback;
    // Corrupt file — don't crash the whole server, fall back but keep the
    // broken file on disk for inspection.
    console.error(`[config] failed to parse ${filePath}: ${err.message}`);
    return fallback;
  }
}

function writeJsonSafe(filePath, data) {
  ensureStateDir();
  const tmpPath = `${filePath}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function loadConfig() {
  ensureStateDir();
  const existing = readJsonSafe(CONFIG_PATH, null);
  if (!existing) {
    writeJsonSafe(CONFIG_PATH, DEFAULT_CONFIG);
    return { ...DEFAULT_CONFIG };
  }
  // Merge with defaults so newly-added fields don't crash older config files.
  return {
    ...DEFAULT_CONFIG,
    ...existing,
    telegram: { ...DEFAULT_CONFIG.telegram, ...(existing.telegram || {}) },
  };
}

function saveConfig(config) {
  writeJsonSafe(CONFIG_PATH, config);
  return config;
}

function loadApps() {
  const apps = readJsonSafe(APPS_PATH, []);
  return Array.isArray(apps) ? apps : [];
}

function saveApps(apps) {
  writeJsonSafe(APPS_PATH, apps);
  return apps;
}

module.exports = {
  HOME,
  STATE_DIR,
  CONFIG_PATH,
  APPS_PATH,
  APPS_ROOT,
  NAS_ROOT,
  DEFAULT_CONFIG,
  ensureStateDir,
  loadConfig,
  saveConfig,
  loadApps,
  saveApps,
};
