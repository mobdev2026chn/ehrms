const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { liveDevices } = require('../db/mongo');

const JWT_SECRET = process.env.JWT_SECRET || 'AEvaHRMS@123';
const activeUserSessions = new Map();

function postJson(urlStr, payloadData) {
  return new Promise((resolve) => {
    try {
      const url = new URL(urlStr);
      const transport = url.protocol === 'https:' ? require('https') : require('http');
      const postData = JSON.stringify(payloadData);
      
      const req = transport.request({
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        },
        timeout: 5000
      }, res => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            resolve({ statusCode: res.statusCode, data: JSON.parse(body) });
          } catch (e) {
            resolve(null);
          }
        });
      });

      req.on('error', () => resolve(null));
      req.on('timeout', () => { req.destroy(); resolve(null); });
      req.write(postData);
      req.end();
    } catch (e) {
      resolve(null);
    }
  });
}

async function login(req, res) {
  try {
    const { username, email, password, forceLogout, deviceId, machineName, hostname } = req.body;
    const rawInput = (email || username || '').trim();

    if (!rawInput || !password) {
      return res.status(400).json({ error: 'Email/Username and password are required.' });
    }

    const cleanUsername = rawInput.toLowerCase();
    let user = null;
    let isMatch = false;

    // 1. PRIMARY AUTHENTICATION: Hosted HRMS API (https://uat.ektahr.com)
    try {
      const backendUrl = (process.env.BACKEND_URL || 'https://uat.ektahr.com').replace(/\/$/, '');
      const loginEndpoints = [
        `${backendUrl}/api/v1/auth/login`,
        `${backendUrl}/api/auth/login`,
        `${backendUrl}/auth/login`
      ];

      for (const endpoint of loginEndpoints) {
        if (isMatch) break;
        const apiResp = await postJson(endpoint, { email: cleanUsername, username: cleanUsername, password: password });
        if (apiResp && apiResp.data && (apiResp.data.token || apiResp.data.user || apiResp.data.success === true || apiResp.data.data)) {
          const apiUser = apiResp.data.user || apiResp.data.data || {};
          user = {
            _id: apiUser._id || apiUser.id || cleanUsername,
            username: apiUser.email || apiUser.username || cleanUsername,
            name: `${apiUser.firstName || ''} ${apiUser.lastName || ''}`.trim() || apiUser.name || apiUser.email || 'EktaHR User',
            password: password,
            role: apiUser.role || 'SUPER_ADMIN',
            businessId: apiUser.companyId ? apiUser.companyId.toString() : (apiUser.businessId ? apiUser.businessId.toString() : (apiUser.adminId ? apiUser.adminId.toString() : (apiUser._id ? apiUser._id.toString() : 'default')))
          };
          isMatch = true;
          console.log(`[Hosted Auth] Successfully authenticated ${cleanUsername} via hosted endpoint: ${endpoint}`);
          break;
        }
      }
    } catch (apiErr) {
      console.warn('[Hosted Auth] Hosted API check error:', apiErr.message);
    }

    // 2. SECONDARY AUTHENTICATION: Connected MongoDB 'users', 'admins', 'staffs', or 'companies' collections
    if (!isMatch && mongoose.connection.readyState === 1) {
      try {
        const dbsToSearch = [];
        if (mongoose.connection.db) dbsToSearch.push(mongoose.connection.db);
        try { dbsToSearch.push(mongoose.connection.useDb('DEV_HRMS')); } catch (e) {}
        try { dbsToSearch.push(mongoose.connection.useDb('hrms-development')); } catch (e) {}

        for (const dbObj of dbsToSearch) {
          if (user) break;

          // Check 'users' collection (Main HRMS Users / Admins)
          const usersCol = dbObj.collection('users');
          const userDoc = await usersCol.findOne({
            $or: [
              { email: new RegExp(`^${cleanUsername}$`, 'i') },
              { username: new RegExp(`^${cleanUsername}$`, 'i') }
            ]
          });

          if (userDoc) {
            user = {
              _id: userDoc._id,
              username: userDoc.email || userDoc.username || cleanUsername,
              name: userDoc.name || userDoc.fullName || userDoc.username || 'EktaHR User',
              password: userDoc.password || userDoc.password_hash || userDoc.passwordHash || '',
              role: (userDoc.role || '').toUpperCase().includes('ADMIN') ? 'SUPER_ADMIN' : (userDoc.role || 'SUPER_ADMIN'),
              businessId: userDoc.companyId ? userDoc.companyId.toString() : (userDoc._id ? userDoc._id.toString() : 'default')
            };
            break;
          }

          // Check 'admins' collection (Company Admins)
          const adminsCol = dbObj.collection('admins');
          const adminDoc = await adminsCol.findOne({
            $or: [
              { email: new RegExp(`^${cleanUsername}$`, 'i') },
              { companyAdmin: new RegExp(`^${cleanUsername}$`, 'i') }
            ]
          });

          if (adminDoc) {
            user = {
              _id: adminDoc._id,
              username: adminDoc.email || cleanUsername,
              name: adminDoc.name || adminDoc.companyAdmin || 'Company Admin',
              password: adminDoc.password || adminDoc.password_hash || adminDoc.passwordHash || '',
              role: 'SUPER_ADMIN',
              businessId: adminDoc._id.toString()
            };
            break;
          }

          // Check 'staffs' collection (Employees / Agents)
          const staffCol = dbObj.collection('staffs');
          const staffDoc = await staffCol.findOne({
            email: new RegExp(`^${cleanUsername}$`, 'i')
          });

          if (staffDoc) {
            const fullName = `${staffDoc.firstName || ''} ${staffDoc.lastName || ''}`.trim() || staffDoc.name || staffDoc.email;
            user = {
              _id: staffDoc._id,
              username: staffDoc.email,
              name: fullName,
              password: staffDoc.password || staffDoc.password_hash || staffDoc.passwordHash || '',
              role: staffDoc.role || 'AGENT',
              businessId: staffDoc.adminId ? staffDoc.adminId.toString() : (staffDoc.companyId ? staffDoc.companyId.toString() : 'default')
            };
            break;
          }

          // Check 'companies' collection
          const companiesCol = dbObj.collection('companies');
          const companyDoc = await companiesCol.findOne({
            $or: [
              { email: new RegExp(`^${cleanUsername}$`, 'i') },
              { companyEmail: new RegExp(`^${cleanUsername}$`, 'i') }
            ]
          });

          if (companyDoc) {
            user = {
              _id: companyDoc._id,
              username: companyDoc.email || companyDoc.companyEmail || cleanUsername,
              name: companyDoc.companyName || companyDoc.name || 'Company Admin',
              password: companyDoc.password || companyDoc.password_hash || companyDoc.passwordHash || '',
              role: 'SUPER_ADMIN',
              businessId: companyDoc._id.toString()
            };
            break;
          }
        }
      } catch (dbErr) {
        console.error('[Auth] DB lookup error:', dbErr.message);
      }

      if (user && user.password && !isMatch) {
        try {
          isMatch = bcrypt.compareSync(password, user.password);
        } catch (e) {}

        if (!isMatch && user.password === password) {
          isMatch = true;
        }
      }
    }

    // 4. Master Admin & Employee Fallback
    if (!isMatch && (cleanUsername === 'hp@gmail.com' || cleanUsername === 'akash@gmail.com') && (password === 'User@123' || password === 'Akash@123')) {
      user = {
        _id: '67b489a2f1c8e23400a123bc',
        username: cleanUsername,
        name: cleanUsername.split('@')[0],
        password: password,
        role: 'AGENT',
        businessId: '6a82956a3f37c860e0d526db'
      };
      isMatch = true;
    }
    if (!isMatch && (cleanUsername === 'akash.askeva@gmail.com' || cleanUsername === 'admin@ektahr.com' || cleanUsername === 'admin') && (password === 'Akash@123' || password === 'User@123')) {
      user = {
        _id: 'admin-super-001',
        username: cleanUsername,
        name: 'Akash (Super Admin)',
        password: password,
        role: 'SUPER_ADMIN',
        businessId: 'admin-super-001'
      };
      isMatch = true;
    }

    if (!user || !isMatch) {
      return res.status(401).json({ error: 'Invalid EktaHR login credentials.' });
    }

    const userIdStr = (user._id || cleanUsername).toString();
    const reqDeviceId = (deviceId || machineName || hostname || '').trim().toUpperCase();

    // 4. Single-Login Enforcement:
    // If login is from DIFFERENT system with SAME user -> BLOCK IT!
    // If login is from SAME system or Localhost -> ALLOW IT & REFRESH THE SESSION!
    const clientIp = (req.ip || '').replace('::ffff:', '');
    const isLocalMachine = clientIp === '127.0.0.1' || clientIp === '::1' || clientIp === 'localhost';

    let activeDevHost = null;
    if (!isLocalMachine && liveDevices && reqDeviceId) {
      for (const [id, dev] of liveDevices.entries()) {
        const cleanDevId = id.toUpperCase();
        const cleanHost = (dev.hostname || '').toUpperCase();
        if (
          dev.currentUser &&
          dev.currentUser.trim().toLowerCase() === cleanUsername &&
          dev.status !== 'OFFLINE' &&
          cleanDevId !== reqDeviceId &&
          cleanHost !== reqDeviceId
        ) {
          activeDevHost = dev.hostname || dev.deviceId || id;
          break;
        }
      }
    }

    if (!forceLogout && !isLocalMachine && activeDevHost) {
      console.warn(`[Auth] Blocked login from different system for ${cleanUsername} - active on ${activeDevHost}`);
      return res.status(403).json({
        error: `Login Blocked: User ${cleanUsername} is already logged in on another device (${activeDevHost}). Multiple logins across different devices are restricted.`,
        isAlreadyLoggedIn: true
      });
    }

    // 5. Generate new JWT token (Including businessId for strict multi-tenant isolation)
    const token = jwt.sign(
      {
        userId: userIdStr,
        username: user.username,
        businessId: user.businessId || userIdStr,
        role: user.role || 'SUPER_ADMIN'
      },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    // Track active session with deviceId
    activeUserSessions.set(userIdStr, {
      token,
      loginTime: new Date(),
      ip: req.ip,
      deviceId: reqDeviceId
    });

    console.log(`[Auth] EktaHR Login SUCCESS for: ${user.username} (BusinessId: ${user.businessId}) on device: ${reqDeviceId || 'Same System'}`);

    res.json({
      message: 'EktaHR Login Successful',
      token,
      user: {
        userId: userIdStr,
        username: user.username,
        email: user.username,
        fullName: user.fullName || user.name || 'EktaHR Admin',
        businessId: user.businessId || userIdStr,
        role: user.role || 'SUPER_ADMIN'
      }
    });
  } catch (err) {
    console.error('[Auth] Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function logout(req, res) {
  try {
    const userId = req.user ? req.user.userId : null;
    if (userId && activeUserSessions.has(userId)) {
      activeUserSessions.delete(userId);
      console.log(`[Auth] Cleared active session for user: ${userId}`);
    }
    res.json({ message: 'Logged out successfully' });
  } catch (err) {
    res.status(500).json({ error: 'Logout error' });
  }
}

function verifyTokenMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized. No token provided.' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    if (!req.user.businessId) {
      req.user.businessId = req.user.userId || req.user.username;
    }
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Unauthorized. Invalid or expired EktaHR token.' });
  }
}

module.exports = { login, logout, verifyTokenMiddleware, JWT_SECRET };
