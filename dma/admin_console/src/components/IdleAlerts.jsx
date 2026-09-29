import React, { useState, useEffect, useRef } from 'react';
import { Bell, Coffee, CheckCircle2, X, Eye } from 'lucide-react';
import { getServerBaseUrl } from '../config';

const POLL_MS = 4000;
const TOAST_MS = 10000;

const formatTime = (iso) => iso ? new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';

const formatDuration = (sec) => {
  const s = Math.max(0, Math.round(sec || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
};

// Short two-tone chime for new idle alerts (no audio file needed)
function playChime() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    [880, 660].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.15, ctx.currentTime + i * 0.18);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + i * 0.18 + 0.16);
      osc.connect(gain).connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.18);
      osc.stop(ctx.currentTime + i * 0.18 + 0.17);
    });
  } catch (e) {}
}

function alertText(a, name) {
  if (a.type === 'IDLE_START') {
    return { title: `${name} is idle`, body: `No mouse/keyboard activity since ${formatTime(a.idleSince)} on ${a.hostname}` };
  }
  return { title: `${name} is back`, body: `Active again after ${formatDuration(a.durationSec)} idle on ${a.hostname}` };
}

// Polls /api/v1/alerts and shows idle alerts as toasts, desktop notifications and a bell history.
// nameFor(email) -> display name; onView(alert) opens the live screen when the PC is connected.
export default function IdleAlerts({ token, nameFor, canView, onView }) {
  const [history, setHistory] = useState([]);
  const [toasts, setToasts] = useState([]);
  const [unread, setUnread] = useState(0);
  const [open, setOpen] = useState(false);
  const lastIdRef = useRef(null);
  const nameForRef = useRef(nameFor);
  nameForRef.current = nameFor;

  useEffect(() => {
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {});
    }
  }, []);

  useEffect(() => {
    if (!token) return undefined;
    let cancelled = false;

    const poll = async () => {
      try {
        const since = lastIdRef.current === null ? -1 : lastIdRef.current;
        const res = await fetch(`${getServerBaseUrl()}/api/v1/alerts?since=${since}`, {
          headers: { Authorization: `Bearer ${token}` }
        });
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled || !data.success) return;

        const incoming = data.alerts || [];
        if (lastIdRef.current === null) {
          // First load: fill the bell history without popping old alerts
          setHistory(incoming.slice().reverse());
        } else if (incoming.length > 0) {
          setHistory(prev => [...incoming.slice().reverse(), ...prev].slice(0, 100));
          setUnread(u => u + incoming.length);
          setToasts(prev => [...incoming.map(a => ({ ...a, shownAt: Date.now() })), ...prev].slice(0, 5));

          if (incoming.some(a => a.type === 'IDLE_START')) playChime();
          if ('Notification' in window && Notification.permission === 'granted') {
            incoming.forEach(a => {
              const { title, body } = alertText(a, nameForRef.current(a.userEmail));
              try { new Notification(title, { body, icon: '/icon-192.png', tag: `ektahr-${a.id}` }); } catch (e) {}
            });
          }
        }
        lastIdRef.current = data.latestId;
      } catch (e) {}
    };

    poll();
    const interval = setInterval(poll, POLL_MS);
    return () => { cancelled = true; clearInterval(interval); };
  }, [token]);

  // Auto-dismiss toasts
  useEffect(() => {
    if (toasts.length === 0) return undefined;
    const timer = setInterval(() => {
      setToasts(prev => prev.filter(t => Date.now() - t.shownAt < TOAST_MS));
    }, 1000);
    return () => clearInterval(timer);
  }, [toasts.length]);

  const renderItem = (a, compact) => {
    const name = nameFor(a.userEmail);
    const { title, body } = alertText(a, name);
    const isIdle = a.type === 'IDLE_START';
    return (
      <div style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
        <div style={{
          width: '32px', height: '32px', borderRadius: '50%', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: isIdle ? '#fffbeb' : '#ecfdf5', color: isIdle ? '#d97706' : '#059669', border: `1px solid ${isIdle ? '#fde68a' : '#a7f3d0'}`
        }}>
          {isIdle ? <Coffee size={16} /> : <CheckCircle2 size={16} />}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 700, fontSize: '0.85rem', color: '#0f172a' }}>{title}</div>
          <div style={{ fontSize: '0.78rem', color: '#64748b', marginTop: '2px' }}>{body}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '4px' }}>
            <span style={{ fontSize: '0.7rem', color: '#94a3b8' }}>{formatTime(a.at)}</span>
            {isIdle && canView(a) && (
              <button
                onClick={() => { onView(a); setOpen(false); }}
                style={{ border: 'none', background: 'none', color: '#2563eb', fontSize: '0.75rem', fontWeight: 600, cursor: 'pointer', padding: 0, display: 'inline-flex', alignItems: 'center', gap: '4px' }}
              >
                <Eye size={12} /> View screen
              </button>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <>
      {/* Bell + history dropdown */}
      <div style={{ position: 'relative' }}>
        <button
          onClick={() => { setOpen(o => !o); setUnread(0); }}
          title="Idle alerts"
          style={{ position: 'relative', background: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: '10px', width: '40px', height: '40px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: '#334155' }}
        >
          <Bell size={18} />
          {unread > 0 && (
            <span style={{ position: 'absolute', top: '-6px', right: '-6px', minWidth: '18px', height: '18px', padding: '0 5px', borderRadius: '9px', background: '#dc2626', color: '#ffffff', fontSize: '0.68rem', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {unread > 99 ? '99+' : unread}
            </span>
          )}
        </button>

        {open && (
          <div style={{ position: 'absolute', right: 0, top: '48px', width: '340px', maxHeight: '420px', overflowY: 'auto', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '12px', boxShadow: '0 12px 32px rgba(15, 23, 42, 0.15)', zIndex: 200 }}>
            <div style={{ padding: '12px 14px', borderBottom: '1px solid #f1f5f9', fontWeight: 700, fontSize: '0.9rem', color: '#0f172a' }}>Idle alerts</div>
            {history.length === 0 ? (
              <div style={{ padding: '24px 14px', color: '#94a3b8', fontSize: '0.85rem', textAlign: 'center' }}>No idle alerts yet.</div>
            ) : history.map(a => (
              <div key={a.id} style={{ padding: '10px 14px', borderBottom: '1px solid #f8fafc' }}>{renderItem(a)}</div>
            ))}
          </div>
        )}
      </div>

      {/* Toasts */}
      <div style={{ position: 'fixed', top: '100px', right: '20px', display: 'flex', flexDirection: 'column', gap: '10px', zIndex: 1000, width: '340px', maxWidth: 'calc(100vw - 32px)' }}>
        {toasts.map(t => (
          <div key={t.id} style={{
            background: '#ffffff', borderRadius: '12px', padding: '12px 14px', boxShadow: '0 10px 30px rgba(15, 23, 42, 0.18)',
            border: '1px solid #e2e8f0', borderLeft: `4px solid ${t.type === 'IDLE_START' ? '#f59e0b' : '#10b981'}`, position: 'relative'
          }}>
            <button onClick={() => setToasts(prev => prev.filter(x => x.id !== t.id))} style={{ position: 'absolute', top: '8px', right: '8px', border: 'none', background: 'none', cursor: 'pointer', color: '#94a3b8' }}>
              <X size={14} />
            </button>
            {renderItem(t)}
          </div>
        ))}
      </div>
    </>
  );
}
