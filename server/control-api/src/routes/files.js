'use strict';

const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { NAS_ROOT } = require('../config');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 500 * 1024 * 1024 } });

// Resolves a NAS-relative path (e.g. "/", "/docs/readme.txt") to an
// absolute filesystem path and verifies it never escapes NAS_ROOT. This is
// the single choke point every files.js route goes through before touching
// the filesystem — blocks ".." traversal by construction.
function resolveNasPath(reqPath) {
  const root = path.resolve(NAS_ROOT);
  const raw = (reqPath === undefined || reqPath === null || reqPath === '') ? '/' : String(reqPath);
  const posixPath = raw.replace(/\\/g, '/');
  const normalized = path.posix.normalize('/' + posixPath);
  const target = path.join(root, normalized);
  const resolved = path.resolve(target);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    const err = new Error('path escapes NAS root');
    err.status = 400;
    throw err;
  }
  return resolved;
}

function toRelative(absPath) {
  const root = path.resolve(NAS_ROOT);
  const rel = path.relative(root, absPath).split(path.sep).join('/');
  return rel ? `/${rel}` : '/';
}

function ensureNasRoot() {
  if (!fs.existsSync(NAS_ROOT)) {
    fs.mkdirSync(NAS_ROOT, { recursive: true });
  }
}

router.get('/files', (req, res) => {
  try {
    ensureNasRoot();
    const target = resolveNasPath(req.query.path);
    if (!fs.existsSync(target)) {
      return res.status(404).json({ ok: false, error: 'path not found' });
    }
    const stat = fs.statSync(target);
    if (!stat.isDirectory()) {
      return res.status(400).json({ ok: false, error: 'path is not a directory' });
    }
    const dirents = fs.readdirSync(target, { withFileTypes: true });
    const entries = dirents.map((d) => {
      const entryAbs = path.join(target, d.name);
      let entryStat;
      try {
        entryStat = fs.statSync(entryAbs);
      } catch (_) {
        entryStat = null;
      }
      return {
        name: d.name,
        path: toRelative(entryAbs),
        type: d.isDirectory() ? 'dir' : 'file',
        size: entryStat && entryStat.isFile() ? entryStat.size : 0,
        modifiedAt: entryStat ? entryStat.mtime.toISOString() : null,
      };
    });
    res.status(200).json({ path: toRelative(target), entries });
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

router.post('/files/mkdir', (req, res) => {
  try {
    ensureNasRoot();
    const { path: reqPath } = req.body || {};
    if (!reqPath) {
      return res.status(400).json({ ok: false, error: 'path is required' });
    }
    const target = resolveNasPath(reqPath);
    if (fs.existsSync(target)) {
      return res.status(409).json({ ok: false, error: 'path already exists' });
    }
    fs.mkdirSync(target, { recursive: true });
    res.status(201).json({ ok: true });
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

router.post('/files/upload', upload.single('file'), (req, res) => {
  try {
    ensureNasRoot();
    if (!req.file) {
      return res.status(400).json({ ok: false, error: 'file field is required' });
    }
    const destDir = resolveNasPath(req.query.path || '/');
    fs.mkdirSync(destDir, { recursive: true });

    // basename() strips any directory components the client might have
    // smuggled into the original filename.
    const filename = path.basename(req.file.originalname);
    if (!filename || filename === '.' || filename === '..') {
      return res.status(400).json({ ok: false, error: 'invalid filename' });
    }
    const destPath = path.resolve(path.join(destDir, filename));
    const root = path.resolve(NAS_ROOT);
    if (destPath !== root && !destPath.startsWith(root + path.sep)) {
      return res.status(400).json({ ok: false, error: 'path escapes NAS root' });
    }

    fs.writeFileSync(destPath, req.file.buffer);
    const stat = fs.statSync(destPath);
    res.status(200).json({
      ok: true,
      entry: {
        name: filename,
        path: toRelative(destPath),
        type: 'file',
        size: stat.size,
        modifiedAt: stat.mtime.toISOString(),
      },
    });
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

router.get('/files/download', (req, res) => {
  try {
    const target = resolveNasPath(req.query.path);
    if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
      return res.status(404).json({ ok: false, error: 'file not found' });
    }
    res.download(target, path.basename(target));
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

router.delete('/files', (req, res) => {
  try {
    const target = resolveNasPath(req.query.path);
    const root = path.resolve(NAS_ROOT);
    if (target === root) {
      return res.status(400).json({ ok: false, error: 'cannot delete the NAS root' });
    }
    if (!fs.existsSync(target)) {
      return res.status(404).json({ ok: false, error: 'path not found' });
    }
    fs.rmSync(target, { recursive: true, force: true });
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

module.exports = router;
