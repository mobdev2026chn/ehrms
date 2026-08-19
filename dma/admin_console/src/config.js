export function getServerBaseUrl() {
  const customUrl = localStorage.getItem('ektahr_server_url');
  if (customUrl) return customUrl.replace(/\/$/, '');

  // If served directly by express server on port 9000 or custom port
  if (window.location.port && window.location.port !== '3000' && window.location.port !== '5173') {
    return window.location.origin;
  }

  // Default fallback to server on port 2005
  const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
  const hostname = window.location.hostname || 'localhost';
  return `${protocol}//${hostname}:2005`;
}

export function getServerWsUrl() {
  const httpUrl = getServerBaseUrl();
  return httpUrl.replace(/^http/, 'ws');
}
