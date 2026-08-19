import React, { useEffect, useRef, useState } from 'react';
import { X, Eye, MousePointer, Maximize2, ShieldAlert, Scaling } from 'lucide-react';
import { getServerWsUrl } from '../config';

export default function RemoteViewer({ device, initialMode, onClose }) {
  const [controlMode, setControlMode] = useState(initialMode); // 'VIEW_ONLY' or 'REMOTE_CONTROL'
  const [fitMode, setFitMode] = useState('CONTAIN'); // 'CONTAIN' (Full Complete PC View) or 'FILL' (Stretch Width)
  const [status, setStatus] = useState('Connecting to LAN Stream...');
  const [resolution, setResolution] = useState({ width: 1920, height: 1080 });
  const [error, setError] = useState('');
  const [isFullscreen, setIsFullscreen] = useState(false);

  const canvasRef = useRef(null);
  const wsRef = useRef(null);
  const containerRef = useRef(null);
  const lastMoveTimeRef = useRef(0);

  useEffect(() => {
    const baseWsUrl = getServerWsUrl();
    const wsUrl = `${baseWsUrl}/viewer?targetDeviceId=${encodeURIComponent(device.deviceId)}`;
    console.log(`[Viewer] Connecting to WebSocket: ${wsUrl}`);
    setStatus(`Connecting to ${device.hostname} (${device.ipAddress})...`);

    const ws = new WebSocket(wsUrl);
    ws.binaryType = 'arraybuffer';
    wsRef.current = ws;

    ws.onopen = () => {
      setStatus(`Live Stream Active on ${device.hostname}`);
      setError('');
    };

    ws.onmessage = (event) => {
      if (typeof event.data === 'string') {
        try {
          const data = JSON.parse(event.data);
          if (data.type === 'RESOLUTION_INFO') {
            setResolution({ width: data.width || 1920, height: data.height || 1080 });
          } else if (data.type === 'AGENT_NOT_CONNECTED') {
            setError(`EktaDMA Agent on ${device.hostname} is not responding.`);
          } else if (data.type === 'AGENT_OFFLINE') {
            setError(`Agent on ${device.hostname} went offline.`);
          }
        } catch (e) {}
      } else if (event.data instanceof ArrayBuffer || event.data instanceof Blob) {
        const blob = event.data instanceof Blob ? event.data : new Blob([event.data], { type: 'image/jpeg' });
        
        if (window.createImageBitmap) {
          createImageBitmap(blob).then((bitmap) => {
            const canvas = canvasRef.current;
            if (canvas) {
              if (bitmap.width && bitmap.height && (canvas.width !== bitmap.width || canvas.height !== bitmap.height)) {
                canvas.width = bitmap.width;
                canvas.height = bitmap.height;
                setResolution({ width: bitmap.width, height: bitmap.height });
              }
              const ctx = canvas.getContext('2d');
              if (ctx) {
                ctx.imageSmoothingEnabled = false;
                ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
              }
            }
            bitmap.close();
          }).catch(() => {});
        } else {
          const url = URL.createObjectURL(blob);
          const img = new Image();
          img.onload = () => {
            const canvas = canvasRef.current;
            if (canvas) {
              if (img.width && img.height && (canvas.width !== img.width || canvas.height !== img.height)) {
                canvas.width = img.width;
                canvas.height = img.height;
                setResolution({ width: img.width, height: img.height });
              }
              const ctx = canvas.getContext('2d');
              if (ctx) {
                ctx.imageSmoothingEnabled = false;
                ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
              }
            }
            URL.revokeObjectURL(url);
          };
          img.src = url;
        }
      }
    };

    ws.onerror = () => {
      setError('WebSocket connection error. Verify EktaDMA server status.');
    };

    ws.onclose = () => {
      setStatus('Disconnected');
    };

    return () => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    };
  }, [device]);

  // Global Keyboard Listener for Remote Control Mode
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (controlMode !== 'REMOTE_CONTROL') return;
      if (['F5', 'F12', 'Tab'].includes(e.key)) e.preventDefault();
      sendInputEvent({
        eventType: 'KEY_DOWN',
        key: e.key,
        vk: e.keyCode
      });
    };

    const handleKeyUp = (e) => {
      if (controlMode !== 'REMOTE_CONTROL') return;
      sendInputEvent({
        eventType: 'KEY_UP',
        key: e.key,
        vk: e.keyCode
      });
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [controlMode]);

  const sendInputEvent = (evtData) => {
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'INPUT_EVENT',
        ...evtData
      }));
    }
  };

  // High-Precision Pixel-Perfect Coordinate Matrix Normalization
  const getNormalizedCoords = (e) => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };

    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return { x: 0, y: 0 };

    if (fitMode === 'FILL') {
      const scaleX = resolution.width / rect.width;
      const scaleY = resolution.height / rect.height;
      const x = Math.round(Math.max(0, Math.min(resolution.width, (e.clientX - rect.left) * scaleX)));
      const y = Math.round(Math.max(0, Math.min(resolution.height, (e.clientY - rect.top) * scaleY)));
      return { x, y };
    }

    // Aspect Ratio Contain Mode with Letterbox Calculation
    const containerAspect = rect.width / rect.height;
    const imageAspect = resolution.width / resolution.height;

    let renderWidth = rect.width;
    let renderHeight = rect.height;
    let offsetX = 0;
    let offsetY = 0;

    if (containerAspect > imageAspect) {
      // Horizontal Black Bars
      renderWidth = rect.height * imageAspect;
      offsetX = (rect.width - renderWidth) / 2;
    } else {
      // Vertical Black Bars
      renderHeight = rect.width / imageAspect;
      offsetY = (rect.height - renderHeight) / 2;
    }

    const clientXRel = e.clientX - rect.left - offsetX;
    const clientYRel = e.clientY - rect.top - offsetY;

    const x = Math.round(Math.max(0, Math.min(resolution.width, (clientXRel / renderWidth) * resolution.width)));
    const y = Math.round(Math.max(0, Math.min(resolution.height, (clientYRel / renderHeight) * resolution.height)));

    return { x, y };
  };

  // High-Speed 60 FPS Throttled Mouse Movement
  const handleMouseMove = (e) => {
    if (controlMode !== 'REMOTE_CONTROL') return;
    const now = performance.now();
    if (now - lastMoveTimeRef.current < 16) return; // Cap at 60 FPS (16ms) to prevent network lag
    lastMoveTimeRef.current = now;

    const { x, y } = getNormalizedCoords(e);
    sendInputEvent({ eventType: 'MOUSE_MOVE', x, y });
  };

  const handleMouseDown = (e) => {
    if (controlMode !== 'REMOTE_CONTROL') return;
    e.preventDefault();
    const { x, y } = getNormalizedCoords(e);
    let button = 'LEFT';
    if (e.button === 2) button = 'RIGHT';
    if (e.button === 1) button = 'MIDDLE';

    sendInputEvent({
      eventType: 'MOUSE_CLICK',
      button,
      x,
      y,
      isDoubleClick: false
    });
  };

  const handleMouseUp = (e) => {
    if (controlMode !== 'REMOTE_CONTROL') return;
    const { x, y } = getNormalizedCoords(e);
    let button = 'LEFT';
    if (e.button === 2) button = 'RIGHT';
    if (e.button === 1) button = 'MIDDLE';

    sendInputEvent({
      eventType: 'MOUSE_UP',
      button,
      x,
      y
    });
  };

  const handleDoubleClick = (e) => {
    if (controlMode !== 'REMOTE_CONTROL') return;
    e.preventDefault();
    const { x, y } = getNormalizedCoords(e);
    sendInputEvent({
      eventType: 'MOUSE_CLICK',
      button: 'LEFT',
      x,
      y,
      isDoubleClick: true
    });
  };

  const handleWheel = (e) => {
    if (controlMode !== 'REMOTE_CONTROL') return;
    sendInputEvent({
      eventType: 'MOUSE_WHEEL',
      delta: e.deltaY < 0 ? 120 : -120
    });
  };

  const toggleFullscreen = () => {
    if (containerRef.current) {
      if (!document.fullscreenElement) {
        containerRef.current.requestFullscreen().then(() => setIsFullscreen(true)).catch(() => {});
      } else {
        document.exitFullscreen().then(() => setIsFullscreen(false)).catch(() => {});
      }
    }
  };

  const customAmberCursor = `url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><path d='M3 3l7 18 3-7 7-3L3 3z' fill='%23f59e0b' stroke='%23111827' stroke-width='1.5' stroke-linejoin='round'/></svg>") 0 0, pointer`;

  return (
    <div
      ref={containerRef}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        width: '100vw',
        height: '100vh',
        backgroundColor: '#000',
        display: 'flex',
        flexDirection: 'column',
        zIndex: 99999
      }}
    >
      {/* Floating Header Bar */}
      <div style={{
        height: '48px',
        background: 'rgba(15, 23, 42, 0.95)',
        borderBottom: '1px solid #1e293b',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 20px',
        boxShadow: '0 4px 20px rgba(0, 0, 0, 0.5)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
          <h3 style={{ fontSize: '0.95rem', fontWeight: 600, color: '#f8fafc' }}>
            🖥️ {device.hostname} ({device.currentUser || 'User'})
          </h3>
          <span style={{ fontSize: '0.75rem', color: '#38bdf8', background: 'rgba(56, 189, 248, 0.1)', padding: '2px 8px', borderRadius: '4px' }}>
            {device.ipAddress}
          </span>
          <span style={{ fontSize: '0.75rem', color: '#94a3b8' }}>
            {resolution.width}×{resolution.height}
          </span>
        </div>

        {/* Action Controls */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          {/* Fit Mode Toggle Button */}
          <button
            onClick={() => setFitMode(fitMode === 'CONTAIN' ? 'FILL' : 'CONTAIN')}
            title="Toggle Complete PC View vs Stretch Width"
            style={{
              padding: '6px 14px',
              borderRadius: '6px',
              border: fitMode === 'CONTAIN' ? '1px solid #34d399' : '1px solid #334155',
              background: fitMode === 'CONTAIN' ? 'rgba(52, 211, 153, 0.15)' : '#1e293b',
              color: fitMode === 'CONTAIN' ? '#34d399' : '#fff',
              fontSize: '0.85rem',
              fontWeight: 600,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px'
            }}
          >
            <Scaling size={15} color={fitMode === 'CONTAIN' ? '#34d399' : '#fff'} />
            <span>{fitMode === 'CONTAIN' ? 'Full PC View (Uncut)' : 'Stretch Width'}</span>
          </button>

          <button
            onClick={() => setControlMode('VIEW_ONLY')}
            style={{
              padding: '6px 14px',
              borderRadius: '6px',
              border: 'none',
              background: controlMode === 'VIEW_ONLY' ? '#2563eb' : '#1e293b',
              color: '#fff',
              fontSize: '0.85rem',
              fontWeight: 500,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px'
            }}
          >
            <Eye size={14} />
            <span>View Only</span>
          </button>

          <button
            onClick={() => setControlMode('REMOTE_CONTROL')}
            style={{
              padding: '6px 14px',
              borderRadius: '6px',
              border: 'none',
              background: controlMode === 'REMOTE_CONTROL' ? '#f59e0b' : '#1e293b',
              color: controlMode === 'REMOTE_CONTROL' ? '#000' : '#fff',
              fontWeight: controlMode === 'REMOTE_CONTROL' ? 700 : 500,
              fontSize: '0.85rem',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              boxShadow: controlMode === 'REMOTE_CONTROL' ? '0 0 12px rgba(245, 158, 11, 0.4)' : 'none'
            }}
          >
            <MousePointer size={14} color={controlMode === 'REMOTE_CONTROL' ? '#000' : '#fff'} />
            <span>Remote Access (Active Cursor)</span>
          </button>

          <button
            onClick={toggleFullscreen}
            title="Toggle Fullscreen"
            style={{
              padding: '6px 12px',
              borderRadius: '6px',
              border: '1px solid #334155',
              background: '#0f172a',
              color: '#fff',
              cursor: 'pointer'
            }}
          >
            <Maximize2 size={15} />
          </button>

          <button
            onClick={onClose}
            style={{
              padding: '6px 14px',
              borderRadius: '6px',
              border: 'none',
              background: '#991b1b',
              color: '#fff',
              fontSize: '0.85rem',
              fontWeight: 600,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px'
            }}
          >
            <X size={15} />
            <span>Close</span>
          </button>
        </div>
      </div>

      {/* Fullscreen Responsive Desktop Screen Viewport */}
      <div style={{
        flex: 1,
        width: '100vw',
        height: 'calc(100vh - 48px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#000',
        overflow: 'hidden'
      }}>
        {error ? (
          <div style={{
            textAlign: 'center',
            color: '#f43f5e',
            background: 'rgba(244, 63, 94, 0.1)',
            padding: '24px 36px',
            borderRadius: '12px',
            border: '1px solid rgba(244, 63, 94, 0.3)'
          }}>
            <ShieldAlert size={40} style={{ marginBottom: '12px' }} />
            <h4 style={{ fontSize: '1.2rem', marginBottom: '4px' }}>Session Disconnected</h4>
            <p style={{ color: '#cbd5e1', fontSize: '0.9rem' }}>{error}</p>
          </div>
        ) : (
          <canvas
            ref={canvasRef}
            width={resolution.width}
            height={resolution.height}
            onMouseMove={handleMouseMove}
            onMouseDown={handleMouseDown}
            onMouseUp={handleMouseUp}
            onDoubleClick={handleDoubleClick}
            onWheel={handleWheel}
            onContextMenu={(e) => e.preventDefault()}
            style={{
              width: fitMode === 'FILL' ? '100vw' : '100%',
              height: fitMode === 'FILL' ? 'calc(100vh - 48px)' : '100%',
              objectFit: fitMode === 'FILL' ? 'fill' : 'contain',
              maxWidth: fitMode === 'FILL' ? 'none' : '100%',
              maxHeight: fitMode === 'FILL' ? 'none' : '100%',
              imageRendering: 'crisp-edges',
              cursor: controlMode === 'REMOTE_CONTROL' ? customAmberCursor : 'default'
            }}
          />
        )}
      </div>
    </div>
  );
}
