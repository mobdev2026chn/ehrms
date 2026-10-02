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

module.exports = { IDLE_THRESHOLD_SECONDS };
