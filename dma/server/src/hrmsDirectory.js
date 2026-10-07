// Company staff directory read from the EktaHR backend (HRMSbackend GET /api/admin/dma/staff)
// with the signed-in admin's own EktaHR token.
//
// Used when this DMA server has no MongoDB connection (the normal case for a server started
// by the Admin Console on an admin's PC): no database credentials are needed on that PC.

const HRMS_API_URL = (process.env.HRMS_API_URL || process.env.BACKEND_URL || 'https://uat.ektahr.com').replace(/\/$/, '');
const CACHE_MS = 60 * 1000;
const cache = new Map(); // hrmsToken -> { at, staff }

function getJson(urlStr, token) {
  return new Promise((resolve) => {
    try {
      const url = new URL(urlStr);
      const transport = url.protocol === 'https:' ? require('https') : require('http');
      const req = transport.request({
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: 'GET',
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
        timeout: 8000
      }, res => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try { resolve({ statusCode: res.statusCode, data: JSON.parse(body) }); }
          catch (e) { resolve({ statusCode: res.statusCode, data: null }); }
        });
      });
      req.on('error', () => resolve(null));
      req.on('timeout', () => { req.destroy(); resolve(null); });
      req.end();
    } catch (e) {
      resolve(null);
    }
  });
}

/**
 * The admin's company staff: [{ id, email, name, employeeId, department, designation, branch, status }].
 * Returns null when it cannot be read (no token, backend unreachable, token expired); the
 * caller then shows live agents only.
 */
async function getCompanyStaff(hrmsToken) {
  if (!hrmsToken) return null;
  const hit = cache.get(hrmsToken);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.staff;

  const resp = await getJson(`${HRMS_API_URL}/api/admin/dma/staff`, hrmsToken);
  const staff = resp && resp.statusCode === 200 && resp.data && resp.data.data && Array.isArray(resp.data.data.staff)
    ? resp.data.data.staff
    : null;
  if (staff) {
    cache.set(hrmsToken, { at: Date.now(), staff });
  } else if (hit) {
    return hit.staff; // keep the last good list through a brief backend outage
  }
  return staff;
}

module.exports = { getCompanyStaff, HRMS_API_URL };
