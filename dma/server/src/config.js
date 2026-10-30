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

// Online server that a LAN server's Admin Console also signs in to, so the admin sees employees on
// any network next to the office LAN. Set ONLINE_SERVER_URL= (empty) to keep a LAN server offline-only.
const ONLINE_SERVER_URL = IS_ONLINE
  ? ''
  : (process.env.ONLINE_SERVER_URL ?? 'https://track.ektahr.com').trim().replace(/\/$/, '');

module.exports = { IDLE_THRESHOLD_SECONDS, DMA_MODE, IS_ONLINE, ONLINE_SERVER_URL };
