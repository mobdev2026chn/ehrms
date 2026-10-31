import React, { useState, useEffect, useRef } from 'react';
import LoginModal from './components/LoginModal';
import DeviceGrid from './components/DeviceGrid';
import RemoteViewer from './components/RemoteViewer';
import ActivityReport from './components/ActivityReport';
import SettingsPanel from './components/SettingsPanel';
import IdleAlerts from './components/IdleAlerts';
import { LogOut, Monitor, Activity, Wifi, RefreshCw, CalendarDays, Settings } from 'lucide-react';

import {
  loadServerInfo, getServerInfo, isOnlineOrigin, hasSeparateOnlineServer,
  getOnlineToken, setOnlineToken, routeServer, getDataServer
} from './config';
import { signIn, getAutoLogin, setAutoLogin, tokenSecondsLeft, isRejectedLogin } from './auth';

// Session renewed this long before its 24 hours run out, so an open live view never hits an expired token
const RENEW_BEFORE_SECONDS = 10 * 60;

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem('ektahr_token') || '');
  const [user, setUser] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem('ektahr_user')) || null;
    } catch {
      return null;
    }
  });

  const [onlineToken, setOnlineTokenState] = useState(() => getOnlineToken());
  const [devices, setDevices] = useState([]);
  // Connected PCs with an employee logged in: office LAN + any network, one entry per PC.
  // network: 'LAN' (office network) | 'ONLINE' (elsewhere); route: server its live view runs through
  const [agents, setAgents] = useState([]);
  const [lanScan, setLanScan] = useState({ state: 'scanning', at: null });
  // 'online' (page served by the online server) | 'connected' | 'unreachable' | 'off' (LAN-only server)
  const [onlineState, setOnlineState] = useState(() => isOnlineOrigin() ? 'online' : 'off');
  const [networkFilter, setNetworkFilter] = useState('ALL');
  const [showAllStaff, setShowAllStaff] = useState(false);
  const [activeTab, setActiveTab] = useState('LIVE');
  const [selectedDevice, setSelectedDevice] = useState(null);
  const [sessionMode, setSessionMode] = useState('VIEW_ONLY');
  // Opened with no live session (none saved, or its 24 hours are over) but a remembered sign-in:
  // sign in with it behind a short "Signing in" screen instead of showing the login form.
  const [autoSigningIn, setAutoSigningIn] = useState(() => {
    const saved = localStorage.getItem('ektahr_token') || '';
    const left = saved ? tokenSecondsLeft(saved) : 0;
    return left !== null && left <= 0 && !!getAutoLogin();
  });
  // Why the remembered sign-in failed, shown on the login screen
  const [autoLoginError, setAutoLoginError] = useState('');
  const renewal = useRef(null);
  const lastRenewAt = useRef(0);

  const dataServer = getDataServer();

  // Remembered sign-in: a fresh session (and online token) without the login screen. Calls made
  // while one is under way share it, so the 4-second scan never signs in twice at once.
  const renewSession = () => {
    if (renewal.current) return renewal.current;
    const saved = getAutoLogin();
    if (!saved) return Promise.resolve(false);
    lastRenewAt.current = Date.now();
    renewal.current = signIn(saved.username, saved.password)
      .then((session) => {
        handleLoginSuccess(session.token, session.user, session.onlineToken);
        setAutoLoginError('');
        return true;
      })
      .catch((err) => {
        // Password changed / account blocked: stop, so retries don't add failed logins to the account
        if (isRejectedLogin(err)) setAutoLogin(false);
        setAutoLoginError(err.message);
        return false;
      })
      .finally(() => { renewal.current = null; });
    return renewal.current;
  };

  useEffect(() => {
    if (!autoSigningIn) return;
    renewSession().then((ok) => {
      if (!ok) clearSession();
      setAutoSigningIn(false);
    });
  }, []);

  const fetchDevices = async () => {
    try {
      const { baseUrl, token: dataToken } = getDataServer();
      const response = await fetch(`${baseUrl}/api/v1/devices/list`, {
        headers: {
          'Authorization': `Bearer ${dataToken}`
        }
      });
      const data = await response.json();
      const deviceArr = data.devices || data.data || (Array.isArray(data) ? data : []);
      if (Array.isArray(deviceArr)) {
        setDevices(deviceArr);
      }
    } catch (e) {
      console.error('Failed to fetch device list:', e);
    }
  };

  // Connected PCs (with an employee logged in) on one server: 'LAN' = this office server, 'ONLINE' = online server
  const fetchConnected = async (route) => {
    const { baseUrl, token: routeToken } = routeServer(route);
    const response = await fetch(`${baseUrl}/api/v1/lan/agents`, {
      headers: {
        'Authorization': `Bearer ${routeToken}`
      }
    });
    if (response.status === 401) return { unauthorized: true };
    const data = await response.json();
    return data.success && Array.isArray(data.agents) ? { agents: data.agents } : { error: true };
  };

  // Scan: office PCs from this LAN server + employees on any network from the online server
  const scanAgents = async () => {
    const left = tokenSecondsLeft(localStorage.getItem('ektahr_token') || '');
    if (left !== null && left < RENEW_BEFORE_SECONDS && Date.now() - lastRenewAt.current > 60000) {
      renewSession();
    }
    const onlinePage = isOnlineOrigin();
    const withOnline = hasSeparateOnlineServer() && !!getOnlineToken();
    const failed = (e) => { console.error('Device scan failed:', e); return { error: true }; };
    const [local, remote] = await Promise.all([
      fetchConnected(onlinePage ? 'ONLINE' : 'LAN').catch(failed),
      withOnline ? fetchConnected('ONLINE').catch(failed) : Promise.resolve(null)
    ]);
    if (local.unauthorized) {
      // Session over: the remembered sign-in renews it, otherwise back to the login screen
      if (!(await renewSession())) clearSession();
      return;
    }
    if (remote && remote.unauthorized) {
      // Online session expired: keep showing the office LAN (and sign in to it again when remembered)
      setOnlineToken('');
      setOnlineTokenState('');
      renewSession();
    }
    setOnlineState(onlinePage ? 'online' : !hasSeparateOnlineServer() ? 'off' : remote && remote.agents ? 'connected' : 'unreachable');

    if (!local.agents && !(remote && remote.agents)) {
      setLanScan(prev => ({ ...prev, state: 'error' }));
      return;
    }

    const merged = new Map();
    for (const a of local.agents || []) {
      merged.set(a.deviceId, onlinePage
        ? { ...a, network: a.network === 'LAN' ? 'LAN' : 'ONLINE', route: 'ONLINE' }
        : { ...a, network: 'LAN', route: 'LAN' });
    }
    // An office PC is on both servers: its LAN entry wins (live view stays on the office network)
    for (const a of (remote && remote.agents) || []) {
      if (!merged.has(a.deviceId)) {
        merged.set(a.deviceId, { ...a, network: a.network === 'LAN' ? 'LAN' : 'ONLINE', route: 'ONLINE' });
      }
    }
    setAgents([...merged.values()]);
    setLanScan({ state: 'done', at: new Date() });
  };

  const refreshAll = () => {
    scanAgents();
    if (showAllStaff) fetchDevices();
  };

  // Scan automatically as soon as the admin logs in, then keep it live
  useEffect(() => {
    if (token) {
      setLanScan({ state: 'scanning', at: null });
      // Refresh which servers this console talks to (the office server may have gained an online server)
      loadServerInfo().finally(scanAgents);
      const interval = setInterval(scanAgents, 4000);
      return () => clearInterval(interval);
    }
  }, [token, onlineToken]);

  useEffect(() => {
    if (token && showAllStaff) {
      fetchDevices();
      const interval = setInterval(fetchDevices, 4000);
      return () => clearInterval(interval);
    }
  }, [token, onlineToken, showAllStaff]);

  const networkCounts = {
    ALL: agents.length,
    LAN: agents.filter(a => a.network === 'LAN').length,
    ONLINE: agents.filter(a => a.network !== 'LAN').length
  };
  const filteredAgents = networkFilter === 'ALL'
    ? agents
    : agents.filter(a => (a.network === 'LAN') === (networkFilter === 'LAN'));
  const connectedIds = new Set(agents.map(a => a.deviceId));
  // Offline staff have no network, so they are listed under "All" only
  const visibleDevices = showAllStaff && networkFilter === 'ALL'
    ? [
        ...filteredAgents,
        ...devices.filter(d => !connectedIds.has(d.deviceId))
      ]
    : filteredAgents;

  const handleLoginSuccess = (newToken, userData, newOnlineToken = '') => {
    setToken(newToken);
    setUser(userData);
    localStorage.setItem('ektahr_token', newToken);
    localStorage.setItem('ektahr_user', JSON.stringify(userData));
    setOnlineToken(newOnlineToken);
    setOnlineTokenState(newOnlineToken);
    setAutoLogin(true);
  };

  // Logout button: the admin chose to leave, so the remembered sign-in waits for Sign In
  const handleLogout = () => {
    setAutoLogin(false);
    setAutoLoginError('');
    clearSession();
  };

  const clearSession = () => {
    setToken('');
    setUser(null);
    localStorage.removeItem('ektahr_token');
    localStorage.removeItem('ektahr_user');
    setOnlineToken('');
    setOnlineTokenState('');
    setAgents([]);
  };

  if (autoSigningIn) {
    return (
      <div style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', backgroundColor: '#f1f5f9' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', color: '#475569', fontSize: '0.95rem', fontWeight: 600 }}>
          <RefreshCw size={18} color="#EFAA1F" className="spin" />
          <span>Signing in to EktaHR…</span>
        </div>
      </div>
    );
  }

  if (!token) {
    return <LoginModal onLoginSuccess={handleLoginSuccess} initialError={autoLoginError} />;
  }

  const connectedCount = agents.length;
  const networkMode = {
    online: { title: 'Online', note: 'Employees on any network — office PCs are marked LAN' },
    connected: { title: 'Office LAN + Online', note: 'Office PCs and employees on other networks' },
    unreachable: { title: 'Office LAN', note: onlineToken ? 'Online server not reachable — showing office PCs only' : 'Not signed in to the online server — log in again to include remote employees' },
    off: { title: 'Office LAN', note: 'This server shows office PCs only' }
  }[onlineState];

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: '#f8fafc' }}>
      {/* Top Header Bar with Official EktaHR Brand Logo */}
      <header style={{
        background: '#ffffff',
        borderBottom: '1px solid #e2e8f0',
        padding: '0 28px',
        height: '88px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        position: 'sticky',
        top: 0,
        zIndex: 100,
        boxShadow: '0 2px 12px rgba(0, 0, 0, 0.04)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '22px' }}>
          {/* Cropped EktaHR Brand Logo */}
          <div style={{
            height: '56px',
            display: 'flex',
            alignItems: 'center'
          }}>
            <img
              src="/ektaHr_logo_cropped.png"
              alt="EktaHR Logo"
              style={{ height: '56px', width: 'auto', objectFit: 'contain' }}
              onError={(e) => {
                e.target.onerror = null;
                e.target.src = '/ektaHr_logo_white.png';
              }}
            />
          </div>

          <div>
            <h1 style={{ fontSize: '1.2rem', fontWeight: 700, color: '#0f172a', letterSpacing: '-0.01em' }}>
              EktaHR DMA Portal
              {/* Non-production server (DMA_ENV): say so, so test data is never mistaken for live */}
              {getServerInfo().env && getServerInfo().env !== 'production' && (
                <span style={{ marginLeft: '10px', fontSize: '0.7rem', fontWeight: 700, color: '#ffffff', background: '#7c3aed', padding: '2px 8px', borderRadius: '10px', verticalAlign: 'middle', textTransform: 'uppercase' }}>
                  {getServerInfo().env}
                </span>
              )}
            </h1>
            <span style={{ fontSize: '0.75rem', color: '#d97706', fontWeight: 600 }}>
              Desktop Monitoring & Remote Access
            </span>
          </div>
        </div>

        {/* User Badge & Logout */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '18px' }}>
          <IdleAlerts
            baseUrl={dataServer.baseUrl}
            token={dataServer.token}
            nameFor={(email) => {
              const match = [...agents, ...devices].find(d => (d.currentUser || '').toLowerCase() === email);
              return (match && match.fullName) || email;
            }}
            canView={(a) => agents.some(d => d.deviceId === a.deviceId)}
            onView={(a) => {
              const agent = agents.find(d => d.deviceId === a.deviceId);
              if (agent) {
                setSelectedDevice(agent);
                setSessionMode('VIEW_ONLY');
              }
            }}
          />

          {/* Opens Profile & Settings */}
          <div style={{ textAlign: 'right', cursor: 'pointer' }} title="Profile & Settings" onClick={() => setActiveTab('SETTINGS')}>
            <div style={{ fontSize: '0.9rem', fontWeight: 600, color: '#0f172a' }}>
              {user?.fullName || user?.username}
            </div>
            <span style={{ fontSize: '0.75rem', color: '#b45309', fontWeight: 600, background: '#fef3c7', border: '1px solid #fde68a', padding: '2px 8px', borderRadius: '12px' }}>
              {user?.role || 'SUPER_ADMIN'}
            </span>
          </div>

          <button className="glass-button danger" onClick={handleLogout} style={{ padding: '8px 14px' }}>
            <LogOut size={16} />
            <span>Logout</span>
          </button>
        </div>
      </header>

      {/* Main Container */}
      <main style={{ flex: 1, padding: '28px', maxWidth: '1440px', margin: '0 auto', width: '100%' }}>
        {/* Metric Cards Summary with Light Themes */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '18px', marginBottom: '28px' }}>
          <div className="glass-panel" style={{ padding: '18px 22px', display: 'flex', alignItems: 'center', gap: '18px', background: '#ffffff', border: '1px solid #e2e8f0' }}>
            <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: '#ecfdf5', border: '1px solid #a7f3d0', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#059669' }}>
              <Activity size={26} />
            </div>
            <div>
              <span style={{ fontSize: '0.8rem', color: '#64748b', fontWeight: 500 }}>Connected Systems</span>
              <h3 style={{ fontSize: '1.6rem', fontWeight: 700, color: '#059669' }}>
                {lanScan.state === 'scanning' ? 'Scanning…' : `${connectedCount} Connected`}
              </h3>
              {lanScan.state !== 'scanning' && (
                <span style={{ fontSize: '0.75rem', color: '#94a3b8' }}>
                  LAN {networkCounts.LAN} · Online {networkCounts.ONLINE}
                </span>
              )}
            </div>
          </div>

          <div className="glass-panel" style={{ padding: '18px 22px', display: 'flex', alignItems: 'center', gap: '18px', background: '#ffffff', border: '1px solid #e2e8f0' }}>
            <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: '#fffbeb', border: '1px solid #fde68a', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#d97706' }}>
              <Wifi size={26} />
            </div>
            <div>
              <span style={{ fontSize: '0.8rem', color: '#64748b', fontWeight: 500 }}>Network Mode</span>
              <h3 style={{ fontSize: '1.6rem', fontWeight: 700, color: '#d97706' }}>{networkMode.title}</h3>
              <span style={{ display: 'block', fontSize: '0.75rem', color: onlineState === 'unreachable' ? '#b45309' : '#94a3b8' }}>
                {networkMode.note}
              </span>
              <span style={{ fontSize: '0.75rem', color: lanScan.state === 'error' ? '#dc2626' : '#94a3b8' }}>
                {lanScan.state === 'error'
                  ? 'Scan failed — retrying…'
                  : lanScan.at ? `Auto-scanned ${lanScan.at.toLocaleTimeString()}` : 'Scanning…'}
              </span>
            </div>
          </div>
        </div>

        {/* Tabs: Live devices | Date-wise activity report */}
        <div style={{ display: 'inline-flex', background: '#f1f5f9', padding: '4px', borderRadius: '10px', border: '1px solid #e2e8f0', marginBottom: '18px' }}>
          {[
            { key: 'LIVE', label: 'Live Devices', icon: <Monitor size={16} /> },
            { key: 'ACTIVITY', label: 'Activity Report', icon: <CalendarDays size={16} /> },
            { key: 'SETTINGS', label: 'Profile & Settings', icon: <Settings size={16} /> }
          ].map(t => (
            <button
              key={t.key}
              onClick={() => setActiveTab(t.key)}
              style={{
                background: activeTab === t.key ? '#ffffff' : 'transparent',
                color: activeTab === t.key ? '#d97706' : '#64748b',
                border: 'none',
                padding: '8px 16px',
                borderRadius: '8px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                fontWeight: 600,
                fontSize: '0.88rem',
                boxShadow: activeTab === t.key ? '0 1px 3px rgba(0,0,0,0.1)' : 'none'
              }}
            >
              {t.icon}
              <span>{t.label}</span>
            </button>
          ))}
        </div>

        {activeTab === 'SETTINGS' ? (
          <SettingsPanel user={user} onlineState={onlineState} onLogout={handleLogout} />
        ) : activeTab === 'ACTIVITY' ? (
          <ActivityReport />
        ) : (
        /* Device Grid Component */
        <DeviceGrid
          devices={visibleDevices}
          onRefresh={refreshAll}
          showAllStaff={showAllStaff}
          onToggleShowAll={() => setShowAllStaff(v => !v)}
          networkFilter={networkFilter}
          onNetworkFilterChange={setNetworkFilter}
          networkCounts={networkCounts}
          scanning={lanScan.state === 'scanning'}
          onSelectDevice={(device, mode) => {
            setSelectedDevice(device);
            setSessionMode(mode);
          }}
        />
        )}
      </main>

      {/* Remote Screen Overlay Viewer */}
      {selectedDevice && (
        <RemoteViewer
          device={selectedDevice}
          initialMode={sessionMode}
          onClose={() => setSelectedDevice(null)}
        />
      )}
    </div>
  );
}
