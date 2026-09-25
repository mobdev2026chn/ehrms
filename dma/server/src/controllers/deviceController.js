const { getDevicesList, storeScreenshot, getDeviceScreenshots, liveDevices } = require('../db/mongo');
const { getConnectedAgents } = require('../ws/signalingServer');

const NOT_LOGGED_IN_USERS = ['', 'ektahr employee', 'logged out', '—'];

// LAN scan: PCs whose agent is connected to this server right now AND has an employee logged in,
// scoped to the admin's business
async function getLanAgents(req, res) {
  try {
    const businessId = req.user?.businessId;
    const devices = await getDevicesList(businessId);
    const connected = getConnectedAgents();
    const seen = new Set();

    const agents = [];
    for (const d of devices) {
      const live = connected.get(d.deviceId);
      const user = (d.currentUser || '').trim().toLowerCase();
      const status = (d.status || '').toUpperCase();
      if (!live || seen.has(d.deviceId)) continue;
      if (NOT_LOGGED_IN_USERS.includes(user) || status === 'LOGGED_OUT' || status === 'OFFLINE') continue;

      seen.add(d.deviceId);
      const liveInfo = liveDevices.get(d.deviceId) || {};
      agents.push({
        ...d,
        hostname: live.hostname || d.hostname,
        ipAddress: live.ipAddress || d.ipAddress,
        idleSeconds: liveInfo.idleSeconds || 0,
        activeWindow: liveInfo.activeWindow || '',
        connected: true,
        connectedAt: live.connectedAt
      });
    }

    res.json({ success: true, scannedAt: new Date(), agents });
  } catch (err) {
    console.error('[LAN Scan] Error listing connected agents:', err);
    res.status(500).json({ success: false, error: 'Failed to scan LAN agents' });
  }
}

async function getAllDevices(req, res) {
  try {
    const businessId = req.user?.businessId || req.query.businessId;
    const devices = await getDevicesList(businessId);
    res.json({ success: true, devices });
  } catch (err) {
    console.error('[Device] Error fetching devices:', err);
    res.status(500).json({ error: 'Failed to fetch devices' });
  }
}

async function postScreenshot(req, res) {
  try {
    const data = req.body || {};
    if (!data.imageBase64 && !data.image) {
      return res.status(400).json({ success: false, error: 'Missing imageBase64 in payload' });
    }
    console.log('[Screenshot] Received upload for device:', data.deviceId || data.hostname, 'Length:', (data.imageBase64 || '').length);
    const saved = storeScreenshot(data);
    res.json({ success: true, screenshot: saved });
  } catch (err) {
    console.error('[Device] Error storing screenshot:', err);
    res.status(500).json({ success: false, error: 'Failed to store screenshot' });
  }
}

async function getScreenshots(req, res) {
  try {
    const deviceId = req.params.deviceId || req.query.deviceId;
    const businessId = req.user?.businessId || req.query.businessId;
    const screenshots = await getDeviceScreenshots(deviceId, businessId);
    res.json({ success: true, screenshots });
  } catch (err) {
    console.error('[Device] Error fetching screenshots:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch screenshots' });
  }
}

async function downloadAgent(req, res) {
  try {
    const path = require('path');
    const fs = require('fs');
    const agentPath = path.join(__dirname, '../../../agent/publish/EktaHR-Agent.exe');
    if (fs.existsSync(agentPath)) {
      return res.download(agentPath, 'EktaHR-Agent.exe');
    }
    res.status(404).json({ error: 'Agent binary not found' });
  } catch (err) {
    res.status(500).json({ error: 'Download failed' });
  }
}

module.exports = { getAllDevices, getLanAgents, postScreenshot, getScreenshots, downloadAgent };
