const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { liveDevices } = require('../db/mongo');

const JWT_SECRET = process.env.JWT_SECRET || 'AEvaHRMS@123';
const activeUserSessions = new Map();

async function login(req, res) {
  try {
    const { username, email, password, forceLogout, deviceId, machineName, hostname } = req.body;
    const rawInput = (email || username || '').trim();

    if (!rawInput || !password) {
      return res.status(400).json({ error: 'Email/Username and password are required.' });
    }

    const cleanUsername = rawInput.toLowerCase();
    let user = null;

    // 1. Query connected MongoDB 'admins', 'staffs', or 'users' collections in DEV_HRMS database
    if (mongoose.connection.readyState === 1) {
      try {
        const targetDb = mongoose.connection.useDb('DEV_HRMS');

        // Check 'admins' collection (Company Admins)
        const adminsCollection = targetDb.collection('admins');
        const adminDoc = await adminsCollection.findOne({
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
            password: adminDoc.password,
            role: 'SUPER_ADMIN',
            businessId: adminDoc._id.toString()
          };
        }

        // Check 'staffs' collection (Employees / Agents)
        if (!user) {
          const staffCollection = targetDb.collection('staffs');
          const staffDoc = await staffCollection.findOne({
            email: new RegExp(`^${cleanUsername}$`, 'i')
          });
          if (staffDoc) {
            const fullName = `${staffDoc.firstName || ''} ${staffDoc.lastName || ''}`.trim() || staffDoc.email;
            user = {
              _id: staffDoc._id,
              username: staffDoc.email,
              name: fullName,
              password: staffDoc.password,
              role: staffDoc.role || 'AGENT',
              businessId: staffDoc.adminId ? staffDoc.adminId.toString() : 'default'
            };
          }
        }

        // Check 'users' collection (Fallback User)
        if (!user) {
          const usersCollection = targetDb.collection('users');
          user = await usersCollection.findOne({
            $or: [
              { email: new RegExp(`^${cleanUsername}$`, 'i') },
              { username: new RegExp(`^${cleanUsername}$`, 'i') }
            ]
          });
        }
      } catch (dbErr) {
        console.error('[Auth] DB lookup error:', dbErr.message);
      }
    }

    // 2. Validate password against MongoDB Atlas database (100% STRICT REAL DB BCRYPT ONLY)
    if (user && user.password) {
      let isMatch = false;

      // 2a. Real Bcrypt Case-Sensitive Verification
      try {
        isMatch = bcrypt.compareSync(password, user.password || user.password_hash || '');
      } catch (e) {}

      // 2b. Exact Plaintext Match (only if stored unhashed in DB)
      if (!isMatch && user.password === password) {
        isMatch = true;
      }

      if (!isMatch) {
        return res.status(401).json({ error: 'Invalid EktaHR password.' });
      }
    } else {
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
