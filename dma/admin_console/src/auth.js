import { getServerBaseUrl, loadServerInfo } from './config';

// Remembered sign-in ("Remember me" on the login screen). The DMA session token lasts 24 hours;
// with a remembered sign-in the console renews it by itself instead of sending the admin back to
// the login screen. Kept in this console's own Edge profile on the admin's PC.
const SAVED_LOGIN_KEY = 'ektahr_saved_login';
// Off after the Logout button (the admin chose to leave) or a rejected password: wait for Sign In.
const AUTO_LOGIN_KEY = 'ektahr_auto_login';

export function getSavedLogin() {
  try {
    const saved = JSON.parse(localStorage.getItem(SAVED_LOGIN_KEY));
    return saved && saved.username && saved.password ? saved : null;
  } catch {
    return null;
  }
}

export function saveLogin(username, password) {
  localStorage.setItem(SAVED_LOGIN_KEY, JSON.stringify({ username, password }));
}

export function forgetLogin() {
  localStorage.removeItem(SAVED_LOGIN_KEY);
}

export function setAutoLogin(on) {
  if (on) localStorage.setItem(AUTO_LOGIN_KEY, '1');
  else localStorage.removeItem(AUTO_LOGIN_KEY);
}

// The remembered sign-in, when the console may use it without the admin pressing Sign In
export function getAutoLogin() {
  return localStorage.getItem(AUTO_LOGIN_KEY) === '1' ? getSavedLogin() : null;
}

// Seconds left on a DMA token (its own exp claim); null when it can't be read.
export function tokenSecondsLeft(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return typeof payload.exp === 'number' ? payload.exp - Date.now() / 1000 : null;
  } catch {
    return null;
  }
}

// Office LAN server: also sign in to its online server so the admin sees employees on any network.
// Not reachable (no internet, server down) = office LAN only; that never blocks the login.
async function signInOnline(onlineServerUrl, body) {
  if (!onlineServerUrl) return '';
  try {
    const response = await fetch(`${onlineServerUrl}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    });
    const data = await response.json();
    return response.ok && data.token ? data.token : '';
  } catch (e) {
    return '';
  }
}

// Signs in to this console's server (and its online server) -> { token, user, onlineToken }.
// Throws an Error carrying the server's status (none = server not reached) and isAlreadyLoggedIn.
export async function signIn(username, password, force = false) {
  const info = await loadServerInfo();
  const body = JSON.stringify({ username, password, forceLogout: force });
  const onlineLogin = info.mode === 'lan' ? signInOnline(info.onlineServerUrl, body) : Promise.resolve('');
  let response;
  try {
    response = await fetch(`${getServerBaseUrl()}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    });
  } catch (e) {
    throw Object.assign(new Error('DMA server not reachable. Please try again.'), { status: 0 });
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw Object.assign(new Error(data.error || 'EktaHR Login failed'), {
      status: response.status,
      isAlreadyLoggedIn: !!data.isAlreadyLoggedIn
    });
  }
  return { token: data.token, user: data.user, onlineToken: await onlineLogin };
}

// The server answered "no" (wrong password, account blocked, ...), rather than not being reached:
// retrying with the same password would only count as more failed logins on the EktaHR account.
export function isRejectedLogin(err) {
  return !!err && err.status >= 400 && err.status < 500;
}
