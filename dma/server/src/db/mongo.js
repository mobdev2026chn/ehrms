const http = require('http');
const mongoose = require('mongoose');

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
      if (id !== deviceId && dev.currentUser && dev.currentUser.trim().toLowerCase() === cleanNewUser && dev.status !== 'OFFLINE') {
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

// Dedicated MongoDB Collection 'dmalogs' in DEV_HRMS for DMA Mouse Movement, Status & Screenshots
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
        idleSeconds: data.idleSeconds !== undefined ? data.idleSeconds : 0,
        activeWindow: data.activeWindow || '',
        processName: data.processName || '',
        keystrokes: data.keystrokes || 0,
        mouseClicks: data.mouseClicks || 0,
        lastSeen: new Date(),
        updatedAt: new Date()
      }
    };

    if (data.imageBase64 || data.image) {
      const screenshotItem = {
        id: 'SS-' + Date.now() + '-' + Math.floor(Math.random() * 1000),
        timestamp: new Date(),
        imageBase64: data.imageBase64 || data.image
      };
      updateDoc.$push = {
        screenshots: {
          $each: [screenshotItem],
          $slice: -50
        }
      };
    }

    await dmaLogsCol.updateOne(filter, updateDoc, { upsert: true });
  } catch (err) {
    console.error('[Mongo dmalogs] Error logging DMA activity:', err.message);
  }
}

// In-Memory Screenshot History Store
const deviceScreenshots = new Map();

function storeScreenshot(data) {
  const deviceId = (data.deviceId || 'UNKNOWN').toUpperCase();
  const list = deviceScreenshots.get(deviceId) || [];
  const entry = {
    id: 'SS-' + Date.now() + '-' + Math.floor(Math.random() * 1000),
    deviceId,
    hostname: data.hostname || deviceId,
    currentUser: data.currentUser || 'EktaHR Employee',
    businessId: data.businessId || 'default',
    timestamp: data.timestamp || new Date().toISOString(),
    imageBase64: data.imageBase64 || data.image || ''
  };
  list.unshift(entry);
  if (list.length > 50) list.pop();
  deviceScreenshots.set(deviceId, list);

  // Async sync to dedicated MongoDB 'dmalogs' collection
  logDmaActivityToMongo(data);

  return entry;
}

async function getDeviceScreenshots(deviceId, businessId) {
  const cleanId = (deviceId || '').replace('DEV-', '').toUpperCase();
  let results = [];

  // 1. Primary Lookup from dedicated MongoDB 'dmalogs' collection
  if (mongoose.connection.readyState === 1) {
    try {
      const targetDb = mongoose.connection.useDb('DEV_HRMS');
      const dmaLogsCol = targetDb.collection('dmalogs');
      let queryFilter = {};

      if (businessId && businessId !== 'all' && businessId !== 'superadmin') {
        queryFilter.businessId = businessId;
      }

      if (cleanId && cleanId !== 'ALL') {
        queryFilter.$or = [
          { deviceId: new RegExp(cleanId, 'i') },
          { hostname: new RegExp(cleanId, 'i') },
          { currentUser: new RegExp(cleanId, 'i') }
        ];
      }

      const docs = await dmaLogsCol.find(queryFilter).toArray();
      for (const doc of docs) {
        if (Array.isArray(doc.screenshots)) {
          for (const s of doc.screenshots) {
            results.push({
              ...s,
              deviceId: doc.deviceId,
              hostname: doc.hostname,
              currentUser: doc.currentUser,
              businessId: doc.businessId
            });
          }
        }
      }
    } catch (e) {
      console.error('[Mongo dmalogs] Error fetching screenshots:', e.message);
    }
  }

  // 2. Fallback to in-memory store if DB query is empty
  if (results.length === 0) {
    for (const [k, list] of deviceScreenshots.entries()) {
      if (!cleanId || cleanId === 'ALL' || k === cleanId || k.includes(cleanId) || cleanId.includes(k)) {
        results.push(...list);
      }
    }
    if (businessId && businessId !== 'all' && businessId !== 'superadmin') {
      results = results.filter(item => item.businessId === businessId);
    }
  }

  // Sort latest first
  results.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  return results;
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

async function getDevicesList(targetBusinessId) {
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

      if (isSuperAdminAccess || matchesAdmin || !belongsToOtherAdmin) {
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

  // Filter ONLY active/online users (ONLINE, STREAMING, PAUSED, MEETING)
  const activeResults = results.filter(dev => dev.status !== 'OFFLINE' && dev.status !== 'offline');

  return activeResults;
}

module.exports = {
  connectMongo,
  registerOrUpdateDevice,
  markDeviceOffline,
  getDevicesList,
  storeScreenshot,
  getDeviceScreenshots,
  logDmaActivityToMongo,
  liveDevices
};
