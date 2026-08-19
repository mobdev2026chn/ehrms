import React, { useState, useEffect } from 'react';
import { Monitor, Eye, MousePointer, User, Wifi, RefreshCw, LayoutGrid, List, Search, Camera, X } from 'lucide-react';
import { getServerBaseUrl } from '../config';

export default function DeviceGrid({ devices, onRefresh, onSelectDevice }) {
  const [viewMode, setViewMode] = useState('LIST');
  const [searchTerm, setSearchTerm] = useState('');
  const [activeScreenshotDevice, setActiveScreenshotDevice] = useState(null);
  const [screenshots, setScreenshots] = useState([]);
  const [loadingSs, setLoadingSs] = useState(false);
  const [previewImage, setPreviewImage] = useState(null);

  useEffect(() => {
    if (activeScreenshotDevice) {
      setLoadingSs(true);
      const devId = activeScreenshotDevice.deviceId;
      const baseUrl = getServerBaseUrl();
      const token = localStorage.getItem('ektahr_token') || '';
      fetch(`${baseUrl}/api/v1/devices/${encodeURIComponent(devId)}/screenshots`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      })
        .then(res => res.json())
        .then(data => {
          if (data.success) {
            setScreenshots(data.screenshots || []);
          }
          setLoadingSs(false);
        })
        .catch(() => setLoadingSs(false));
    }
  }, [activeScreenshotDevice]);

  const sortedDevices = [...devices]
    .filter(d => {
      const query = searchTerm.toLowerCase();
      return (
        (d.hostname || '').toLowerCase().includes(query) ||
        (d.currentUser || '').toLowerCase().includes(query) ||
        (d.ipAddress || '').toLowerCase().includes(query)
      );
    })
    .sort((a, b) => {
      if (a.status === 'ONLINE' && b.status !== 'ONLINE') return -1;
      if (a.status !== 'ONLINE' && b.status === 'ONLINE') return 1;
      return 0;
    });

  const getStatusConfig = (statusStr) => {
    const statusUpper = (statusStr || 'OFFLINE').toUpperCase();
    let statusColor = '#64748b';
    let statusBg = '#f1f5f9';
    let statusBorder = '#cbd5e1';
    let statusText = 'OFFLINE';
    let dotColor = '#64748b';

    if (statusUpper === 'ONLINE' || statusUpper === 'ACTIVE') {
      statusColor = '#047857';
      statusBg = '#ecfdf5';
      statusBorder = '#a7f3d0';
      statusText = 'ONLINE';
      dotColor = '#10b981';
    } else if (statusUpper === 'IDLE' || statusUpper === 'SYSTEM IDLE') {
      statusColor = '#d97706';
      statusBg = '#fffbeb';
      statusBorder = '#fde68a';
      statusText = 'IDLE';
      dotColor = '#f59e0b';
    } else if (statusUpper === 'BREAK' || statusUpper === 'ON BREAK') {
      statusColor = '#b45309';
      statusBg = '#fffbeb';
      statusBorder = '#fde68a';
      statusText = 'ON BREAK';
      dotColor = '#f59e0b';
    } else if (statusUpper === 'PAUSED' || statusUpper === 'PAUSE') {
      statusColor = '#1d4ed8';
      statusBg = '#eff6ff';
      statusBorder = '#bfdbfe';
      statusText = 'PAUSED';
      dotColor = '#3b82f6';
    } else if (statusUpper === 'MEETING' || statusUpper === 'IN MEETING') {
      statusColor = '#7e22ce';
      statusBg = '#faf5ff';
      statusBorder = '#e9d5ff';
      statusText = 'IN MEETING';
      dotColor = '#a855f7';
    } else if (statusUpper === 'LOGGED_OUT' || statusUpper === 'LOGOUT') {
      statusText = 'LOGGED OUT';
    }

    return { statusColor, statusBg, statusBorder, statusText, dotColor };
  };

  return (
    <div className="glass-panel" style={{ padding: '24px', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '16px' }}>
      {/* Header Bar Controls */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px', marginBottom: '24px' }}>
        <div>
          <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: '#0f172a', letterSpacing: '-0.01em' }}>
            EktaHR Office LAN Devices ({devices.length})
          </h2>
          <p style={{ color: '#64748b', fontSize: '0.85rem', marginTop: '2px' }}>
            Active employee computers monitored on local network
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          {/* Search Box */}
          <div style={{ position: 'relative', width: '220px' }}>
            <Search size={16} color="#94a3b8" style={{ position: 'absolute', left: '12px', top: '10px' }} />
            <input
              type="text"
              placeholder="Search PC or employee..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              style={{
                width: '100%',
                padding: '7px 12px 7px 36px',
                borderRadius: '8px',
                border: '1px solid #cbd5e1',
                fontSize: '0.85rem',
                outline: 'none',
                background: '#f8fafc',
                color: '#0f172a'
              }}
            />
          </div>

          {/* View Mode Toggle Switcher */}
          <div style={{ display: 'flex', background: '#f1f5f9', padding: '3px', borderRadius: '8px', border: '1px solid #e2e8f0' }}>
            <button
              onClick={() => setViewMode('LIST')}
              title="List View"
              style={{
                background: viewMode === 'LIST' ? '#ffffff' : 'transparent',
                color: viewMode === 'LIST' ? '#d97706' : '#64748b',
                border: 'none',
                padding: '6px 10px',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                fontWeight: 600,
                fontSize: '0.8rem',
                boxShadow: viewMode === 'LIST' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none'
              }}
            >
              <List size={16} />
              <span>List</span>
            </button>

            <button
              onClick={() => setViewMode('GRID')}
              title="Grid View"
              style={{
                background: viewMode === 'GRID' ? '#ffffff' : 'transparent',
                color: viewMode === 'GRID' ? '#d97706' : '#64748b',
                border: 'none',
                padding: '6px 10px',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                fontWeight: 600,
                fontSize: '0.8rem',
                boxShadow: viewMode === 'GRID' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none'
              }}
            >
              <LayoutGrid size={16} />
              <span>Grid</span>
            </button>
          </div>

          <button className="glass-button outline" onClick={onRefresh} style={{ padding: '7px 14px', fontSize: '0.85rem' }}>
            <RefreshCw size={15} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {sortedDevices.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px 20px', color: '#64748b' }}>
          <Monitor size={48} style={{ opacity: 0.4, marginBottom: '12px' }} />
          <p style={{ fontSize: '1.1rem', fontWeight: 500 }}>No matching EktaHR devices found.</p>
          <span style={{ fontSize: '0.85rem', color: '#94a3b8' }}>Ensure EktaHR-Agent.exe is running on employee PCs.</span>
        </div>
      ) : viewMode === 'LIST' ? (
        /* ==================== SLEEK LIST VIEW TABLE ==================== */
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'separate', borderSpacing: '0 8px' }}>
            <thead>
              <tr style={{ color: '#64748b', fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                <th style={{ padding: '8px 16px', textAlign: 'left' }}>Employee / Device</th>
                <th style={{ padding: '8px 16px', textAlign: 'left' }}>IP Address</th>
                <th style={{ padding: '8px 16px', textAlign: 'left' }}>Status</th>
                <th style={{ padding: '8px 16px', textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {sortedDevices.map((device) => {
                const isConnectable = device.status && device.status !== 'OFFLINE' && device.status !== 'LOGGED_OUT';
                const { statusColor, statusBg, statusBorder, statusText, dotColor } = getStatusConfig(device.status);
                const userInitial = (device.currentUser || 'E').charAt(0).toUpperCase();

                return (
                  <tr
                    key={device.deviceId}
                    style={{
                      background: isConnectable ? '#ffffff' : '#f8fafc',
                      border: isConnectable ? '1px solid #fde68a' : '1px solid #e2e8f0',
                      boxShadow: isConnectable ? '0 2px 8px rgba(245, 158, 11, 0.08)' : '0 1px 3px rgba(0,0,0,0.02)',
                      transition: 'all 0.15s ease'
                    }}
                  >
                    {/* Employee & Device Column */}
                    <td style={{ padding: '14px 16px', borderTopLeftRadius: '10px', borderBottomLeftRadius: '10px', borderLeft: isConnectable ? '4px solid #f59e0b' : '4px solid #cbd5e1' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                        <div style={{
                          width: '40px',
                          height: '40px',
                          borderRadius: '50%',
                          background: isConnectable ? '#fffbeb' : '#f1f5f9',
                          border: isConnectable ? '1px solid #fde68a' : '1px solid #e2e8f0',
                          color: isConnectable ? '#d97706' : '#64748b',
                          fontWeight: 700,
                          fontSize: '1rem',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center'
                        }}>
                          {userInitial}
                        </div>
                        <div>
                          <div style={{ fontWeight: 700, color: '#0f172a', fontSize: '0.95rem' }}>
                            {device.hostname || device.deviceId}
                          </div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: '#64748b', fontSize: '0.8rem', marginTop: '2px' }}>
                            <User size={13} color="#94a3b8" />
                            <span>{device.currentUser || 'EktaHR Employee'}</span>
                          </div>
                        </div>
                      </div>
                    </td>

                    {/* IP Column */}
                    <td style={{ padding: '14px 16px', color: '#475569', fontSize: '0.85rem' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <Wifi size={14} color="#64748b" />
                        <span>{device.ipAddress}</span>
                      </div>
                    </td>

                    {/* Status Column */}
                    <td style={{ padding: '14px 16px' }}>
                      <span style={{
                        padding: '4px 12px',
                        borderRadius: '20px',
                        fontSize: '0.75rem',
                        fontWeight: 700,
                        letterSpacing: '0.03em',
                        background: statusBg,
                        color: statusColor,
                        border: `1px solid ${statusBorder}`,
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px'
                      }}>
                        <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: dotColor }}></span>
                        {statusText}
                      </span>
                    </td>

                    {/* Actions Column */}
                    <td style={{ padding: '14px 16px', textAlign: 'right', borderTopRightRadius: '10px', borderBottomRightRadius: '10px' }}>
                      <div style={{ display: 'inline-flex', gap: '8px', justifyContent: 'flex-end' }}>
                        <button
                          className="glass-button"
                          disabled={!isConnectable}
                          onClick={() => isConnectable && onSelectDevice(device, 'VIEW_ONLY')}
                          title={isConnectable ? 'View Live Screen' : `Cannot view screen when status is ${statusText}`}
                          style={{
                            padding: '6px 14px',
                            fontSize: '0.8rem',
                            fontWeight: 600,
                            background: isConnectable ? 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)' : '#f1f5f9',
                            color: isConnectable ? '#ffffff' : '#94a3b8',
                            border: isConnectable ? '1px solid #2563eb' : '1px solid #cbd5e1',
                            boxShadow: isConnectable ? '0 2px 8px rgba(37, 99, 235, 0.25)' : 'none',
                            opacity: isConnectable ? 1 : 0.45,
                            cursor: isConnectable ? 'pointer' : 'not-allowed'
                          }}
                        >
                          <Eye size={14} />
                          <span>View Screen</span>
                        </button>

                        <button
                          className="glass-button secondary"
                          onClick={() => setActiveScreenshotDevice(device)}
                          title="View Historical Screenshots"
                          style={{
                            padding: '6px 12px',
                            fontSize: '0.8rem',
                            cursor: 'pointer',
                            background: '#f8fafc',
                            color: '#0f172a',
                            border: '1px solid #cbd5e1'
                          }}
                        >
                          <Camera size={14} />
                          <span>Screenshots</span>
                        </button>

                        <button
                          className="glass-button"
                          disabled={!isConnectable}
                          onClick={() => isConnectable && onSelectDevice(device, 'REMOTE_CONTROL')}
                          title={isConnectable ? 'Remote Access PC' : `Cannot remote access when status is ${statusText}`}
                          style={{
                            padding: '6px 12px',
                            fontSize: '0.8rem',
                            opacity: isConnectable ? 1 : 0.35,
                            cursor: isConnectable ? 'pointer' : 'not-allowed'
                          }}
                        >
                          <MousePointer size={14} />
                          <span>Remote Access</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : (
        /* ==================== GRID VIEW CARDS ==================== */
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(330px, 1fr))', gap: '18px' }}>
          {sortedDevices.map((device) => {
            const isConnectable = device.status && device.status !== 'OFFLINE' && device.status !== 'LOGGED_OUT';
            const isOnline = device.status === 'ONLINE';
            const { statusColor, statusBg, statusBorder, statusText, dotColor } = getStatusConfig(device.status);

            return (
              <div
                key={device.deviceId}
                style={{
                  background: isConnectable ? '#ffffff' : '#f8fafc',
                  border: isConnectable ? '1.5px solid #f59e0b' : '1px solid #e2e8f0',
                  borderRadius: '14px',
                  padding: '20px',
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                  transition: 'all 0.2s',
                  boxShadow: isConnectable ? '0 4px 20px rgba(245, 158, 11, 0.12)' : '0 2px 8px rgba(0, 0, 0, 0.03)'
                }}
              >
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <div style={{
                        width: '44px',
                        height: '44px',
                        borderRadius: '12px',
                        background: isConnectable ? '#fffbeb' : '#f1f5f9',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        color: isConnectable ? '#d97706' : '#64748b',
                        border: isConnectable ? '1px solid #fde68a' : '1px solid #e2e8f0'
                      }}>
                        <Monitor size={22} />
                      </div>
                      <div>
                        <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: '#0f172a' }}>
                          {device.hostname || device.deviceId}
                        </h4>
                        <span style={{ fontSize: '0.75rem', color: isConnectable ? '#d97706' : '#64748b', fontWeight: 600 }}>
                          {device.ipAddress}
                        </span>
                      </div>
                    </div>

                    <span style={{
                      padding: '5px 12px',
                      borderRadius: '20px',
                      fontSize: '0.725rem',
                      fontWeight: 700,
                      letterSpacing: '0.04em',
                      background: statusBg,
                      color: statusColor,
                      border: `1px solid ${statusBorder}`,
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '6px'
                    }}>
                      <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: dotColor }}></span>
                      {statusText}
                    </span>
                  </div>

                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '0.85rem', color: '#64748b', margin: '16px 0' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <User size={15} color="#d97706" />
                      <span>Employee: <strong style={{ color: '#0f172a', fontWeight: 600 }}>{device.currentUser || 'EktaHR Employee'}</strong></span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <Wifi size={15} color="#64748b" />
                      <span>LAN IP: <strong style={{ color: '#0f172a', fontWeight: 500 }}>{device.ipAddress}</strong></span>
                    </div>
                  </div>
                </div>

                <div style={{ display: 'flex', gap: '8px', marginTop: '14px' }}>
                  <button
                    className="glass-button"
                    disabled={!isConnectable}
                    onClick={() => isConnectable && onSelectDevice(device, 'VIEW_ONLY')}
                    title={isConnectable ? 'View Live Screen' : `Cannot view screen when status is ${statusText}`}
                    style={{
                      flex: 1,
                      justifyContent: 'center',
                      fontSize: '0.8rem',
                      fontWeight: 600,
                      background: isConnectable ? 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)' : '#f1f5f9',
                      color: isConnectable ? '#ffffff' : '#94a3b8',
                      border: isConnectable ? '1px solid #2563eb' : '1px solid #cbd5e1',
                      boxShadow: isConnectable ? '0 2px 8px rgba(37, 99, 235, 0.25)' : 'none',
                      opacity: isConnectable ? 1 : 0.45,
                      cursor: isConnectable ? 'pointer' : 'not-allowed'
                    }}
                  >
                    <Eye size={14} />
                    <span>Live</span>
                  </button>

                  <button
                    className="glass-button secondary"
                    onClick={() => setActiveScreenshotDevice(device)}
                    title="View Historical Screenshots"
                    style={{
                      flex: 1,
                      justifyContent: 'center',
                      fontSize: '0.8rem',
                      cursor: 'pointer',
                      background: '#f8fafc',
                      color: '#0f172a',
                      border: '1px solid #cbd5e1'
                    }}
                  >
                    <Camera size={14} />
                    <span>Snaps</span>
                  </button>

                  <button
                    className="glass-button"
                    disabled={!isConnectable}
                    onClick={() => isConnectable && onSelectDevice(device, 'REMOTE_CONTROL')}
                    title={isConnectable ? 'Remote Access PC' : `Cannot remote access when status is ${statusText}`}
                    style={{
                      flex: 1,
                      justifyContent: 'center',
                      fontSize: '0.8rem',
                      opacity: isConnectable ? 1 : 0.35,
                      cursor: isConnectable ? 'pointer' : 'not-allowed'
                    }}
                  >
                    <MousePointer size={14} />
                    <span>Remote</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ==================== SCREENSHOT HISTORY MODAL ==================== */}
      {activeScreenshotDevice && (
        <div style={{
          position: 'fixed',
          top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(15, 23, 42, 0.85)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 9999,
          padding: '20px'
        }}>
          <div style={{
            background: '#ffffff',
            borderRadius: '16px',
            width: '900px',
            maxWidth: '95vw',
            maxHeight: '90vh',
            display: 'flex',
            flexDirection: 'column',
            boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.25)',
            overflow: 'hidden'
          }}>
            {/* Modal Header */}
            <div style={{
              padding: '18px 24px',
              borderBottom: '1px solid #e2e8f0',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              background: '#f8fafc'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <Camera size={20} color="#f59e0b" />
                <div>
                  <h3 style={{ margin: 0, fontSize: '1.1rem', color: '#0f172a', fontWeight: 700 }}>
                    Screenshot History — {activeScreenshotDevice.hostname}
                  </h3>
                  <span style={{ fontSize: '0.8rem', color: '#64748b' }}>
                    User: {activeScreenshotDevice.currentUser || 'EktaHR User'} | IP: {activeScreenshotDevice.ipAddress}
                  </span>
                </div>
              </div>
              <button
                onClick={() => { setActiveScreenshotDevice(null); setPreviewImage(null); }}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  padding: '6px',
                  borderRadius: '50%',
                  color: '#64748b'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Modal Content */}
            <div style={{ padding: '24px', overflowY: 'auto', flex: 1 }}>
              {loadingSs ? (
                <div style={{ textAlign: 'center', padding: '40px', color: '#64748b' }}>
                  <span>Loading device screenshots...</span>
                </div>
              ) : screenshots.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '50px 20px', color: '#64748b' }}>
                  <Camera size={40} color="#cbd5e1" style={{ marginBottom: '12px' }} />
                  <p style={{ margin: 0, fontWeight: 600, fontSize: '1rem', color: '#334155' }}>No screenshots captured yet</p>
                  <p style={{ margin: '4px 0 0', fontSize: '0.85rem' }}>Screenshots are automatically captured every 5 minutes when device is active.</p>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))', gap: '16px' }}>
                  {screenshots.map((ss) => (
                    <div
                      key={ss.id || ss._id}
                      onClick={() => setPreviewImage(ss.imageBase64 || ss.secureUrl)}
                      style={{
                        border: '1px solid #e2e8f0',
                        borderRadius: '10px',
                        overflow: 'hidden',
                        cursor: 'pointer',
                        background: '#f8fafc',
                        transition: 'transform 0.15s, boxShadow 0.15s'
                      }}
                      onMouseEnter={(e) => { e.currentTarget.style.transform = 'scale(1.02)'; e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.1)'; }}
                      onMouseLeave={(e) => { e.currentTarget.style.transform = 'scale(1)'; e.currentTarget.style.boxShadow = 'none'; }}
                    >
                      <img
                        src={ss.imageBase64 || ss.secureUrl}
                        alt="Desktop Screenshot"
                        style={{ width: '100%', height: '145px', objectFit: 'cover', display: 'block' }}
                      />
                      <div style={{ padding: '10px 12px', fontSize: '0.78rem', color: '#475569', background: '#ffffff', borderTop: '1px solid #f1f5f9' }}>
                        <div style={{ fontWeight: 600, color: '#0f172a' }}>
                          {new Date(ss.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                        </div>
                        <div style={{ fontSize: '0.72rem', color: '#94a3b8' }}>
                          {new Date(ss.timestamp).toLocaleDateString()}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Full Preview Image Modal */}
      {previewImage && (
        <div
          onClick={() => setPreviewImage(null)}
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            background: 'rgba(0, 0, 0, 0.95)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 10000,
            padding: '20px'
          }}
        >
          {/* Top Bar with Close Button */}
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              position: 'absolute',
              top: '20px',
              right: '24px',
              display: 'flex',
              alignItems: 'center',
              gap: '12px',
              zIndex: 10001
            }}
          >
            <button
              onClick={() => setPreviewImage(null)}
              title="Close Screenshot View (ESC)"
              style={{
                background: 'rgba(239, 68, 68, 0.9)',
                color: '#ffffff',
                border: 'none',
                borderRadius: '8px',
                padding: '8px 16px',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                fontWeight: 700,
                fontSize: '0.9rem',
                cursor: 'pointer',
                boxShadow: '0 4px 14px rgba(239, 68, 68, 0.4)',
                transition: 'all 0.15s ease'
              }}
              onMouseEnter={(e) => { e.currentTarget.style.background = '#dc2626'; e.currentTarget.style.transform = 'scale(1.05)'; }}
              onMouseLeave={(e) => { e.currentTarget.style.background = 'rgba(239, 68, 68, 0.9)'; e.currentTarget.style.transform = 'scale(1)'; }}
            >
              <X size={18} />
              <span>Close View</span>
            </button>
          </div>

          <img
            src={previewImage}
            alt="Full Preview"
            onClick={(e) => e.stopPropagation()}
            style={{
              maxWidth: '92vw',
              maxHeight: '88vh',
              borderRadius: '12px',
              border: '1px solid rgba(255,255,255,0.15)',
              boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.7)'
            }}
          />
        </div>
      )}
    </div>
  );
}
