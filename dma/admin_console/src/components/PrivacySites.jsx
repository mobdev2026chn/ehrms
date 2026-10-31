import React, { useState, useEffect } from 'react';
import { EyeOff, Plus, X, Save, RotateCcw, RefreshCw, CheckCircle2, AlertTriangle } from 'lucide-react';
import { isOnlineOrigin, hasSeparateOnlineServer, getOnlineToken, routeServer, getDataServer } from '../config';

// Personal websites / apps the agents paint over in screenshots and live view (server: privacySites.js).
// Read from the server that holds the console's data; saved to every DMA server the console is signed
// in to, since each PC takes the list from whichever server it reaches.

const card = { padding: '22px 24px', background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '16px' };
const MAX_SITES = 100;

async function request(server, method, body) {
  const res = await fetch(`${server.baseUrl}/api/v1/privacy-sites`, {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${server.token}` },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 404) throw new Error('this DMA server is older and has no personal-website list yet - update it first');
  if (!res.ok || data.success === false) throw new Error(data.error || `request failed (${res.status})`);
  return data;
}

function saveTargets() {
  const targets = [{ name: isOnlineOrigin() ? 'online server' : 'office server', ...routeServer('LAN') }];
  if (hasSeparateOnlineServer() && getOnlineToken()) targets.push({ name: 'online server', ...routeServer('ONLINE') });
  return targets;
}

// Same rules as the server (cleanSites): the agent gets the words '|'-separated and reads plain strings
function cleanWord(raw) {
  return String(raw || '').replace(/[|,"\\{}]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 40).trim();
}

export default function PrivacySites({ user }) {
  const isSuper = user?.role === 'SUPER_ADMIN';
  const [sites, setSites] = useState([]);
  const [saved, setSaved] = useState([]);
  const [source, setSource] = useState('');
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(''); // '' | 'loading' | 'saving'
  const [message, setMessage] = useState(null); // { kind: 'ok' | 'error', text }

  const apply = (data) => {
    setSites(data.sites || []);
    setSaved(data.sites || []);
    setSource(data.source || '');
  };

  const load = async () => {
    setBusy('loading');
    try {
      apply(await request(getDataServer(), 'GET'));
    } catch (e) {
      setMessage({ kind: 'error', text: `Could not load the list: ${e.message}.` });
    }
    setBusy('');
  };

  useEffect(() => { load(); }, []);

  const addWords = () => {
    const next = [...sites];
    for (const word of input.split(/[,\n]/).map(cleanWord)) {
      if (word.length >= 2 && next.length < MAX_SITES && !next.some(s => s.toLowerCase() === word.toLowerCase())) next.push(word);
    }
    setSites(next);
    setInput('');
  };

  // PUT (save) or DELETE (reset) on every server; says which ones did not take it
  const sendToAll = async (method) => {
    setBusy('saving');
    setMessage(null);
    const targets = saveTargets();
    const results = await Promise.allSettled(targets.map(t => request(t, method, method === 'PUT' ? { sites } : null)));
    const done = results.find(r => r.status === 'fulfilled');
    const failed = results.map((r, i) => r.status === 'rejected' ? `${targets[i].name}: ${r.reason.message}` : null).filter(Boolean);
    if (done) apply(done.value);
    if (!failed.length) {
      setMessage({ kind: 'ok', text: method === 'PUT' ? 'Saved. Connected PCs hide these sites from now on.' : 'Back to the default list. Connected PCs use it from now on.' });
    } else {
      setMessage({
        kind: 'error',
        text: done
          ? `Saved, except on the ${failed.join('; ')}. PCs that only reach that server keep the old list - save again later.`
          : `Not saved - ${failed.join('; ')}.`
      });
    }
    setBusy('');
  };

  const dirty = sites.length !== saved.length || sites.some((s, i) => s !== saved[i]);
  const canReset = source === 'company' || (isSuper && source === 'default');
  const sourceText = {
    company: "Your company's own list",
    default: isSuper ? 'Default list for every company without its own' : 'Default list',
    'built-in': 'Built-in list'
  }[source];

  return (
    <div style={card}>
      <h3 style={{ fontSize: '1.05rem', fontWeight: 700, color: '#0f172a', marginBottom: '6px', display: 'flex', alignItems: 'center', gap: '8px' }}>
        <EyeOff size={18} color="#d97706" /> Personal websites
      </h3>
      <p style={{ color: '#64748b', fontSize: '0.84rem', lineHeight: 1.5, marginBottom: '12px' }}>
        A browser tab whose title contains one of these words, or an app with it in its name (e.g. WhatsApp), is
        covered with "Personal content hidden" in screenshots and live view, and remote clicks and keys can't reach it.
      </p>
      {sourceText && <div style={{ fontSize: '0.78rem', color: '#94a3b8', marginBottom: '10px' }}>{sourceText}</div>}

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '14px', minHeight: '28px' }}>
        {busy === 'loading' && <span style={{ color: '#94a3b8', fontSize: '0.84rem' }}>Loading…</span>}
        {busy !== 'loading' && sites.length === 0 && (
          <span style={{ color: '#b45309', fontSize: '0.84rem' }}>Empty: nothing is hidden.</span>
        )}
        {sites.map(site => (
          <span key={site} style={{
            display: 'inline-flex', alignItems: 'center', gap: '4px', padding: '4px 6px 4px 10px', borderRadius: '999px',
            background: '#fffbeb', border: '1px solid #fde68a', color: '#92400e', fontSize: '0.82rem', fontWeight: 600
          }}>
            {site}
            <button
              type="button"
              title={`Remove ${site}`}
              disabled={!!busy}
              onClick={() => setSites(sites.filter(s => s !== site))}
              style={{ background: 'none', border: 'none', padding: '1px', cursor: 'pointer', color: '#b45309', display: 'flex' }}
            >
              <X size={13} />
            </button>
          </span>
        ))}
      </div>

      <div style={{ display: 'flex', gap: '8px', marginBottom: '14px' }}>
        <input
          type="text"
          value={input}
          placeholder="Add a website or app, e.g. Amazon"
          disabled={!!busy}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addWords(); } }}
          style={{ flex: 1, minWidth: 0, padding: '8px 10px', border: '1px solid #cbd5e1', borderRadius: '8px', fontSize: '0.86rem', background: '#f8fafc' }}
        />
        <button className="glass-button outline" disabled={!!busy || !input.trim()} onClick={addWords} style={{ padding: '8px 12px', fontSize: '0.85rem' }}>
          <Plus size={15} />
          <span>Add</span>
        </button>
      </div>

      <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
        <button
          onClick={() => sendToAll('PUT')}
          disabled={!!busy || !dirty}
          style={{
            padding: '8px 18px', fontSize: '0.88rem', fontWeight: 600, color: '#ffffff', border: 'none', borderRadius: '8px',
            background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)', cursor: busy || !dirty ? 'not-allowed' : 'pointer',
            display: 'inline-flex', alignItems: 'center', gap: '6px', opacity: busy || !dirty ? 0.6 : 1
          }}
        >
          {busy === 'saving' ? <RefreshCw size={15} className="spin" /> : <Save size={15} />}
          <span>{busy === 'saving' ? 'Saving...' : 'Save'}</span>
        </button>
        {dirty && (
          <button className="glass-button outline" disabled={!!busy} onClick={() => setSites(saved)} style={{ padding: '8px 14px', fontSize: '0.85rem' }}>
            <span>Undo changes</span>
          </button>
        )}
        {canReset && !dirty && (
          <button className="glass-button outline" disabled={!!busy} onClick={() => sendToAll('DELETE')} style={{ padding: '8px 14px', fontSize: '0.85rem' }}>
            <RotateCcw size={15} />
            <span>{isSuper ? 'Reset to built-in list' : 'Reset to default list'}</span>
          </button>
        )}
      </div>

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
  );
}
