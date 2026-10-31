import React, { useState, useEffect, useRef } from 'react';
import { User, Mail, Shield, Globe, Wifi, RefreshCw, Download, LogOut, Server, Monitor, CheckCircle2, AlertTriangle } from 'lucide-react';
import { getServerBaseUrl, getServerInfo, isOnlineOrigin } from '../config';
import PrivacySites from './PrivacySites';

// Profile + Settings tab: who is signed in, this Admin Console's version and auto-update (office
// server inside the Admin Console updates itself from the online server - adminConsoleUpdate.js).

const card = { padding: '22px 24px', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '16px' };
const rowStyle = { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '10px 0', borderBottom: '1px solid #f1f5f9', fontSize: '0.88rem' };
const labelStyle = { color: '#64748b', display: 'flex', alignItems: 'center', gap: '8px' };
const valueStyle = { color: '#0f172a', fontWeight: 600, textAlign: 'right' };

const Row = ({ icon, label, children }) => (
  <div style={rowStyle}>
    <span style={labelStyle}>{icon}{label}</span>
    <span style={valueStyle}>{children}</span>
  </div>
);

const ONLINE_STATE_TEXT = {
  online: 'This is the online server',
  connected: 'Signed in',
  unreachable: 'Not signed in / not reachable',
  off: 'Not used (office LAN only)'
};

function Toggle({ checked, disabled, onChange }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      style={{
        width: '46px', height: '24px', borderRadius: '12px', border: 'none', position: 'relative',
        background: checked ? '#d97706' : '#cbd5e1', cursor: disabled ? 'not-allowed' : 'pointer', opacity: disabled ? 0.5 : 1,
        transition: 'background 0.15s'
      }}
    >
      <span style={{
        position: 'absolute', top: '3px', left: checked ? '25px' : '3px', width: '18px', height: '18px',
        borderRadius: '50%', background: '#ffffff', transition: 'left 0.15s', boxShadow: '0 1px 3px rgba(0,0,0,0.2)'
      }} />
    </button>
  );
}

export default function SettingsPanel({ user, onlineState, onLogout }) {
  const [status, setStatus] = useState(null);
  const [loadError, setLoadError] = useState('');
  const [busy, setBusy] = useState(''); // '' | 'checking' | 'updating'
  const [message, setMessage] = useState(null); // { kind: 'ok' | 'error', text }
  const pollRef = useRef(null);

  const api = async (path, options = {}) => {
    const token = localStorage.getItem('ektahr_token') || '';
    const res = await fetch(`${getServerBaseUrl()}${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...(options.headers || {}) }
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.success === false) throw new Error(data.error || `Request failed (${res.status})`);
    return data;
  };

  const loadStatus = async (check) => {
    try {
      setStatus(await api(`/api/v1/admin-console/status${check ? '?check=1' : ''}`));
      setLoadError('');
    } catch (e) {
      setLoadError(e.message);
    }
  };

  useEffect(() => {
    loadStatus(true);
    return () => clearInterval(pollRef.current);
  }, []);

  const setAutoUpdate = async (value) => {
    try {
      await api('/api/v1/admin-console/settings', { method: 'PUT', body: JSON.stringify({ autoUpdate: value }) });
      setStatus(s => ({ ...s, autoUpdate: value }));
      setMessage({ kind: 'ok', text: value ? 'Auto update is on: new versions install by themselves.' : 'Auto update is off: use Update to install new versions.' });
    } catch (e) {
      setMessage({ kind: 'error', text: e.message });
    }
  };

  // The server restarts into the new version: wait until it answers with it, then reload the console
  const waitForNewVersion = (target) => {
    clearInterval(pollRef.current);
    const started = Date.now();
    pollRef.current = setInterval(async () => {
      try {
        const s = await api('/api/v1/admin-console/status');
        if (s.version === target) {
          clearInterval(pollRef.current);
          window.location.reload();
        }
      } catch (e) { /* restarting */ }
      if (Date.now() - started > 3 * 60 * 1000) {
        clearInterval(pollRef.current);
        setBusy('');
        setMessage({ kind: 'error', text: 'The update did not finish in time. Reopen the Admin Console.' });
      }
    }, 2000);
  };

  const update = async () => {
    setBusy('checking');
    setMessage(null);
    try {
      const result = await api('/api/v1/admin-console/update', { method: 'POST' });
      if (result.updating) {
        setBusy('updating');
        setMessage({ kind: 'ok', text: `Installing Admin Console ${result.version || result.updatingTo} - the console reloads in a few seconds.` });
        waitForNewVersion(result.version || result.updatingTo);
        return;
      }
      setStatus(s => ({ ...s, ...result }));
      setMessage(result.error
        ? { kind: 'error', text: result.error }
        : { kind: 'ok', text: `Admin Console ${result.version} is up to date.` });
    } catch (e) {
      setMessage({ kind: 'error', text: e.message });
    }
    setBusy('');
  };

  const env = (status && status.env) || getServerInfo().env || 'production';
  const onlinePage = isOnlineOrigin();
  const initial = (user?.fullName || user?.username || 'A').charAt(0).toUpperCase();

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))', gap: '18px', alignItems: 'start' }}>
      {/* Profile */}
      <div style={card}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '14px' }}>
          <div style={{
            width: '52px', height: '52px', borderRadius: '50%', background: '#fffbeb', border: '1px solid #fde68a',
            color: '#d97706', fontWeight: 700, fontSize: '1.3rem', display: 'flex', alignItems: 'center', justifyContent: 'center'
          }}>{initial}</div>
          <div>
            <h3 style={{ fontSize: '1.1rem', fontWeight: 700, color: '#0f172a' }}>{user?.fullName || user?.username}</h3>
            <span style={{ fontSize: '0.75rem', color: '#b45309', fontWeight: 600, background: '#fef3c7', border: '1px solid #fde68a', padding: '2px 8px', borderRadius: '12px' }}>
              {user?.role || 'ADMIN'}
            </span>
          </div>
        </div>
        <Row icon={<Mail size={15} />} label="Email">{user?.email || user?.username}</Row>
        <Row icon={<Shield size={15} />} label="Role">{user?.hrmsRole || user?.role}</Row>
        <Row icon={<Server size={15} />} label="Environment">
          <span style={{ textTransform: 'capitalize', color: env === 'production' ? '#047857' : '#7c3aed' }}>{env}</span>
        </Row>
        <Row icon={<Wifi size={15} />} label={onlinePage ? 'Server' : 'Office server'}>{onlinePage ? 'Online server' : 'This PC / office LAN'}</Row>
        <Row icon={<Globe size={15} />} label="Online server">{ONLINE_STATE_TEXT[onlineState] || '—'}</Row>
        <button className="glass-button danger" onClick={onLogout} style={{ marginTop: '16px', padding: '8px 14px' }}>
          <LogOut size={16} />
          <span>Log out</span>
        </button>
      </div>

      {/* Admin Console version + updates */}
      <div style={card}>
        <h3 style={{ fontSize: '1.05rem', fontWeight: 700, color: '#0f172a', marginBottom: '6px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Monitor size={18} color="#d97706" /> Admin Console
        </h3>
        {loadError && <p style={{ color: '#dc2626', fontSize: '0.85rem' }}>{loadError}</p>}
        {status && (
          <>
            <Row label="Version">{status.version || '—'}</Row>
            <Row label="Latest version">
              {status.canSelfUpdate
                ? (status.latestVersion
                  ? `${status.latestVersion}${status.updateAvailable ? ' (new)' : ''}`
                  : (status.error ? 'could not check' : '—'))
                : status.version}
            </Row>
            <Row label="Agent version handed out">{status.agentVersion || '—'}</Row>
            {status.canSelfUpdate ? (
              <>
                <div style={rowStyle}>
                  <span style={labelStyle}>Auto update</span>
                  <Toggle checked={!!status.autoUpdate} disabled={!!busy} onChange={setAutoUpdate} />
                </div>
                <div style={{ display: 'flex', gap: '10px', marginTop: '16px', flexWrap: 'wrap' }}>
                  <button
                    onClick={update}
                    disabled={!!busy}
                    style={{
                      padding: '8px 18px', fontSize: '0.88rem', fontWeight: 600, color: '#ffffff', border: 'none', borderRadius: '8px',
                      background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)', cursor: busy ? 'wait' : 'pointer',
                      display: 'inline-flex', alignItems: 'center', gap: '6px', opacity: busy ? 0.7 : 1
                    }}
                  >
                    {busy ? <RefreshCw size={15} className="spin" /> : <Download size={15} />}
                    <span>{busy === 'checking' ? 'Checking...' : busy === 'updating' ? 'Updating...' : 'Update'}</span>
                  </button>
                  <button className="glass-button outline" disabled={!!busy} onClick={() => loadStatus(true)} style={{ padding: '8px 14px', fontSize: '0.85rem' }}>
                    <RefreshCw size={15} />
                    <span>Check now</span>
                  </button>
                </div>
                <p style={{ color: '#94a3b8', fontSize: '0.78rem', marginTop: '12px' }}>
                  Auto update installs new versions by itself (checked every 30 minutes; it waits while a screen is being viewed).
                </p>
              </>
            ) : (
              <p style={{ color: '#94a3b8', fontSize: '0.8rem', marginTop: '12px' }}>
                This console runs on a server that is updated with its deploy (git pull + restart).
              </p>
            )}
          </>
        )}
        {message && (
          <div style={{
            marginTop: '14px', padding: '10px 12px', borderRadius: '8px', fontSize: '0.84rem', display: 'flex', gap: '8px', alignItems: 'flex-start',
            background: message.kind === 'ok' ? '#ecfdf5' : '#fef2f2', color: message.kind === 'ok' ? '#047857' : '#b91c1c',
            border: `1px solid ${message.kind === 'ok' ? '#a7f3d0' : '#fecaca'}`
          }}>
            {message.kind === 'ok' ? <CheckCircle2 size={16} /> : <AlertTriangle size={16} />}
            <span>{message.text}</span>
          </div>
        )}
      </div>

      <PrivacySites user={user} />
    </div>
  );
}
