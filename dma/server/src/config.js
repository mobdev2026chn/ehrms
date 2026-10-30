// Central DMA settings — change them in dma/server/.env and restart the server.
// Agents receive these values from the server (at login and on every WebSocket connect),
// so the agent exe does not need to be rebuilt when a value changes.

function intFromEnv(name, fallback, min, max) {
  const value = parseInt(process.env[name], 10);
  if (Number.isNaN(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

// No mouse / keyboard input for this many seconds = IDLE
// (idle screenshot + idle badge + admin alert). 300 = 5 minutes.
const IDLE_THRESHOLD_SECONDS = intFromEnv('IDLE_THRESHOLD_SECONDS', 300, 30, 7200);

// DMA_MODE=lan (default): office server on the admin's PC — LAN clients only, agents trusted on the LAN.
// DMA_MODE=online: public server (e.g. track.ektahr.com behind HTTPS) — employees on any network;
//   every agent / viewer connection must carry a DMA token, and JWT_SECRET must be set.
const DMA_MODE = (process.env.DMA_MODE || 'lan').toLowerCase() === 'online' ? 'online' : 'lan';
const IS_ONLINE = DMA_MODE === 'online';

// ---- Environment: production / development (dma/environments.json) ----
// DMA_ENV=<name> in .env picks the EktaHR login service, the online server and whether the old
// DEV_HRMS database may be used - in one place. Agents and the Admin Console get the same values at
// build time (build.ps1 -Env <name>).
// Without DMA_ENV (an older .env) the server keeps its old behaviour: HRMS_API_URL / BACKEND_URL /
// ONLINE_SERVER_URL / MONGODB_URI from .env, production values otherwise.
const ENVIRONMENTS = require('../../environments.json');
const DMA_ENV = (process.env.DMA_ENV || 'production').trim().toLowerCase();
const ENV_EXPLICIT = !!process.env.DMA_ENV;
const envSettings = ENVIRONMENTS[DMA_ENV];
if (!envSettings || DMA_ENV.startsWith('_')) {
  throw new Error(`DMA_ENV=${DMA_ENV} is not defined in dma/environments.json (use ${Object.keys(ENVIRONMENTS).filter(k => !k.startsWith('_')).join(' / ')})`);
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

module.exports = { IDLE_THRESHOLD_SECONDS, DMA_MODE, IS_ONLINE, ONLINE_SERVER_URL, DMA_ENV, ENV_EXPLICIT, HRMS_API_URL, USE_DATABASE };
