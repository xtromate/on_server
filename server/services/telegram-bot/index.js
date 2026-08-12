'use strict';

const TelegramBot = require('node-telegram-bot-api');
// Reuses control-api's own config reader (plain JSON files, no native
// deps) so both processes agree on where ~/.on_server/config.json lives.
const { loadConfig } = require('../../control-api/src/config');

const HELP_TEXT = ['On-Server bot commands:', '', '/status - service + metrics summary', '/help - this message'].join(
  '\n'
);

function resolveControlApiBase(config) {
  const port = process.env.CONTROL_API_PORT || config.port || 8420;
  // Always talk to control-api over localhost — the bot runs on the same
  // phone/pm2 instance as control-api, so it never needs the tailnet path.
  return `http://127.0.0.1:${port}`;
}

async function callControlApi(base, apiPath, apiToken) {
  const res = await fetch(`${base}${apiPath}`, {
    headers: { Authorization: `Bearer ${apiToken}` },
  });
  if (!res.ok) {
    throw new Error(`${apiPath} returned HTTP ${res.status}`);
  }
  return res.json();
}

function statusEmoji(status) {
  if (status === 'running') return '\u{1F7E2}'; // green circle
  if (status === 'stopped') return '⚪'; // white circle
  return '\u{1F7E1}'; // yellow circle
}

function formatBytes(kb) {
  if (kb === null || kb === undefined) return 'n/a';
  return `${Math.round(kb / 1024)}MB`;
}

async function buildStatusSummary(base, apiToken) {
  const [servicesRes, metricsRes] = await Promise.all([
    callControlApi(base, '/api/services', apiToken),
    callControlApi(base, '/api/metrics', apiToken),
  ]);

  const lines = ['On-Server status', ''];

  lines.push('Services:');
  for (const s of servicesRes.services) {
    lines.push(`${statusEmoji(s.status)} ${s.name} (${s.kind}) - ${s.status}`);
  }

  lines.push('');
  const { cpu, mem, disk, battery } = metricsRes;
  if (cpu) {
    lines.push(`Load avg: ${cpu.load1}, ${cpu.load5}, ${cpu.load15}`);
  }
  if (mem && mem.totalKb) {
    const pct = Math.round((mem.usedKb / mem.totalKb) * 100);
    lines.push(`Memory: ${pct}% used (${formatBytes(mem.usedKb)} / ${formatBytes(mem.totalKb)})`);
  }
  if (disk && disk.totalKb) {
    const pct = Math.round((disk.usedKb / disk.totalKb) * 100);
    lines.push(`Disk: ${pct}% used (${disk.mountPath})`);
  }
  if (battery) {
    lines.push(`Battery: ${battery.percentage}% (${battery.status})`);
  } else {
    lines.push('Battery: unavailable (termux-api not installed?)');
  }

  return lines.join('\n');
}

function startBot(token, apiToken) {
  const config = loadConfig();
  const base = resolveControlApiBase(config);
  const bot = new TelegramBot(token, { polling: true });

  bot.onText(/^\/help/, (msg) => {
    bot.sendMessage(msg.chat.id, HELP_TEXT);
  });

  bot.onText(/^\/status/, async (msg) => {
    try {
      const summary = await buildStatusSummary(base, apiToken);
      bot.sendMessage(msg.chat.id, summary);
    } catch (err) {
      bot.sendMessage(msg.chat.id, `Could not reach control-api: ${err.message}`);
    }
  });

  bot.on('polling_error', (err) => {
    console.error(`[telegram-bot] polling error: ${err.message}`);
  });

  console.log('[telegram-bot] polling started');
  return bot;
}

// Resolves the bot token: normally read from ~/.on_server/config.json
// (set via PUT /api/bots/telegram from the Flutter app), with an optional
// TELEGRAM_BOT_TOKEN env override for local development against a throwaway
// bot without touching control-api's config — see .env.example.
function resolveToken(config) {
  if (config.telegram.enabled && config.telegram.token) return config.telegram.token;
  if (process.env.TELEGRAM_BOT_TOKEN) return process.env.TELEGRAM_BOT_TOKEN;
  return null;
}

function main() {
  const config = loadConfig();
  const token = resolveToken(config);

  if (!token) {
    console.log(
      '[telegram-bot] no token configured (or bot disabled) in ~/.on_server/config.json — idling. ' +
        'Set one via PUT /api/bots/telegram from the app; this process will be restarted automatically.'
    );
    // Keep the event loop alive (and pm2 happy) instead of crash-looping
    // while waiting to be restarted once a token is configured.
    setInterval(() => {}, 60 * 60 * 1000);
    return;
  }

  if (!config.token) {
    console.warn(
      '[telegram-bot] warning: control-api has no auth token yet in ~/.on_server/config.json ' +
        '(run scripts/setup-services.sh) — /status will fail until it does.'
    );
  }

  startBot(token, config.token || process.env.CONTROL_API_TOKEN || '');
}

main();
