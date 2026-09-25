const jwt = require('jsonwebtoken');
const { liveDevices } = require('../db/mongo');

const JWT_SECRET = process.env.JWT_SECRET || 'AEvaHRMS@123';
const activeUserSessions = new Map();

// EktaHR HRMS backend (HRMSbackend) — single source of truth for Admin / Staff credentials.
// Contract: POST {HRMS_API_URL}/api/auth/login { email, password }
//   -> 200 { success, token, user: { id, email, name, role: 'superAdmin'|'admin'|'staff'|'candidate', adminId, ... } }
//   -> 401 / 403 / 404 { success: false, message }
const HRMS_API_URL = (process.env.HRMS_API_URL || process.env.BACKEND_URL || 'https://uat.ektahr.com').replace(/\/$/, '');
const HRMS_LOGIN_ENDPOINT = `${HRMS_API_URL}/api/auth/login`;

// HRMS role -> DMA role
const ROLE_MAP = {
  superAdmin: 'SUPER_ADMIN',
  admin: 'ADMIN',
  staff: 'STAFF'
};
const ADMIN_ROLES = ['SUPER_ADMIN', 'ADMIN'];

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
        timeout: 8000
      }, res => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            resolve({ statusCode: res.statusCode, data: JSON.parse(body) });
          } catch (e) {
            resolve({ statusCode: res.statusCode, data: null });
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

// Verifies credentials against the HRMS backend and maps the account to a DMA identity
async function authenticateWithHrms(email, password) {
  const apiResp = await postJson(HRMS_LOGIN_ENDPOINT, { email, password });

  if (!apiResp) {
    return { ok: false, status: 503, error: 'Unable to reach the EktaHR login service. Please try again.' };
  }

  const data = apiResp.data || {};
  if (data.requiresOtp) {
    return { ok: false, status: 403, error: 'OTP login is enabled for this account and is not supported by the DMA yet.' };
  }
  if (apiResp.statusCode !== 200 || !data.success || !data.user) {
    const status = [401, 403, 404].includes(apiResp.statusCode) ? apiResp.statusCode : 401;
    return { ok: false, status, error: data.message || 'Invalid EktaHR login credentials.' };
  }

  const hrmsUser = data.user;
  const role = ROLE_MAP[hrmsUser.role];
  if (!role) {
    return { ok: false, status: 403, error: 'This account type cannot sign in to EktaHR DMA.' };
  }

  // Company scope: an admin IS the company; staff belong to their admin's company; super admins see all
  let businessId;
  if (role === 'SUPER_ADMIN') businessId = 'superadmin';
  else if (role === 'ADMIN') businessId = hrmsUser.id;
  else businessId = hrmsUser.adminId;

  if (!businessId) {
    return { ok: false, status: 403, error: 'This account is not linked to a company in EktaHR.' };
  }

  return {
    ok: true,
    user: {
      userId: hrmsUser.id,
      username: (hrmsUser.email || email).toLowerCase(),
      fullName: hrmsUser.name || `${hrmsUser.firstName || ''} ${hrmsUser.lastName || ''}`.trim() || hrmsUser.email,
      employeeId: hrmsUser.employeeId,
      hrmsRole: hrmsUser.role,
      role,
      businessId: businessId.toString()
    }
  };
}

// Mounted on two routes:
//   /api/v1/auth/login    -> Admin Console: company admins and super admins only
//   /api/device/register  -> Desktop Agent: staff and admins
async function login(req, res) {
  try {
    const { username, email, password, forceLogout, deviceId, machineName, hostname } = req.body;
    const rawInput = (email || username || '').trim();

    if (!rawInput || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }

    const cleanUsername = rawInput.toLowerCase();
    const isAgentLogin = req.path.includes('/device/');

    const auth = await authenticateWithHrms(cleanUsername, password);
    if (!auth.ok) {
      console.warn(`[Auth] HRMS login rejected for ${cleanUsername}: ${auth.error}`);
      return res.status(auth.status).json({ error: auth.error });
    }
    const user = auth.user;

    if (!isAgentLogin && !ADMIN_ROLES.includes(user.role)) {
      return res.status(403).json({ error: 'Only company admins can sign in to the EktaHR DMA Admin Console.' });
    }
    if (isAgentLogin && user.role === 'SUPER_ADMIN') {
      return res.status(403).json({ error: 'Super admin accounts cannot sign in to the desktop agent. Use a staff or company admin login.' });
    }

    const reqDeviceId = (deviceId || machineName || hostname || '').trim().toUpperCase();

    // Single-Login Enforcement:
    // If login is from DIFFERENT system with SAME user -> BLOCK IT!
    // If login is from SAME system or Localhost -> ALLOW IT & REFRESH THE SESSION!
    const clientIp = (req.socket.remoteAddress || '').replace('::ffff:', '');
    const isLocalMachine = clientIp === '127.0.0.1' || clientIp === '::1' || clientIp === 'localhost';

    let activeDevHost = null;
    if (isAgentLogin && !isLocalMachine && liveDevices && reqDeviceId) {
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

    // DMA session token (businessId gives strict multi-tenant isolation)
    const token = jwt.sign(
      {
        userId: user.userId,
        username: user.username,
        businessId: user.businessId,
        role: user.role,
        hrmsRole: user.hrmsRole
      },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    activeUserSessions.set(user.userId, {
      token,
      loginTime: new Date(),
      ip: clientIp,
      deviceId: reqDeviceId
    });

    console.log(`[Auth] HRMS login SUCCESS: ${user.username} (${user.hrmsRole}, BusinessId: ${user.businessId})${isAgentLogin ? ` on device ${reqDeviceId || 'unknown'}` : ' [Admin Console]'}`);

    res.json({
      message: 'EktaHR Login Successful',
      token,
      user: {
        userId: user.userId,
        username: user.username,
        email: user.username,
        fullName: user.fullName,
        employeeId: user.employeeId,
        businessId: user.businessId,
        role: user.role,
        hrmsRole: user.hrmsRole
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

// Use after verifyTokenMiddleware on Admin Console endpoints (staff agent tokens are rejected)
function requireAdminRole(req, res, next) {
  if (req.user && ADMIN_ROLES.includes(req.user.role)) return next();
  return res.status(403).json({ error: 'Admin access required.' });
}

module.exports = { login, logout, verifyTokenMiddleware, requireAdminRole, JWT_SECRET };
