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
