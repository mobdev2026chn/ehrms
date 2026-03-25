/**
 * Enable with: LOG_TRACKINGS=1 or LOG_TRACKINGS=true in .env
 * Disable with: LOG_TRACKINGS=0
 */
function shouldLogTrackings() {
  const v = String(process.env.LOG_TRACKINGS || '').toLowerCase();
  if (v === '0' || v === 'false' || v === 'off') return false;
  return v === '1' || v === 'true' || v === 'on' || v === 'yes';
}

function logTrackingWrite(source, payload) {
  if (!shouldLogTrackings()) return;
  const line = {
    ts: new Date().toISOString(),
    source,
    ...payload,
  };
  console.log('[Trackings]', JSON.stringify(line));
}

module.exports = { shouldLogTrackings, logTrackingWrite };
