const fs = require('fs');
const path = require('path');
const { STORAGE_DIR, safeSegment, isSuperScope } = require('./storage/fileStore');

// Personal websites / apps the agent paints over in screenshots and live view / remote access, before
// the image leaves the employee's PC: a browser window whose title contains one of these words, or an
// app whose name does. One list per company; a super admin edits the default that every company
// without its own list uses.
//   <DMA_STORAGE_DIR>/privacy-sites/<businessId>.json   { sites, updatedAt, updatedBy }
//   <DMA_STORAGE_DIR>/privacy-sites/_default.json
const DIR = path.join(STORAGE_DIR, 'privacy-sites');

// Same list as PrivacyMask.DefaultSites in the agent (used there until a server sends one)
const BUILT_IN_SITES = [
  'WhatsApp', 'Facebook', 'Instagram', 'Messenger', 'Telegram', 'Snapchat',
  'YouTube', 'Netflix', 'Prime Video', 'Hotstar', 'JioCinema', 'Spotify',
  'Gmail', 'Yahoo Mail', 'NetBanking', 'Net Banking', 'Internet Banking', 'Online Banking'
];
const MAX_SITES = 100;
const MAX_LENGTH = 40;
// The agent reads a WebSocket message of up to 8 KB in one go: keep the list well under that
const MAX_TOTAL_BYTES = 4000;

function fileFor(businessId) {
  return path.join(DIR, `${isSuperScope(businessId) ? '_default' : safeSegment(businessId)}.json`);
}

function readList(file) {
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    return data && Array.isArray(data.sites) ? data : null;
  } catch (e) {
    return null;
  }
}

// The agent gets the list as one '|'-separated string and its JSON reader stops at , " } - so none of
// those (nor \ { or control characters) may be in a word. Duplicates (any case) are dropped.
function cleanSites(sites) {
  const seen = new Set();
  const clean = [];
  let bytes = 0;
  for (const raw of Array.isArray(sites) ? sites : []) {
    const word = String(raw || '').replace(/[|,"\\{}\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, MAX_LENGTH).trim();
    const key = word.toLowerCase();
    if (word.length < 2 || seen.has(key)) continue;
    bytes += Buffer.byteLength(word) + 1;
    if (clean.length >= MAX_SITES || bytes > MAX_TOTAL_BYTES) break;
    seen.add(key);
    clean.push(word);
  }
  return clean;
}

// -> { sites, source: 'company' | 'default' | 'built-in', updatedAt, updatedBy }
function getPrivacySites(businessId) {
  const own = !isSuperScope(businessId) && readList(fileFor(businessId));
  if (own) return { sites: own.sites, source: 'company', updatedAt: own.updatedAt || null, updatedBy: own.updatedBy || null };
  const def = readList(fileFor('superadmin'));
  if (def) return { sites: def.sites, source: 'default', updatedAt: def.updatedAt || null, updatedBy: def.updatedBy || null };
  return { sites: BUILT_IN_SITES, source: 'built-in', updatedAt: null, updatedBy: null };
}

function savePrivacySites(businessId, sites, updatedBy) {
  fs.mkdirSync(DIR, { recursive: true });
  const entry = { sites: cleanSites(sites), updatedAt: new Date().toISOString(), updatedBy: updatedBy || null };
  fs.writeFileSync(fileFor(businessId), JSON.stringify(entry, null, 2));
  return getPrivacySites(businessId);
}

// Back to the default list (a company) or the built-in one (super admin)
function resetPrivacySites(businessId) {
  try { fs.rmSync(fileFor(businessId), { force: true }); } catch (e) {}
  return getPrivacySites(businessId);
}

module.exports = { BUILT_IN_SITES, getPrivacySites, savePrivacySites, resetPrivacySites };
