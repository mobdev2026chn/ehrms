import React, { useState, useEffect } from 'react';
import LoginModal from './components/LoginModal';
import DeviceGrid from './components/DeviceGrid';
import RemoteViewer from './components/RemoteViewer';
import ActivityReport from './components/ActivityReport';
import IdleAlerts from './components/IdleAlerts';
import { LogOut, Monitor, Activity, Wifi, RefreshCw, CalendarDays } from 'lucide-react';

import { getServerBaseUrl } from './config';

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem('ektahr_token') || '');
  const [user, setUser] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem('ektahr_user')) || null;
    } catch {
      return null;
    }
  });

  const [devices, setDevices] = useState([]);
  const [lanAgents, setLanAgents] = useState([]);
  const [lanScan, setLanScan] = useState({ state: 'scanning', at: null });
  const [showAllStaff, setShowAllStaff] = useState(false);
  const [activeTab, setActiveTab] = useState('LIVE');
  const [selectedDevice, setSelectedDevice] = useState(null);
  const [sessionMode, setSessionMode] = useState('VIEW_ONLY');

  const fetchDevices = async () => {
    try {
      const baseUrl = getServerBaseUrl();
      const response = await fetch(`${baseUrl}/api/v1/devices/list`, {
        headers: {
          'Authorization': `Bearer ${token}`
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

  // LAN scan: PCs whose agent is connected to this LAN server with an employee logged in
  const scanLanAgents = async () => {
    try {
      const baseUrl = getServerBaseUrl();
      const response = await fetch(`${baseUrl}/api/v1/lan/agents`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      if (response.status === 401) {
        handleLogout();
        return;
      }
      const data = await response.json();
      if (data.success && Array.isArray(data.agents)) {
        setLanAgents(data.agents);
        setLanScan({ state: 'done', at: new Date() });
      } else {
        setLanScan(prev => ({ ...prev, state: 'error' }));
      }
    } catch (e) {
      console.error('LAN scan failed:', e);
      setLanScan(prev => ({ ...prev, state: 'error' }));
    }
  };

  const refreshAll = () => {
    scanLanAgents();
    if (showAllStaff) fetchDevices();
  };

  // Scan the LAN automatically as soon as the admin logs in, then keep it live
  useEffect(() => {
    if (token) {
      setLanScan({ state: 'scanning', at: null });
      scanLanAgents();
      const interval = setInterval(scanLanAgents, 4000);
      return () => clearInterval(interval);
    }
  }, [token]);

  useEffect(() => {
    if (token && showAllStaff) {
      fetchDevices();
      const interval = setInterval(fetchDevices, 4000);
      return () => clearInterval(interval);
    }
  }, [token, showAllStaff]);

  const connectedIds = new Set(lanAgents.map(a => a.deviceId));
  const visibleDevices = showAllStaff
    ? [
        ...lanAgents,
        ...devices.filter(d => !connectedIds.has(d.deviceId))
      ]
    : lanAgents;

  const handleLoginSuccess = (newToken, userData) => {
    setToken(newToken);
    setUser(userData);
    localStorage.setItem('ektahr_token', newToken);
    localStorage.setItem('ektahr_user', JSON.stringify(userData));
  };

  const handleLogout = () => {
    setToken('');
    setUser(null);
    localStorage.removeItem('ektahr_token');
    localStorage.removeItem('ektahr_user');
  };

  if (!token) {
    return <LoginModal onLoginSuccess={handleLoginSuccess} />;
  }

  const connectedCount = lanAgents.length;

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
            </h1>
            <span style={{ fontSize: '0.75rem', color: '#d97706', fontWeight: 600 }}>
              Desktop Monitoring & Remote Access
            </span>
          </div>
        </div>

        {/* User Badge & Logout */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '18px' }}>
          <IdleAlerts
            token={token}
            nameFor={(email) => {
              const match = [...lanAgents, ...devices].find(d => (d.currentUser || '').toLowerCase() === email);
              return (match && match.fullName) || email;
            }}
            canView={(a) => lanAgents.some(d => d.deviceId === a.deviceId)}
            onView={(a) => {
              const agent = lanAgents.find(d => d.deviceId === a.deviceId);
              if (agent) {
                setSelectedDevice(agent);
                setSessionMode('VIEW_ONLY');
              }
            }}
          />

          <div style={{ textAlign: 'right' }}>
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
              <span style={{ fontSize: '0.8rem', color: '#64748b', fontWeight: 500 }}>Connected LAN Systems</span>
              <h3 style={{ fontSize: '1.6rem', fontWeight: 700, color: '#059669' }}>
                {lanScan.state === 'scanning' ? 'Scanning…' : `${connectedCount} Connected`}
              </h3>
            </div>
          </div>

          <div className="glass-panel" style={{ padding: '18px 22px', display: 'flex', alignItems: 'center', gap: '18px', background: '#ffffff', border: '1px solid #e2e8f0' }}>
            <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: '#fffbeb', border: '1px solid #fde68a', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#d97706' }}>
              <Wifi size={26} />
            </div>
            <div>
              <span style={{ fontSize: '0.8rem', color: '#64748b', fontWeight: 500 }}>Network Mode</span>
              <h3 style={{ fontSize: '1.6rem', fontWeight: 700, color: '#d97706' }}>Office LAN</h3>
              <span style={{ fontSize: '0.75rem', color: lanScan.state === 'error' ? '#dc2626' : '#94a3b8' }}>
                {lanScan.state === 'error'
                  ? 'LAN scan failed — retrying…'
                  : lanScan.at ? `Auto-scanned ${lanScan.at.toLocaleTimeString()}` : 'Scanning local network…'}
              </span>
            </div>
          </div>
        </div>

        {/* Tabs: Live devices | Date-wise activity report */}
        <div style={{ display: 'inline-flex', background: '#f1f5f9', padding: '4px', borderRadius: '10px', border: '1px solid #e2e8f0', marginBottom: '18px' }}>
          {[
            { key: 'LIVE', label: 'Live Devices', icon: <Monitor size={16} /> },
            { key: 'ACTIVITY', label: 'Activity Report', icon: <CalendarDays size={16} /> }
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

        {activeTab === 'ACTIVITY' ? (
          <ActivityReport />
        ) : (
        /* Device Grid Component */
        <DeviceGrid
          devices={visibleDevices}
          onRefresh={refreshAll}
          showAllStaff={showAllStaff}
          onToggleShowAll={() => setShowAllStaff(v => !v)}
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
