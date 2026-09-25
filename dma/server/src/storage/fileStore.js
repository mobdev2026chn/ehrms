const fs = require('fs');
const path = require('path');

// All DMA monitoring data (screenshots, idle logs) is kept on the server's disk — not in MongoDB.
// Layout:
//   <DMA_STORAGE_DIR>/screenshots/<businessId>/<deviceId>/<yyyy-mm-dd>/<HHmmss-ms>.jpg
//   <DMA_STORAGE_DIR>/screenshots/<businessId>/<deviceId>/<yyyy-mm-dd>/index.jsonl   (one line per screenshot)
//   <DMA_STORAGE_DIR>/idle-logs/<businessId>/<yyyy-mm-dd>.jsonl                       (one line per idle period)
const STORAGE_DIR = path.resolve(process.env.DMA_STORAGE_DIR || path.join(__dirname, '../../storage'));
const SCREENSHOT_DIR = path.join(STORAGE_DIR, 'screenshots');
const IDLE_DIR = path.join(STORAGE_DIR, 'idle-logs');
const TIMEZONE = process.env.DMA_TIMEZONE || 'Asia/Kolkata';

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
fs.mkdirSync(IDLE_DIR, { recursive: true });

// Folder-safe id: blocks path traversal from client-supplied deviceId / businessId
function safeSegment(value, fallback = 'unknown') {
  const clean = String(value || '').trim().replace(/[^A-Za-z0-9_.@-]/g, '_').replace(/^\.+/, '');
  return clean.slice(0, 120) || fallback;
}

// yyyy-mm-dd in the office timezone
function dayKey(date = new Date()) {
  return new Date(date).toLocaleDateString('en-CA', { timeZone: TIMEZONE });
}

function timeKey(date = new Date()) {
  const t = new Date(date).toLocaleTimeString('en-GB', { timeZone: TIMEZONE, hour12: false }).replace(/:/g, '');
  return `${t}-${String(new Date(date).getMilliseconds()).padStart(3, '0')}`;
}

function listDirs(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name);
  } catch (e) {
    return [];
  }
}

function readJsonl(file) {
  try {
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map(line => {
      try { return JSON.parse(line); } catch (e) { return null; }
    }).filter(Boolean);
  } catch (e) {
    return [];
  }
}

// ================= SCREENSHOTS =================

// Saves a JPEG (base64 data URL or raw base64 / Buffer) to disk and returns its metadata
async function saveScreenshot({ deviceId, hostname, currentUser, businessId, timestamp, idleSeconds, image }) {
  let buffer = Buffer.isBuffer(image) ? image : null;
  if (!buffer) {
    const base64 = String(image || '').replace(/^data:image\/\w+;base64,/, '');
    buffer = Buffer.from(base64, 'base64');
  }
  if (buffer.length < 4 || buffer[0] !== 0xFF || buffer[1] !== 0xD8) {
    throw new Error('Screenshot is not a valid JPEG image');
  }

  const takenAt = timestamp ? new Date(timestamp) : new Date();
  const when = Number.isNaN(takenAt.getTime()) ? new Date() : takenAt;
  const biz = safeSegment(businessId, 'default');
  const dev = safeSegment((deviceId || hostname || '').toUpperCase(), 'UNKNOWN');
  const day = dayKey(when);
  const dir = path.join(SCREENSHOT_DIR, biz, dev, day);
  const file = `${timeKey(when)}.jpg`;

  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.writeFile(path.join(dir, file), buffer);

  const entry = {
    id: `${day}_${file.replace('.jpg', '')}`,
    file,
    deviceId: dev,
    hostname: hostname || dev,
    currentUser: currentUser || 'EktaHR Employee',
    businessId: biz,
    timestamp: when.toISOString(),
    idleSeconds: Number(idleSeconds) || 0,
    sizeKB: Math.round(buffer.length / 1024),
    imageUrl: `/api/v1/screenshots/file/${encodeURIComponent(biz)}/${encodeURIComponent(dev)}/${day}/${file}`
  };
  await fs.promises.appendFile(path.join(dir, 'index.jsonl'), JSON.stringify(entry) + '\n');
  return entry;
}

function isSuperScope(businessId) {
  return !businessId || businessId === 'all' || businessId === 'superadmin' || businessId === 'admin-super-001';
}

// Newest-first screenshots for a device, scoped to the admin's business
function listScreenshots({ deviceId, businessId, days = 7, limit = 200 }) {
  const cleanId = String(deviceId || '').replace(/^DEV-/, '').toUpperCase();
  const businesses = isSuperScope(businessId) ? listDirs(SCREENSHOT_DIR) : [safeSegment(businessId)];
  const results = [];

  for (const biz of businesses) {
    const bizDir = path.join(SCREENSHOT_DIR, biz);
    for (const dev of listDirs(bizDir)) {
      if (cleanId && cleanId !== 'ALL' && dev !== safeSegment(cleanId)) continue;
      const dayDirs = listDirs(path.join(bizDir, dev)).sort().reverse().slice(0, Math.max(1, Number(days) || 7));
      for (const day of dayDirs) {
        results.push(...readJsonl(path.join(bizDir, dev, day, 'index.jsonl')));
      }
    }
  }

  results.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  return results.slice(0, Math.min(Number(limit) || 200, 2000));
}

// Absolute path of a screenshot file, or null if the request is outside the admin's business
function resolveScreenshotFile({ businessId, fileBusinessId, deviceId, day, file }) {
  const biz = safeSegment(fileBusinessId);
  if (!isSuperScope(businessId) && biz !== safeSegment(businessId)) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !/^[\d-]+\.jpg$/.test(file)) return null;

  const full = path.join(SCREENSHOT_DIR, biz, safeSegment(deviceId), day, file);
  if (!full.startsWith(SCREENSHOT_DIR + path.sep) || !fs.existsSync(full)) return null;
  return full;
}

// Deletes screenshot day-folders older than SCREENSHOT_RETENTION_DAYS (default 30)
function cleanupOldScreenshots() {
  const retentionDays = Number(process.env.SCREENSHOT_RETENTION_DAYS || 30);
  if (!(retentionDays > 0)) return;
  const cutoff = dayKey(new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000));
  let removed = 0;

  for (const biz of listDirs(SCREENSHOT_DIR)) {
    for (const dev of listDirs(path.join(SCREENSHOT_DIR, biz))) {
      for (const day of listDirs(path.join(SCREENSHOT_DIR, biz, dev))) {
        if (day < cutoff) {
          fs.rmSync(path.join(SCREENSHOT_DIR, biz, dev, day), { recursive: true, force: true });
          removed++;
        }
      }
    }
  }
  if (removed) console.log(`[Storage] Removed ${removed} screenshot day-folder(s) older than ${retentionDays} days`);
}

function startRetentionJob() {
  try { cleanupOldScreenshots(); } catch (e) { console.error('[Storage] Cleanup error:', e.message); }
  setInterval(() => {
    try { cleanupOldScreenshots(); } catch (e) { console.error('[Storage] Cleanup error:', e.message); }
  }, 6 * 60 * 60 * 1000).unref();
}

// ================= IDLE LOGS =================

async function appendIdleLog(entry) {
  const biz = safeSegment(entry.businessId, 'default');
  const dir = path.join(IDLE_DIR, biz);
  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.appendFile(path.join(dir, `${dayKey(entry.startAt)}.jsonl`), JSON.stringify({ ...entry, businessId: biz }) + '\n');
}

// Idle periods whose start day falls within [fromDay, toDay] (yyyy-mm-dd, inclusive)
function readIdleLogs({ businessId, fromDay, toDay }) {
  const businesses = isSuperScope(businessId) ? listDirs(IDLE_DIR) : [safeSegment(businessId)];
  const results = [];
  for (const biz of businesses) {
    let files = [];
    try { files = fs.readdirSync(path.join(IDLE_DIR, biz)).filter(f => f.endsWith('.jsonl')); } catch (e) {}
    for (const f of files) {
      const day = f.replace('.jsonl', '');
      if ((fromDay && day < fromDay) || (toDay && day > toDay)) continue;
      results.push(...readJsonl(path.join(IDLE_DIR, biz, f)));
    }
  }
  return results;
}

// Open idle periods are checkpointed so a server restart can still close them
const OPEN_IDLE_FILE = path.join(IDLE_DIR, '_open_periods.json');

function saveOpenIdlePeriods(openMap) {
  try {
    fs.writeFileSync(OPEN_IDLE_FILE, JSON.stringify(Object.fromEntries(openMap)));
  } catch (e) {
    console.error('[Storage] Failed to checkpoint open idle periods:', e.message);
  }
}

function loadOpenIdlePeriods() {
  try {
    return JSON.parse(fs.readFileSync(OPEN_IDLE_FILE, 'utf8')) || {};
  } catch (e) {
    return {};
  }
}

module.exports = {
  STORAGE_DIR,
  isSuperScope,
  dayKey,
  saveScreenshot,
  listScreenshots,
  resolveScreenshotFile,
  startRetentionJob,
  appendIdleLog,
  readIdleLogs,
  saveOpenIdlePeriods,
  loadOpenIdlePeriods
};
