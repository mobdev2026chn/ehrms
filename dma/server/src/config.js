// Central DMA settings — dma/dma.config.json (pushed with the code) and dma/server/.env (per server,
// overrides the config file); restart the server after a change.
// Agents receive these values from the server (at login and on every WebSocket connect),
// so the agent exe does not need to be rebuilt when a value changes.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const DMA_CONFIG = require('../../dma.config.json');

function intFromEnv(name, fallback, min, max) {
  const value = parseInt(process.env[name], 10);
  if (Number.isNaN(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

// No mouse / keyboard input for this many seconds = IDLE
// (idle screenshot + idle badge + admin alert). 300 = 5 minutes.
const IDLE_THRESHOLD_SECONDS = intFromEnv('IDLE_THRESHOLD_SECONDS', 300, 30, 7200);

// lan: office server on the admin's PC — LAN clients only, agents trusted on the LAN.
// online: public server (track.ektahr.com behind HTTPS) — employees on any network; every agent /
//   viewer connection must carry a DMA token.
// DMA_MODE in .env when set (the office server inside the Admin Console always sets lan), otherwise
// "serverMode" in dma/dma.config.json - the mode of the server run from this repo, i.e. the online server.
const DMA_MODE = (process.env.DMA_MODE || DMA_CONFIG.serverMode || 'lan').toLowerCase() === 'online' ? 'online' : 'lan';
const IS_ONLINE = DMA_MODE === 'online';
const MODE_SOURCE = process.env.DMA_MODE ? '.env (DMA_MODE)' : DMA_CONFIG.serverMode ? 'dma.config.json' : 'default';

// Token secret. The old public default would let anyone forge an admin token on the internet, so the
// online server never uses it: without its own JWT_SECRET in .env it creates a random one once and
// keeps it in its storage folder (survives restarts and git pulls; a new one signs everyone in again).
const DEFAULT_JWT_SECRET = 'AEvaHRMS@123';
function resolveJwtSecret() {
  const fromEnv = process.env.JWT_SECRET;
  if (fromEnv && fromEnv !== DEFAULT_JWT_SECRET) return { secret: fromEnv, source: '.env' };
  if (!IS_ONLINE) return { secret: fromEnv || DEFAULT_JWT_SECRET, source: 'default (office LAN server)' };
  const file = path.join(path.resolve(process.env.DMA_STORAGE_DIR || path.join(__dirname, '../storage')), '.jwt-secret');
  try {
    const saved = fs.readFileSync(file, 'utf8').trim();
    if (saved.length >= 32) return { secret: saved, source: file };
  } catch (e) {}
  const secret = crypto.randomBytes(48).toString('hex');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, secret, { mode: 0o600 });
  return { secret, source: `${file} (created)` };
}
const { secret: JWT_SECRET, source: JWT_SECRET_SOURCE } = resolveJwtSecret();

// ---- Environment: production / development (dma/dma.config.json) ----
// The environment picks the EktaHR login service, the online server and whether the old DEV_HRMS
// database may be used - in one place. It is DMA_ENV in .env when set (pins this server), otherwise
// "environment" in dma/dma.config.json (changes with a push + git pull). The agent and Admin Console
// get the same values at build time (build.ps1).
// Neither set (very old setup): HRMS_API_URL / BACKEND_URL / ONLINE_SERVER_URL / MONGODB_URI from .env.
const ENVIRONMENTS = DMA_CONFIG.environments || {};
const ENV_SOURCE = process.env.DMA_ENV ? '.env (DMA_ENV)' : DMA_CONFIG.environment ? 'dma.config.json' : 'default';
const DMA_ENV = (process.env.DMA_ENV || DMA_CONFIG.environment || 'production').trim().toLowerCase();
const ENV_EXPLICIT = ENV_SOURCE !== 'default';
const envSettings = ENVIRONMENTS[DMA_ENV];
if (!envSettings) {
  throw new Error(`Environment "${DMA_ENV}" (from ${ENV_SOURCE}) is not defined in dma/dma.config.json (use ${Object.keys(ENVIRONMENTS).join(' / ')})`);
}
const trimUrl = (u) => String(u || '').trim().replace(/\/$/, '');

// EktaHR login service (POST {HRMS_API_URL}/api/auth/login) and staff directory
const HRMS_API_URL = ENV_EXPLICIT
  ? trimUrl(envSettings.hrmsApiUrl)
  : trimUrl(process.env.HRMS_API_URL || process.env.BACKEND_URL || envSettings.hrmsApiUrl);

// MONGODB_URI (old DEV_HRMS database) is only used where the environment allows it - never in production
const USE_DATABASE = ENV_EXPLICIT ? !!envSettings.useDatabase : true;

// Online server that a LAN server's Admin Console also signs in to, so the admin sees employees on
// any network next to the office LAN. Empty = the office server stays offline-only.
const ONLINE_SERVER_URL = IS_ONLINE
  ? ''
  : ENV_EXPLICIT
    ? trimUrl(envSettings.onlineServerUrl)
    : trimUrl(process.env.ONLINE_SERVER_URL ?? envSettings.onlineServerUrl);

module.exports = {
  IDLE_THRESHOLD_SECONDS, DMA_MODE, IS_ONLINE, MODE_SOURCE, ONLINE_SERVER_URL, DMA_ENV, ENV_EXPLICIT, ENV_SOURCE,
  HRMS_API_URL, USE_DATABASE, JWT_SECRET, JWT_SECRET_SOURCE
};
