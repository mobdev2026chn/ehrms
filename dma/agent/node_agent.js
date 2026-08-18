const WebSocket = require('ws');
const os = require('os');
const screenshot = require('screenshot-desktop');

const hostname = os.hostname();
const username = os.userInfo().username;
const deviceId = `WIN-PC-${hostname.toUpperCase()}`;
const serverWsUrl = process.env.SERVER_WS_URL || 'ws://localhost:9000';

let isStreaming = false;
let streamInterval = null;

console.log('=======================================================');
console.log('  EKTA HR DMA - WINDOWS DESKTOP AGENT (ACTIVE)         ');
console.log('=======================================================');
console.log(`[Agent] Device ID:    ${deviceId}`);
console.log(`[Agent] Hostname:     ${hostname}`);
console.log(`[Agent] Logged User:  ${username}`);
console.log(`[Agent] Target Server:${serverWsUrl}`);

function connect() {
  const uri = `${serverWsUrl}/agent?deviceId=${encodeURIComponent(deviceId)}&hostname=${encodeURIComponent(hostname)}&user=${encodeURIComponent(username)}`;
  console.log(`[Agent] Connecting to ${uri}...`);

  const ws = new WebSocket(uri);

  ws.on('open', () => {
    console.log('[Agent] Connected successfully! Computer is ONLINE on Admin Dashboard.');
    
    // Heartbeat loop
    const hbInterval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'HEARTBEAT',
          hostname,
          currentUser: username
        }));
      }
    }, 4000);

    ws.on('close', () => {
      clearInterval(hbInterval);
      stopStreaming();
      console.log('[Agent] Connection lost. Reconnecting in 3s...');
      setTimeout(connect, 3000);
    });
  });

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      if (data.type === 'START_STREAM') {
        console.log('[Agent] Received START_STREAM request from Admin Console');
        startStreaming(ws);
      } else if (data.type === 'STOP_STREAM') {
        console.log('[Agent] Received STOP_STREAM request');
        stopStreaming();
      }
    } catch (e) {}
  });

  ws.on('error', (err) => {
    console.error('[Agent] WebSocket error:', err.message);
  });
}

function startStreaming(ws) {
  if (isStreaming) return;
  isStreaming = true;

  // Send resolution info
  ws.send(JSON.stringify({
    type: 'RESOLUTION_INFO',
    width: 1920,
    height: 1080
  }));

  console.log('[Agent] Capturing & streaming live desktop screen frames...');
  streamInterval = setInterval(async () => {
    if (!isStreaming || ws.readyState !== WebSocket.OPEN) return;

    try {
      const imgBuffer = await screenshot({ format: 'jpg' });
      if (imgBuffer && isStreaming && ws.readyState === WebSocket.OPEN) {
        ws.send(imgBuffer, { binary: true });
      }
    } catch (err) {
      console.error('[Agent] Capture frame error:', err.message);
    }
  }, 100); // ~10 FPS smooth stream
}

function stopStreaming() {
  isStreaming = false;
  if (streamInterval) {
    clearInterval(streamInterval);
    streamInterval = null;
  }
}

connect();
