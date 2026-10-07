// LAN-only access guard: rejects HTTP requests and WebSocket upgrades from non-private IPs.
// Uses the raw socket address only — X-Forwarded-For is ignored so it cannot be spoofed.
// Disable with LAN_ONLY=false in .env (e.g. when deliberately exposing the server through a reverse proxy).

const LAN_ONLY = (process.env.LAN_ONLY || 'true').toLowerCase() !== 'false';

function normalizeIp(ip) {
  if (!ip) return '';
  let clean = ip.trim().toLowerCase();
  if (clean.startsWith('::ffff:')) clean = clean.slice(7); // IPv4-mapped IPv6
  return clean;
}

function isPrivateIp(rawIp) {
  const ip = normalizeIp(rawIp);
  if (!ip) return false;

  // IPv6: loopback, link-local fe80::/10, unique-local fc00::/7
  if (ip.includes(':')) {
    return ip === '::1' || /^fe[89ab]/.test(ip) || /^f[cd]/.test(ip);
  }

  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some(n => Number.isNaN(n))) return false;
  const [a, b] = parts;

  return (
    a === 10 ||                          // 10.0.0.0/8
    a === 127 ||                         // loopback
    (a === 172 && b >= 16 && b <= 31) || // 172.16.0.0/12
    (a === 192 && b === 168) ||          // 192.168.0.0/16
    (a === 169 && b === 254)             // link-local
  );
}

function lanOnlyHttp(req, res, next) {
  if (!LAN_ONLY || isPrivateIp(req.socket.remoteAddress)) return next();
  console.warn(`[LAN Guard] Blocked HTTP ${req.method} ${req.path} from ${req.socket.remoteAddress}`);
  res.status(403).json({ error: 'EktaDMA is available on the office LAN only.' });
}

// Returns true if the upgrade is allowed; otherwise destroys the socket
function allowLanUpgrade(request, socket) {
  if (!LAN_ONLY || isPrivateIp(request.socket.remoteAddress)) return true;
  console.warn(`[LAN Guard] Blocked WebSocket ${request.url} from ${request.socket.remoteAddress}`);
  socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
  socket.destroy();
  return false;
}

module.exports = { LAN_ONLY, isPrivateIp, lanOnlyHttp, allowLanUpgrade };
