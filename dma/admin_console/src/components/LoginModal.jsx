import React, { useState } from 'react';
import { Lock, User, ShieldAlert, Settings, Eye, EyeOff } from 'lucide-react';
import { getServerBaseUrl } from '../config';

export default function LoginModal({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [serverUrl, setServerUrl] = useState(() => localStorage.getItem('ektahr_server_url') || '');
  const [showSettings, setShowSettings] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSaveSettings = (e) => {
    e.preventDefault();
    if (serverUrl.trim()) {
      localStorage.setItem('ektahr_server_url', serverUrl.trim().replace(/\/$/, ''));
    } else {
      localStorage.removeItem('ektahr_server_url');
    }
    setShowSettings(false);
  };

  const [isAlreadyLoggedIn, setIsAlreadyLoggedIn] = useState(false);

  const handleSubmit = async (e, force = false) => {
    if (e && e.preventDefault) e.preventDefault();
    setError('');
    setIsAlreadyLoggedIn(false);
    setLoading(true);

    try {
      const baseUrl = getServerBaseUrl();
      const response = await fetch(`${baseUrl}/api/v1/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password, forceLogout: force })
      });

      const data = await response.json();
      if (!response.ok) {
        if (data.isAlreadyLoggedIn) {
          setIsAlreadyLoggedIn(true);
        }
        throw new Error(data.error || 'EktaHR Login failed');
      }

      onLoginSuccess(data.token, data.user);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: 'rgba(241, 245, 249, 0.98)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 1000
    }}>
      <div className="glass-panel" style={{ width: '460px', padding: '40px', background: '#ffffff', border: '1px solid #e2e8f0', boxShadow: '0 10px 40px rgba(0, 0, 0, 0.08)' }}>
        <div style={{ textAlign: 'center', marginBottom: '24px' }}>
          {/* Cropped EktaHR Logo */}
          <div style={{
            width: '380px',
            height: '140px',
            margin: '0 auto 18px auto',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center'
          }}>
            <img
              src="/ektaHr_logo_cropped.png"
              alt="EktaHR Logo"
              style={{ height: '110px', width: 'auto', maxWidth: '100%', objectFit: 'contain' }}
              onError={(e) => {
                e.target.onerror = null;
                e.target.src = '/ektaHr_final.png';
              }}
            />
          </div>

          <h2 style={{ fontSize: '1.4rem', fontWeight: 700, color: '#0f172a', letterSpacing: '-0.02em' }}>
            EktaHR DMA Portal
          </h2>
          <p style={{ color: '#EFAA1F', fontSize: '0.85rem', fontWeight: 600, marginTop: '4px' }}>
            Desktop Monitoring & Remote Access Console
          </p>
        </div>

        {error && (
          <div style={{
            background: '#fef2f2',
            border: '1px solid #fecaca',
            borderRadius: '8px',
            padding: '12px 14px',
            marginBottom: '18px',
            display: 'flex',
            flexDirection: 'column',
            gap: '8px',
            color: '#dc2626',
            fontSize: '0.875rem'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <ShieldAlert size={18} />
              <span>{error}</span>
            </div>
            {isAlreadyLoggedIn && (
              <button
                type="button"
                onClick={() => handleSubmit(null, true)}
                style={{
                  marginTop: '4px',
                  padding: '8px 12px',
                  background: '#dc2626',
                  color: '#ffffff',
                  border: 'none',
                  borderRadius: '6px',
                  fontSize: '0.82rem',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Log In & Terminate Other Active Session
              </button>
            )}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: '18px' }}>
            <label style={{ display: 'block', color: '#475569', fontSize: '0.875rem', marginBottom: '6px', fontWeight: 600 }}>
              EktaHR Username / Email
            </label>
            <div style={{ position: 'relative' }}>
              <User size={18} color="#EFAA1F" style={{ position: 'absolute', left: '12px', top: '12px' }} />
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                style={{
                  width: '100%',
                  padding: '10px 12px 10px 40px',
                  background: '#f8fafc',
                  border: '1px solid #cbd5e1',
                  borderRadius: '8px',
                  color: '#0f172a',
                  fontSize: '0.95rem',
                  outline: 'none'
                }}
              />
            </div>
          </div>

          <div style={{ marginBottom: '24px' }}>
            <label style={{ display: 'block', color: '#475569', fontSize: '0.875rem', marginBottom: '6px', fontWeight: 600 }}>
              EktaHR Password
            </label>
            <div style={{ position: 'relative' }}>
              <Lock size={18} color="#EFAA1F" style={{ position: 'absolute', left: '12px', top: '12px' }} />
              <input
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                style={{
                  width: '100%',
                  padding: '10px 42px 10px 40px',
                  background: '#f8fafc',
                  border: '1px solid #cbd5e1',
                  borderRadius: '8px',
                  color: '#0f172a',
                  fontSize: '0.95rem',
                  outline: 'none'
                }}
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                style={{
                  position: 'absolute',
                  right: '10px',
                  top: '10px',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  padding: '2px',
                  display: 'flex',
                  alignItems: 'center',
                  color: showPassword ? '#EFAA1F' : '#94a3b8'
                }}
                title={showPassword ? 'Hide Password' : 'Show Password'}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            className="glass-button"
            disabled={loading}
            style={{ width: '100%', justifyContent: 'center', padding: '12px', fontSize: '1rem' }}
          >
            {loading ? 'Authenticating EktaHR...' : 'Sign In with EktaHR'}
          </button>
        </form>

        {/* Server Connection Customization Toggle */}
        <div style={{ marginTop: '20px', textAlign: 'center', borderTop: '1px solid #f1f5f9', paddingTop: '16px' }}>
          <button
            type="button"
            onClick={() => setShowSettings(!showSettings)}
            style={{
              background: 'none',
              border: 'none',
              color: '#64748b',
              fontSize: '0.82rem',
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px'
            }}
          >
            <Settings size={14} />
            <span>{showSettings ? 'Hide Server Settings' : 'Configure Server Address'}</span>
          </button>

          {showSettings && (
            <div style={{ marginTop: '12px', padding: '12px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0', textAlign: 'left' }}>
              <label style={{ display: 'block', fontSize: '0.78rem', color: '#475569', fontWeight: 600, marginBottom: '6px' }}>
                Server Base URL (Default: Auto-detect / port 9000)
              </label>
              <input
                type="text"
                placeholder="e.g. http://192.168.1.100:9000"
                value={serverUrl}
                onChange={(e) => setServerUrl(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 10px',
                  border: '1px solid #cbd5e1',
                  borderRadius: '6px',
                  fontSize: '0.85rem',
                  marginBottom: '8px'
                }}
              />
              <button
                type="button"
                onClick={handleSaveSettings}
                style={{
                  padding: '6px 12px',
                  fontSize: '0.8rem',
                  background: '#f59e0b',
                  color: '#ffffff',
                  border: 'none',
                  borderRadius: '6px',
                  cursor: 'pointer',
                  fontWeight: 600
                }}
              >
                Save Server Address
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
