export function getServerBaseUrl() {
  const customUrl = localStorage.getItem('ektahr_server_url');
  if (customUrl && !customUrl.includes(':9000') && !customUrl.includes('192.168.0.31')) {
    return customUrl.replace(/\/$/, '');
  }
  if (customUrl) {
    localStorage.removeItem('ektahr_server_url');
  }

  // If accessed via a domain name (e.g. track.ektahr.com) or non-dev port
  if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
    return window.location.origin;
  }

  if (window.location.port && window.location.port !== '3000' && window.location.port !== '5173') {
    return window.location.origin;
  }

  // Fallback for local development
  const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
  const hostname = window.location.hostname || 'localhost';
  return `${protocol}//${hostname}:2005`;
}

export function getServerWsUrl() {
  const httpUrl = getServerBaseUrl();
  return httpUrl.replace(/^http/, 'ws');
}

// ---- Office LAN server + online server ----
// The page is served either by an office LAN server (the admin's PC) or by the online server.
// An office LAN server names its online server, and the console signs in to both: office PCs come
// from the LAN server, employees on any other network from the online server.

const SERVER_INFO_KEY = 'ektahr_server_info';
const ONLINE_TOKEN_KEY = 'ektahr_online_token';
const LAN_ONLY_INFO = { mode: 'lan', env: 'production', onlineServerUrl: '' };

// GET /api/v1/server-info -> { mode: 'lan' | 'online', onlineServerUrl }, remembered for the session.
// Servers older than this console have no such route: they are plain LAN servers.
export async function loadServerInfo() {
  let info = LAN_ONLY_INFO;
  try {
    const res = await fetch(`${getServerBaseUrl()}/api/v1/server-info`);
    if (res.ok) {
      const data = await res.json();
      info = {
        mode: data.mode === 'online' ? 'online' : 'lan',
        env: data.env || 'production',
        onlineServerUrl: (data.onlineServerUrl || '').replace(/\/$/, '')
      };
    }
  } catch (e) {}
  localStorage.setItem(SERVER_INFO_KEY, JSON.stringify(info));
  return info;
}

export function getServerInfo() {
  try {
    return JSON.parse(localStorage.getItem(SERVER_INFO_KEY)) || LAN_ONLY_INFO;
  } catch {
    return LAN_ONLY_INFO;
  }
}

// This page came from the online server itself (no separate office server)
export function isOnlineOrigin() {
  return getServerInfo().mode === 'online';
}

// A separate online server this office console can also sign in to
export function hasSeparateOnlineServer() {
  return !isOnlineOrigin() && !!getServerInfo().onlineServerUrl;
}

export function getOnlineToken() {
  return localStorage.getItem(ONLINE_TOKEN_KEY) || '';
}

export function setOnlineToken(token) {
  if (token) localStorage.setItem(ONLINE_TOKEN_KEY, token);
  else localStorage.removeItem(ONLINE_TOKEN_KEY);
}

// Server a device's live view / remote access runs through:
//   'LAN'    -> the office LAN server that served this page
//   'ONLINE' -> the online server (on the online server's own page, that is this server)
export function routeServer(route) {
  if (route === 'ONLINE' && hasSeparateOnlineServer()) {
    const baseUrl = getServerInfo().onlineServerUrl;
    return { baseUrl, wsUrl: baseUrl.replace(/^http/, 'ws'), token: getOnlineToken() };
  }
  return { baseUrl: getServerBaseUrl(), wsUrl: getServerWsUrl(), token: localStorage.getItem('ektahr_token') || '' };
}

// Screenshots, idle logs, alerts and reports: agents save them on the online server whenever they
// reach it, so it holds every employee's data; without an online session the office server's is used.
export function getDataServer() {
  return hasSeparateOnlineServer() && getOnlineToken() ? routeServer('ONLINE') : routeServer('LAN');
}
