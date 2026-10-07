const http = require('http');
const mongoose = require('mongoose');
const { getCompanyStaff } = require('../hrmsDirectory');

async function connectMongo() {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.log('[Mongo] No MONGODB_URI found, running with local user auth mode');
    return;
  }

  try {
    await mongoose.connect(uri);
    console.log('[Mongo] Connected successfully to EktaHR MongoDB!');
  } catch (err) {
    console.error('[Mongo] Connection error:', err.message);
    console.log('[Mongo] Falling back to local auth mode');
  }
}

// In-Memory Device Tracker for High-Speed LAN Heartbeats & Live Streaming Agents
const liveDevices = new Map();

function registerOrUpdateDevice(deviceId, data) {
  const existing = liveDevices.get(deviceId) || {};
  const newUser = (data.currentUser || data.employeeName || existing.currentUser || 'EktaHR Employee').trim();
  const cleanNewUser = newUser.toLowerCase();

  let prevDevToDisconnect = null;

  // Single Active Device per Email Restriction: If user logs in on a new device, disconnect old device
  if (cleanNewUser && cleanNewUser !== 'ektahr employee' && cleanNewUser !== 'logged out' && cleanNewUser !== '—') {
    for (const [id, dev] of liveDevices.entries()) {
      // liveDevices also holds an email-keyed alias of each device (id !== dev.deviceId) — skip it,
      // and skip this same device, so only a genuinely different PC counts as "logged in elsewhere"
      if (id === dev.deviceId && dev.deviceId !== deviceId && dev.currentUser && dev.currentUser.trim().toLowerCase() === cleanNewUser && dev.status !== 'OFFLINE') {
        dev.status = 'OFFLINE';
        dev.lastSeen = new Date();
        prevDevToDisconnect = id;
        console.log(`[SingleLogin] User ${newUser} logged in on ${deviceId}. Disconnecting previous device: ${id}`);
      }
    }
  }

  const updated = {
    deviceId,
    hostname: data.hostname || data.machineName || existing.hostname || deviceId,
    ipAddress: data.ipAddress || data.systemIp || existing.ipAddress || '127.0.0.1',
    currentUser: newUser,
    businessId: data.businessId || data.companyId || existing.businessId || 'default',
    status: data.status || existing.status || 'ONLINE',
    idleSeconds: data.idleSeconds !== undefined ? data.idleSeconds : (existing.idleSeconds || 0),
    activeWindow: data.activeWindow || existing.activeWindow || '',
    processName: data.processName || existing.processName || '',
    keystrokes: data.keystrokes || existing.keystrokes || 0,
    mouseClicks: data.mouseClicks || existing.mouseClicks || 0,
    lastSeen: new Date(),
    previousDeviceIdToDisconnect: prevDevToDisconnect
  };
  liveDevices.set(deviceId, updated);
  if (cleanNewUser && cleanNewUser !== 'ektahr employee') {
    liveDevices.set(cleanNewUser, updated);
  }

  // Sync heartbeat & mouse movement status to dedicated 'dmalogs' MongoDB collection
  logDmaActivityToMongo(updated);

  return updated;
}

function markDeviceOffline(deviceId) {
  if (liveDevices.has(deviceId)) {
    const dev = liveDevices.get(deviceId);
    dev.status = 'OFFLINE';
    dev.lastSeen = new Date();
    logDmaActivityToMongo(dev);
  }
}

// Dedicated MongoDB Collection 'dmalogs' in DEV_HRMS for live device status only.
// Screenshots and idle logs are stored on the server disk (src/storage/fileStore.js), not in MongoDB.
async function logDmaActivityToMongo(data) {
  if (mongoose.connection.readyState !== 1) return;
  try {
    const targetDb = mongoose.connection.useDb('DEV_HRMS');
    const dmaLogsCol = targetDb.collection('dmalogs');

    const deviceId = (data.deviceId || data.hostname || 'UNKNOWN').toUpperCase();
    const filter = { deviceId };

    const updateDoc = {
      $set: {
        deviceId,
        hostname: data.hostname || deviceId,
        currentUser: data.currentUser || 'EktaHR Employee',
        businessId: data.businessId || 'default',
        status: data.status || 'ONLINE',
        activeWindow: data.activeWindow || '',
        processName: data.processName || '',
        keystrokes: data.keystrokes || 0,
        mouseClicks: data.mouseClicks || 0,
        lastSeen: new Date(),
        updatedAt: new Date()
      }
    };

    await dmaLogsCol.updateOne(filter, updateDoc, { upsert: true });
  } catch (err) {
    console.error('[Mongo dmalogs] Error logging DMA activity:', err.message);
  }
}

function fetchJson(url) {
  return new Promise((resolve) => {
    http.get(url, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          resolve(null);
        }
      });
    }).on('error', () => resolve(null));
  });
}

async function getDevicesList(targetBusinessId, hrmsToken) {
  const results = [];
  const processedKeys = new Set();
  const onlineAgents = new Map();

  let resolvedAdminObjIds = [];
  let resolvedAdminStrIds = [];

  const isSuperAdminAccess = !targetBusinessId ||
    targetBusinessId === 'all' ||
    targetBusinessId === 'superadmin' ||
    targetBusinessId === 'admin-super-001' ||
    (typeof targetBusinessId === 'string' && targetBusinessId.toLowerCase().includes('super'));

  // The admin's own company id matches its live agents (their businessId is the staff's HRMS
  // adminId) with or without MongoDB - without this, a server with no database showed no PCs.
  if (!isSuperAdminAccess && targetBusinessId && targetBusinessId !== 'default') {
    resolvedAdminStrIds.push(String(targetBusinessId));
  }

  // 1. Gather all active connected streaming agents on port 9000
  for (const [id, dev] of liveDevices.entries()) {
    const cleanHost = (dev.hostname || id).toUpperCase();
    const cleanUser = (dev.currentUser || '').toLowerCase();
    onlineAgents.set(cleanHost, dev);
    onlineAgents.set(id.toUpperCase(), dev);
    if (cleanUser) onlineAgents.set(cleanUser, dev);
  }

  // 2. Query MongoDB 'admins' and 'staffs' collections in DEV_HRMS filtered by adminId
  if (mongoose.connection.readyState === 1) {
    try {
      const targetDb = mongoose.connection.useDb('DEV_HRMS');
      const adminsCol = targetDb.collection('admins');
      const staffsCol = targetDb.collection('staffs');

      if (!isSuperAdminAccess && targetBusinessId && targetBusinessId !== 'default') {
        const cleanTarget = targetBusinessId.replace('admin-user-', '').trim();

        // Find matching admin doc in 'admins' collection by email, name or _id
        let adminDoc = null;
        if (mongoose.Types.ObjectId.isValid(cleanTarget)) {
          adminDoc = await adminsCol.findOne({ _id: new mongoose.Types.ObjectId(cleanTarget) });
        }
        if (!adminDoc) {
          adminDoc = await adminsCol.findOne({
            $or: [
              { email: new RegExp(`^${cleanTarget}$`, 'i') },
              { companyAdmin: new RegExp(`^${cleanTarget}$`, 'i') }
            ]
          });
        }

        if (adminDoc) {
          resolvedAdminObjIds.push(adminDoc._id);
          resolvedAdminStrIds.push(adminDoc._id.toString());
        }

        if (mongoose.Types.ObjectId.isValid(targetBusinessId)) {
          resolvedAdminObjIds.push(new mongoose.Types.ObjectId(targetBusinessId));
        }
        resolvedAdminStrIds.push(targetBusinessId);
        resolvedAdminStrIds.push(cleanTarget);
      }

      let queryFilter = {};
      if (!isSuperAdminAccess && resolvedAdminStrIds.length > 0) {
        queryFilter = {
          $or: [
            { adminId: { $in: resolvedAdminObjIds } },
            { adminId: { $in: resolvedAdminStrIds } }
          ]
        };
      }

      const staffList = await staffsCol.find(queryFilter).toArray();

      for (const staff of staffList) {
        const staffEmail = (staff.email || '').toLowerCase();
        const fullName = `${staff.firstName || ''} ${staff.lastName || ''}`.trim() || staff.email;
        const liveDev = onlineAgents.get(staffEmail);

        results.push({
          deviceId: liveDev ? liveDev.deviceId : `DEV-${staff._id}`,
          hostname: liveDev ? liveDev.hostname : (staff.branch || 'Office PC'),
          ipAddress: liveDev ? liveDev.ipAddress : '127.0.0.1',
          currentUser: staff.email,
          fullName: fullName,
          department: staff.department || 'General',
          designation: staff.designation || 'Staff',
          businessId: staff.adminId ? staff.adminId.toString() : 'default',
          status: liveDev && liveDev.status ? liveDev.status : 'OFFLINE',
          lastSeen: liveDev ? liveDev.lastSeen : new Date()
        });

        if (staffEmail) processedKeys.add(staffEmail);
      }
    } catch (dbErr) {
      console.error('[Mongo] Error fetching staffs by adminId:', dbErr.message);
    }
  } else if (!isSuperAdminAccess && hrmsToken) {
    // No database on this server: the company's staff come from the EktaHR backend with the
    // signed-in admin's token (HRMSbackend GET /api/admin/dma/staff).
    const staffList = await getCompanyStaff(hrmsToken);
    for (const staff of staffList || []) {
      const staffEmail = (staff.email || '').toLowerCase();
      const liveDev = onlineAgents.get(staffEmail);
      results.push({
        deviceId: liveDev ? liveDev.deviceId : `DEV-${staff.id}`,
        hostname: liveDev ? liveDev.hostname : (staff.branch || 'Office PC'),
        ipAddress: liveDev ? liveDev.ipAddress : '127.0.0.1',
        currentUser: staff.email,
        fullName: staff.name || staff.email,
        department: staff.department || 'General',
        designation: staff.designation || 'Staff',
        businessId: String(targetBusinessId),
        status: liveDev && liveDev.status ? liveDev.status : 'OFFLINE',
        lastSeen: liveDev ? liveDev.lastSeen : new Date()
      });
      if (staffEmail) processedKeys.add(staffEmail);
    }
  }

  // 3. Fallback for active streaming agents
  for (const [id, dev] of liveDevices.entries()) {
    const userKey = (dev.currentUser || '').toLowerCase();
    if (!processedKeys.has(userKey)) {
      let belongsToOtherAdmin = false;
      if (!isSuperAdminAccess && mongoose.connection.readyState === 1 && userKey && userKey !== 'ektahr employee') {
        try {
          const targetDb = mongoose.connection.useDb('DEV_HRMS');
          const staffDoc = await targetDb.collection('staffs').findOne({ email: new RegExp(`^${userKey}$`, 'i') });
          if (staffDoc && staffDoc.adminId) {
            const staffAdminStr = staffDoc.adminId.toString();
            if (resolvedAdminStrIds.length > 0 && !resolvedAdminStrIds.includes(staffAdminStr)) {
              belongsToOtherAdmin = true;
            }
          }
        } catch(e) {}
      }

      const matchesAdmin = resolvedAdminStrIds.length > 0 && (
        resolvedAdminStrIds.includes(dev.businessId) ||
        resolvedAdminStrIds.includes((dev.currentUser || '').toLowerCase())
      );

      // Company admins only see live agents whose businessId (the staff's HRMS adminId) is theirs
      if (isSuperAdminAccess || (matchesAdmin && !belongsToOtherAdmin)) {
        processedKeys.add(userKey);
        results.push({
          deviceId: id,
          hostname: dev.hostname || id,
          ipAddress: dev.ipAddress || '127.0.0.1',
          currentUser: dev.currentUser || 'EktaHR Employee',
          businessId: dev.businessId || 'default',
          status: dev.status || 'ONLINE',
          lastSeen: dev.lastSeen || new Date()
        });
      }
    }
  }

  return results;
}

module.exports = {
  connectMongo,
  registerOrUpdateDevice,
  markDeviceOffline,
  getDevicesList,
  logDmaActivityToMongo,
  liveDevices
};
