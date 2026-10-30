// Agent auto-update.
// The newest agent is the exe this server hands out at /api/v1/download/agent
// (dma/agent/publish/EktaHR-Agent.exe). Its version is the "EKTA-AGENT-VERSION:x.y.z" tag compiled
// into it (AgentVersion in AgentSingle.cs), so publishing a newer exe is all a release needs.
// Connected agents that report a lower version are offered it; they download it, check it and
// install it when nobody is working in them (next start, logout or exit).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const AGENT_EXE = path.join(__dirname, '../../agent/publish/EktaHR-Agent.exe');
const VERSION_TAG = Buffer.from('EKTA-AGENT-VERSION:', 'utf16le'); // .NET string literals are UTF-16
const VERSION_RE = /^\d+(\.\d+){1,3}$/;

let cached = { key: '', info: null };

function readVersionTag(buf) {
  // The bare prefix also appears in the exe (the agent searches for it), so take the tagged one
  for (let i = buf.indexOf(VERSION_TAG); i >= 0; i = buf.indexOf(VERSION_TAG, i + 1)) {
    let version = '';
    for (let j = i + VERSION_TAG.length; j + 1 < buf.length; j += 2) {
      const c = buf.readUInt16LE(j);
      if ((c >= 48 && c <= 57) || c === 46) version += String.fromCharCode(c);
      else break;
    }
    if (VERSION_RE.test(version)) return version;
  }
  return null;
}

// { version, sha256, size } of the published agent, or null (no exe, or a build without a version tag)
function getPublishedAgent() {
  try {
    const st = fs.statSync(AGENT_EXE);
    const key = `${st.size}:${st.mtimeMs}`;
    if (key !== cached.key) {
      const buf = fs.readFileSync(AGENT_EXE);
      const version = readVersionTag(buf);
      cached = {
        key,
        info: version ? { version, sha256: crypto.createHash('sha256').update(buf).digest('hex'), size: buf.length } : null
      };
    }
    return cached.info;
  } catch (e) {
    return null;
  }
}

function compareVersions(a, b) {
  const pa = String(a).split('.').map(Number);
  const pb = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d > 0 ? 1 : -1;
  }
  return 0;
}

// The update message for an agent at `agentVersion`, or null. Agents that report no version are
// builds from before auto-update: they cannot install it this way and are updated by hand once.
// Never offers an older agent (an office server built earlier than the online server).
function updateOfferFor(agentVersion) {
  if (!agentVersion || !VERSION_RE.test(agentVersion)) return null;
  const latest = getPublishedAgent();
  if (!latest || compareVersions(latest.version, agentVersion) <= 0) return null;
  return { type: 'AGENT_UPDATE_AVAILABLE', version: latest.version, sha256: latest.sha256, size: latest.size };
}

module.exports = { AGENT_EXE, getPublishedAgent, updateOfferFor, compareVersions };
