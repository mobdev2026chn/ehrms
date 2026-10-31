// Admin Console auto-update.
//
// The office server inside the Admin Console is unpacked to %LOCALAPPDATA%\EktaHR DMA\server-<version>.
// It updates itself from the online server: when "adminConsoleVersion" in the online server's
// dma.config.json is higher than its own, it downloads the new server code, web console and agent
// (only files that changed), sets them up next to itself as server-<new version> - reusing its own
// Node, npm packages and .env - and restarts into it. The Admin Console exe starts the newest
// installed version from then on.
//
// The online server hands these files out straight from its git checkout, so publishing a new Admin
// Console = raise adminConsoleVersion in dma.config.json, build, push, git pull.
// A version that needs different npm packages cannot update this way (the new Admin Console exe is
// installed by hand once).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const http = require('http');
const https = require('https');
const { spawn } = require('child_process');
const { IS_ONLINE, ONLINE_SERVER_URL } = require('./config');
const { STORAGE_DIR } = require('./storage/fileStore');
const { compareVersions } = require('./agentUpdate');

// The repo's "dma" folder (online server, development) or the unpacked server-<version> folder
const DMA_ROOT = path.resolve(__dirname, '../..');
const PACKAGE_DIRS = ['server/src', 'admin_console/dist'];
const PACKAGE_FILES = ['server/package.json', 'agent/publish/EktaHR-Agent.exe', 'dma.config.json'];
const VERSION_RE = /^\d+(\.\d+){1,3}$/;
const CHECK_EVERY_MS = 30 * 60 * 1000;

// Version of this installed office server, from its folder name; null when run from the repo (the
// online server / development) - those are updated with git pull instead
const folderMatch = /^server-(\d+(\.\d+){1,3})$/.exec(path.basename(DMA_ROOT));
const INSTALLED_VERSION = folderMatch ? folderMatch[1] : null;
const CAN_SELF_UPDATE = !IS_ONLINE && !!INSTALLED_VERSION && !!ONLINE_SERVER_URL;

const SETTINGS_FILE = path.join(STORAGE_DIR, 'admin-console-settings.json');
const state = { latestVersion: null, checkedAt: null, error: null, updating: false, updatingTo: null };

// adminConsoleVersion this server hands out (read fresh, so a git pull counts without a restart)
function publishedVersion() {
  try { return JSON.parse(fs.readFileSync(path.join(DMA_ROOT, 'dma.config.json'), 'utf8')).adminConsoleVersion || null; }
  catch (e) { return null; }
}

function currentVersion() {
  return INSTALLED_VERSION || publishedVersion();
}

function readSettings() {
  try { return { autoUpdate: true, ...JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')) }; }
  catch (e) { return { autoUpdate: true }; }
}

function writeSettings(changes) {
  const settings = { ...readSettings(), ...changes };
  fs.mkdirSync(path.dirname(SETTINGS_FILE), { recursive: true });
  fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
  return settings;
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

// ---- Online server side: the files of the current Admin Console release ----------------------

function walk(rel, out) {
  for (const entry of fs.readdirSync(path.join(DMA_ROOT, rel), { withFileTypes: true })) {
    const childRel = `${rel}/${entry.name}`;
    if (entry.isDirectory()) walk(childRel, out);
    else if (entry.isFile()) out.push(childRel);
  }
}

let manifestCache = { key: '', manifest: null };

// { version, files: [{ path, size, sha256 }] } - only the package folders/files, never .env etc.
function getManifest() {
  const files = [];
  for (const dir of PACKAGE_DIRS) if (fs.existsSync(path.join(DMA_ROOT, dir))) walk(dir, files);
  for (const file of PACKAGE_FILES) if (fs.existsSync(path.join(DMA_ROOT, file))) files.push(file);
  const stats = files.map(f => fs.statSync(path.join(DMA_ROOT, f)));
  const version = publishedVersion();
  const key = version + '|' + files.map((f, i) => `${f}:${stats[i].size}:${stats[i].mtimeMs}`).join(',');
  if (manifestCache.key !== key) {
    manifestCache = {
      key,
      manifest: {
        version,
        files: files.map((f, i) => ({ path: f, size: stats[i].size, sha256: sha256(fs.readFileSync(path.join(DMA_ROOT, f))) }))
      }
    };
  }
  return manifestCache.manifest;
}

// Absolute path of a release file, or null when it is not part of the release
function resolvePackageFile(rel) {
  return getManifest().files.some(f => f.path === rel) ? path.join(DMA_ROOT, rel) : null;
}

// ---- Office server side: check, download, switch -----------------------------------------------

function fetchBuffer(url, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    const req = (url.startsWith('https:') ? https : http).get(url, { timeout: timeoutMs }, res => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`${url} answered HTTP ${res.statusCode}`)); }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    req.on('timeout', () => req.destroy(new Error(`${url} timed out`)));
    req.on('error', reject);
  });
}

async function fetchJson(url) {
  return JSON.parse((await fetchBuffer(url, 15000)).toString('utf8'));
}

// Newest Admin Console version on the online server (also remembered for the Settings page)
async function checkLatest() {
  try {
    const latest = await fetchJson(`${ONLINE_SERVER_URL}/api/v1/admin-console/latest`);
    state.latestVersion = VERSION_RE.test(latest.version || '') ? latest.version : null;
    state.checkedAt = new Date();
    state.error = null;
  } catch (e) {
    state.error = `Could not check for updates: ${e.message}`;
  }
  return state.latestVersion;
}

const isNewer = (v) => !!v && !!INSTALLED_VERSION && compareVersions(v, INSTALLED_VERSION) > 0;

// Release paths are relative and stay inside the folder
const safeRel = (rel) => /^[\w.\-/]+$/.test(rel) && !rel.split('/').includes('..');

function sortedDeps(pkg) {
  const deps = (pkg && pkg.dependencies) || {};
  return JSON.stringify(Object.keys(deps).sort().map(k => [k, deps[k]]));
}

// Downloads the newer version next to this one and restarts into it. Resolves after the files are in
// place (this process then exits); rejects with a message for the Settings page.
async function installUpdate() {
  if (!CAN_SELF_UPDATE) throw new Error('This server is not an installed Admin Console - update it with git pull.');
  if (state.updating) return { updating: true, version: state.updatingTo };
  state.updating = true;
  try {
    const manifest = await fetchJson(`${ONLINE_SERVER_URL}/api/v1/admin-console/manifest`);
    if (!isNewer(manifest.version)) {
      state.updating = false;
      return { updated: false, version: INSTALLED_VERSION };
    }
    const version = manifest.version;
    state.updatingTo = version;
    const download = async (f) => {
      if (!safeRel(f.path)) throw new Error(`Unexpected file in the update: ${f.path}`);
      const buf = await fetchBuffer(`${ONLINE_SERVER_URL}/api/v1/admin-console/file?path=${encodeURIComponent(f.path)}`);
      if (buf.length !== f.size || sha256(buf) !== f.sha256) throw new Error(`Download check failed for ${f.path} - try again`);
      return buf;
    };

    // Node and npm packages are reused, so the new version must need the same packages
    const pkgFile = manifest.files.find(f => f.path === 'server/package.json');
    const newPkgBuf = await download(pkgFile);
    const ownPkg = JSON.parse(fs.readFileSync(path.join(DMA_ROOT, 'server', 'package.json'), 'utf8'));
    if (sortedDeps(JSON.parse(newPkgBuf.toString('utf8'))) !== sortedDeps(ownPkg)) {
      throw new Error(`Admin Console ${version} needs new server packages - install the new EktaHR-AdminConsole.exe by hand once.`);
    }

    const target = path.join(path.dirname(DMA_ROOT), `server-${version}`);
    if (!fs.existsSync(path.join(target, 'ready.ok'))) {
      const partial = `${target}.partial`;
      fs.rmSync(partial, { recursive: true, force: true });
      for (const f of manifest.files) {
        const dest = path.join(partial, ...f.path.split('/'));
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        const own = path.join(DMA_ROOT, ...f.path.split('/'));
        if (fs.existsSync(own) && fs.statSync(own).size === f.size && sha256(fs.readFileSync(own)) === f.sha256) {
          fs.copyFileSync(own, dest); // unchanged
        } else {
          fs.writeFileSync(dest, f === pkgFile ? newPkgBuf : await download(f));
        }
      }
      // Reused from this install: Node, npm packages, settings (.env)
      fs.cpSync(path.join(DMA_ROOT, 'node'), path.join(partial, 'node'), { recursive: true });
      fs.cpSync(path.join(DMA_ROOT, 'server', 'node_modules'), path.join(partial, 'server', 'node_modules'), { recursive: true });
      fs.copyFileSync(path.join(DMA_ROOT, 'server', '.env'), path.join(partial, 'server', '.env'));
      fs.rmSync(target, { recursive: true, force: true });
      fs.renameSync(partial, target);
      fs.writeFileSync(path.join(target, 'ready.ok'), new Date().toISOString());
    }
    restartInto(target, version);
    return { updating: true, version };
  } catch (e) {
    state.updating = false;
    state.updatingTo = null;
    state.error = e.message;
    throw e;
  }
}

// Starts the new version with the same settings the Admin Console gave this one (PORT, LAN_ONLY,
// DMA_STORAGE_DIR) and the same log file, then exits; the new server takes over the port.
function restartInto(target, version) {
  const logFile = path.join(path.dirname(DMA_ROOT), 'logs', 'dma-server.log');
  fs.mkdirSync(path.dirname(logFile), { recursive: true });
  const out = fs.openSync(logFile, 'a');
  const child = spawn(path.join(target, 'node', 'node.exe'), ['src/index.js'], {
    cwd: path.join(target, 'server'),
    env: process.env,
    detached: true,
    stdio: ['ignore', out, out],
    windowsHide: true
  });
  child.unref();
  console.log(`[Update] Admin Console ${version} installed - restarting into it`);
  setTimeout(() => process.exit(0), 500);
}

// Older versions are removed once the new one runs (the one before it is kept)
function removeOldVersions() {
  if (!INSTALLED_VERSION) return;
  try {
    const parent = path.dirname(DMA_ROOT);
    const older = fs.readdirSync(parent)
      .map(name => ({ name, m: /^server-(\d+(\.\d+){1,3})(\.partial)?$/.exec(name) }))
      .filter(x => x.m && (x.m[3] || compareVersions(x.m[1], INSTALLED_VERSION) < 0))
      .sort((a, b) => compareVersions(b.m[1], a.m[1]));
    const keep = older.find(x => !x.m[3]);
    for (const x of older) {
      if (x === keep) continue;
      fs.rmSync(path.join(parent, x.name), { recursive: true, force: true });
      console.log(`[Update] Removed old Admin Console ${x.name}`);
    }
  } catch (e) {
    console.warn('[Update] Could not remove old versions:', e.message);
  }
}

// Auto update: check at start and every 30 minutes; install when on and nobody is watching a screen
function startAutoUpdate(hasActiveViewers) {
  if (!CAN_SELF_UPDATE) return;
  setTimeout(removeOldVersions, 60 * 1000);
  const tick = async () => {
    const latest = await checkLatest();
    if (!isNewer(latest) || !readSettings().autoUpdate) return;
    if (hasActiveViewers()) {
      console.log(`[Update] Admin Console ${latest} available - waiting until no screen is being viewed`);
      setTimeout(tick, 5 * 60 * 1000);
      return;
    }
    installUpdate().catch(e => console.warn('[Update] Admin Console update failed:', e.message));
  };
  setTimeout(tick, 15 * 1000);
  setInterval(tick, CHECK_EVERY_MS);
}

function getStatus() {
  return {
    version: currentVersion(),
    installed: !!INSTALLED_VERSION,
    canSelfUpdate: CAN_SELF_UPDATE,
    autoUpdate: readSettings().autoUpdate,
    latestVersion: state.latestVersion,
    updateAvailable: isNewer(state.latestVersion),
    checkedAt: state.checkedAt,
    updating: state.updating,
    updatingTo: state.updatingTo,
    error: state.error
  };
}

module.exports = {
  publishedVersion, getManifest, resolvePackageFile,
  checkLatest, installUpdate, startAutoUpdate, getStatus, writeSettings, CAN_SELF_UPDATE
};
