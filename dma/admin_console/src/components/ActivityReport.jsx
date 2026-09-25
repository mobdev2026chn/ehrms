import React, { useState, useEffect, useCallback } from 'react';
import { CalendarDays, ChevronLeft, ChevronRight, Clock, Camera, Search, X, ArrowLeft, User, Coffee, RefreshCw } from 'lucide-react';
import { getServerBaseUrl } from '../config';

const OFFICE_TZ = 'Asia/Kolkata';

const todayKey = () => new Date().toLocaleDateString('en-CA', { timeZone: OFFICE_TZ });

const shiftDay = (day, delta) => {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const formatDuration = (sec) => {
  const s = Math.max(0, Math.round(sec || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
};

const formatTime = (iso) => iso
  ? new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', timeZone: OFFICE_TZ })
  : '—';

const formatDayLabel = (day) => new Date(`${day}T12:00:00Z`).toLocaleDateString([], {
  weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC'
});

const END_REASON_LABEL = {
  status_online: 'Back to work',
  status_break: 'Went on break',
  status_meeting: 'Joined meeting',
  status_paused: 'Paused',
  status_logged_out: 'Logged out',
  agent_disconnected: 'Agent disconnected',
  logged_in_elsewhere: 'Logged in elsewhere',
  server_restart: 'Server restarted'
};

// Screenshots are JPEG files on the DMA server; <img> can't send headers, so the admin token rides in the URL
const screenshotSrc = (ss) => {
  const token = localStorage.getItem('ektahr_token') || '';
  return `${getServerBaseUrl()}${ss.imageUrl}?token=${encodeURIComponent(token)}`;
};

async function apiGet(path) {
  const token = localStorage.getItem('ektahr_token') || '';
  const res = await fetch(`${getServerBaseUrl()}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await res.json();
  if (!res.ok || !data.success) throw new Error(data.error || 'Request failed');
  return data;
}

const cardStyle = { background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '12px', padding: '14px 16px' };

function StatCard({ icon, label, value, color }) {
  return (
    <div style={{ ...cardStyle, display: 'flex', alignItems: 'center', gap: '12px' }}>
      <div style={{ width: '40px', height: '40px', borderRadius: '10px', background: '#f8fafc', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'center', color }}>
        {icon}
      </div>
      <div>
        <div style={{ fontSize: '0.75rem', color: '#64748b', fontWeight: 500 }}>{label}</div>
        <div style={{ fontSize: '1.25rem', fontWeight: 700, color: '#0f172a' }}>{value}</div>
      </div>
    </div>
  );
}

function DatePicker({ date, onChange }) {
  const isToday = date >= todayKey();
  const btn = { background: '#ffffff', border: '1px solid #cbd5e1', borderRadius: '8px', padding: '6px 8px', cursor: 'pointer', display: 'flex', alignItems: 'center', color: '#334155' };
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
      <button style={btn} onClick={() => onChange(shiftDay(date, -1))} title="Previous day"><ChevronLeft size={16} /></button>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
        <CalendarDays size={15} color="#d97706" style={{ position: 'absolute', left: '10px', pointerEvents: 'none' }} />
        <input
          type="date"
          value={date}
          max={todayKey()}
          onChange={(e) => e.target.value && onChange(e.target.value)}
          style={{ padding: '6px 10px 6px 32px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '0.85rem', color: '#0f172a', background: '#f8fafc' }}
        />
      </div>
      <button style={{ ...btn, opacity: isToday ? 0.4 : 1, cursor: isToday ? 'not-allowed' : 'pointer' }} disabled={isToday} onClick={() => onChange(shiftDay(date, 1))} title="Next day"><ChevronRight size={16} /></button>
      {!isToday && (
        <button style={{ ...btn, fontSize: '0.8rem', fontWeight: 600 }} onClick={() => onChange(todayKey())}>Today</button>
      )}
    </div>
  );
}

function EmployeeDetail({ employee, date, onDateChange, onBack }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [preview, setPreview] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    apiGet(`/api/v1/activity/employee?email=${encodeURIComponent(employee.userEmail)}&date=${date}`)
      .then(d => { if (!cancelled) setData(d); })
      .catch(e => { if (!cancelled) setError(e.message); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [employee.userEmail, date]);

  const totals = data?.totals || {};

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px', marginBottom: '20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <button className="glass-button outline" onClick={onBack} style={{ padding: '7px 12px', fontSize: '0.85rem' }}>
            <ArrowLeft size={15} /><span>All employees</span>
          </button>
          <div>
            <h2 style={{ fontSize: '1.2rem', fontWeight: 700, color: '#0f172a' }}>{employee.fullName}</h2>
            <span style={{ fontSize: '0.8rem', color: '#64748b' }}>{employee.userEmail}{employee.department ? ` · ${employee.department}` : ''}</span>
          </div>
        </div>
        <DatePicker date={date} onChange={onDateChange} />
      </div>

      {loading ? (
        <div style={{ textAlign: 'center', padding: '60px', color: '#64748b' }}>Loading activity for {formatDayLabel(date)}…</div>
      ) : error ? (
        <div style={{ textAlign: 'center', padding: '60px', color: '#dc2626' }}>{error}</div>
      ) : (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '14px', marginBottom: '22px' }}>
            <StatCard icon={<Coffee size={20} />} label="Total idle time" value={formatDuration(totals.totalIdleSec)} color="#d97706" />
            <StatCard icon={<Clock size={20} />} label="Idle periods" value={totals.idleCount || 0} color="#2563eb" />
            <StatCard icon={<Clock size={20} />} label="Longest idle" value={formatDuration(totals.longestIdleSec)} color="#7e22ce" />
            <StatCard icon={<Camera size={20} />} label="Screenshots" value={totals.screenshotCount || 0} color="#059669" />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(260px, 1fr) minmax(0, 2.4fr)', gap: '18px', alignItems: 'start' }} className="activity-detail-grid">
            {/* Idle periods */}
            <div style={cardStyle}>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700, color: '#0f172a', marginBottom: '12px' }}>Idle periods</h3>
              {data.idleLogs.length === 0 ? (
                <p style={{ color: '#94a3b8', fontSize: '0.85rem' }}>No idle time recorded on this day.</p>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  {data.idleLogs.map((l, i) => (
                    <div key={`${l.startAt}-${i}`} style={{ border: '1px solid #fde68a', background: '#fffbeb', borderRadius: '8px', padding: '8px 10px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', fontWeight: 600, color: '#0f172a' }}>
                        <span>{formatTime(l.startAt)} – {l.endAt ? formatTime(l.endAt) : 'now'}</span>
                        <span style={{ color: '#b45309' }}>{formatDuration(l.durationSec)}</span>
                      </div>
                      <div style={{ fontSize: '0.75rem', color: '#64748b', marginTop: '2px' }}>
                        {l.endAt ? (END_REASON_LABEL[l.endReason] || l.endReason) : 'Still idle'}{l.hostname ? ` · ${l.hostname}` : ''}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Screenshots */}
            <div style={cardStyle}>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700, color: '#0f172a', marginBottom: '12px' }}>Screenshots</h3>
              {data.screenshots.length === 0 ? (
                <p style={{ color: '#94a3b8', fontSize: '0.85rem' }}>No screenshots captured on this day.</p>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '12px' }}>
                  {data.screenshots.map(ss => (
                    <button
                      key={ss.id}
                      onClick={() => setPreview(ss)}
                      style={{ border: '1px solid #e2e8f0', borderRadius: '8px', overflow: 'hidden', padding: 0, background: '#f8fafc', cursor: 'zoom-in', textAlign: 'left' }}
                    >
                      <img src={screenshotSrc(ss)} alt={`Screenshot ${formatTime(ss.timestamp)}`} loading="lazy" style={{ width: '100%', aspectRatio: '16 / 9', objectFit: 'cover', display: 'block', background: '#e2e8f0' }} />
                      <div style={{ padding: '6px 8px', fontSize: '0.75rem', color: '#334155', display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ fontWeight: 600 }}>{formatTime(ss.timestamp)}</span>
                        <span style={{ color: '#94a3b8' }}>{ss.hostname}</span>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </>
      )}

      {preview && (
        <div onClick={() => setPreview(null)} style={{ position: 'fixed', inset: 0, background: 'rgba(15, 23, 42, 0.85)', zIndex: 1000, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
          <div style={{ color: '#ffffff', marginBottom: '10px', fontSize: '0.9rem', display: 'flex', gap: '16px', alignItems: 'center' }}>
            <span>{employee.fullName} · {formatDayLabel(date)} · {formatTime(preview.timestamp)} · {preview.hostname}</span>
            <X size={20} style={{ cursor: 'pointer' }} />
          </div>
          <img src={screenshotSrc(preview)} alt="Screenshot preview" style={{ maxWidth: '100%', maxHeight: '85vh', borderRadius: '8px', boxShadow: '0 10px 40px rgba(0,0,0,0.4)' }} />
        </div>
      )}
    </div>
  );
}

export default function ActivityReport() {
  const [date, setDate] = useState(todayKey);
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState(null);

  const load = useCallback(() => {
    setLoading(true);
    setError('');
    apiGet(`/api/v1/activity/summary?date=${date}`)
      .then(d => setEmployees(d.employees || []))
      .catch(e => setError(e.message))
      .finally(() => setLoading(false));
  }, [date]);

  useEffect(() => { if (!selected) load(); }, [load, selected]);

  if (selected) {
    return (
      <div className="glass-panel" style={{ padding: '24px', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '16px' }}>
        <EmployeeDetail employee={selected} date={date} onDateChange={setDate} onBack={() => setSelected(null)} />
      </div>
    );
  }

  const q = search.trim().toLowerCase();
  const rows = employees.filter(e => !q || e.fullName.toLowerCase().includes(q) || e.userEmail.includes(q) || (e.department || '').toLowerCase().includes(q));
  const withActivity = employees.filter(e => e.screenshotCount > 0 || e.idleCount > 0).length;
  const totalIdle = employees.reduce((s, e) => s + e.totalIdleSec, 0);

  const th = { padding: '8px 14px', textAlign: 'left', fontSize: '0.72rem', fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.05em' };
  const td = { padding: '12px 14px', fontSize: '0.85rem', color: '#334155', borderTop: '1px solid #f1f5f9' };

  return (
    <div className="glass-panel" style={{ padding: '24px', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '14px', marginBottom: '20px' }}>
        <div>
          <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: '#0f172a' }}>Employee Activity — {formatDayLabel(date)}</h2>
          <p style={{ color: '#64748b', fontSize: '0.85rem', marginTop: '2px' }}>
            {withActivity} of {employees.length} employees active · {formatDuration(totalIdle)} total idle time
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', width: '200px' }}>
            <Search size={15} color="#94a3b8" style={{ position: 'absolute', left: '10px', top: '9px' }} />
            <input
              type="text"
              placeholder="Search employee…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ width: '100%', padding: '7px 10px 7px 32px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '0.85rem', background: '#f8fafc', color: '#0f172a' }}
            />
          </div>
          <DatePicker date={date} onChange={setDate} />
          <button className="glass-button outline" onClick={load} style={{ padding: '7px 12px', fontSize: '0.85rem' }}>
            <RefreshCw size={15} /><span>Refresh</span>
          </button>
        </div>
      </div>

      {loading ? (
        <div style={{ textAlign: 'center', padding: '60px', color: '#64748b' }}>Loading activity…</div>
      ) : error ? (
        <div style={{ textAlign: 'center', padding: '60px', color: '#dc2626' }}>{error}</div>
      ) : rows.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px', color: '#64748b' }}>No employees found.</div>
      ) : (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th style={th}>Employee</th>
                <th style={th}>First / last capture</th>
                <th style={th}>Idle time</th>
                <th style={th}>Idle periods</th>
                <th style={th}>Longest idle</th>
                <th style={th}>Screenshots</th>
                <th style={{ ...th, textAlign: 'right' }}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map(e => {
                const hasData = e.screenshotCount > 0 || e.idleCount > 0;
                return (
                  <tr key={e.userEmail} style={{ opacity: hasData ? 1 : 0.55 }}>
                    <td style={td}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                        <div style={{ width: '34px', height: '34px', borderRadius: '50%', background: '#fffbeb', border: '1px solid #fde68a', color: '#d97706', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative' }}>
                          {(e.fullName || 'E').charAt(0).toUpperCase()}
                          {e.online && <span title="Online now" style={{ position: 'absolute', right: '-1px', bottom: '-1px', width: '10px', height: '10px', borderRadius: '50%', background: '#10b981', border: '2px solid #ffffff' }} />}
                        </div>
                        <div>
                          <div style={{ fontWeight: 700, color: '#0f172a' }}>{e.fullName}</div>
                          <div style={{ fontSize: '0.75rem', color: '#64748b' }}>{e.userEmail}{e.department ? ` · ${e.department}` : ''}</div>
                        </div>
                      </div>
                    </td>
                    <td style={td}>{e.firstActivityAt ? `${formatTime(e.firstActivityAt)} – ${formatTime(e.lastActivityAt)}` : '—'}</td>
                    <td style={{ ...td, fontWeight: 700, color: e.totalIdleSec > 3600 ? '#b45309' : '#0f172a' }}>{formatDuration(e.totalIdleSec)}</td>
                    <td style={td}>{e.idleCount}</td>
                    <td style={td}>{e.longestIdleSec ? formatDuration(e.longestIdleSec) : '—'}</td>
                    <td style={td}>{e.screenshotCount}</td>
                    <td style={{ ...td, textAlign: 'right' }}>
                      <button
                        className="glass-button"
                        onClick={() => setSelected(e)}
                        style={{ padding: '6px 12px', fontSize: '0.8rem', background: 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)', color: '#ffffff', border: '1px solid #2563eb' }}
                      >
                        <User size={14} /><span>View activity</span>
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
