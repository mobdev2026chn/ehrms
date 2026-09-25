# EktaHR DMA - Desktop Monitoring & Remote Access

A dedicated, high-performance, LAN-only Live Desktop Streaming & Remote Access system located in `d:/Projects/ektaHr/dma`, authenticated directly with EktaHR credentials.

```
                    OFFICE LAN (d:/Projects/ektaHr/dma)
┌───────────────────────────────────────────────────────────────────────────┐
│                                                                           │
│   ┌──────────────────┐                            ┌──────────────────┐    │
│   │   EktaDMA Agent  │                            │   EktaDMA Agent  │    │
│   │ (C# / DXGI / WS) │                            │ (C# / DXGI / WS) │    │
│   └────────┬─────────┘                            └────────┬─────────┘    │
│            │                                               │              │
│            │ (1. Heartbeat & Live Screen Stream)           │              │
│            ▼                                               ▼              │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │              DMA Signaling Server (Node.js)                      │    │
│   │ • Auth against EktaHRMS Mongo/JWT  • WebSockets Stream Relay      │    │
│   └──────────────────────────────────┬───────────────────────────────┘    │
│                                      │                                    │
│                                      │ (2. Admin Viewer Auth & Remote)    │
│                                      ▼                                    │
│                           ┌────────────────────┐                          │
│                           │ Admin Web Console  │                          │
│                           │ (React / Vite UI)  │                          │
│                           └────────────────────┘                          │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 System Architecture

1. **`dma/server` (Node.js + WebSockets + EktaHR MongoDB)**:
   - Connects to EktaHR MongoDB database (`hrms-development`).
   - Authenticates EktaHR credentials (`JWT_SECRET=AEvaHRMS@123`).
   - Relays live JPEG screen streams and remote mouse/keyboard control events between Agent and Admin viewer.

2. **`dma/agent` (C# .NET 8 EktaDMAAgent)**:
   - DXGI GPU Screen Capturer with adaptive JPEG frame compression.
   - Win32 `user32.dll` `SendInput` mouse and keyboard event injector.
   - Connects to `ws://localhost:9000/agent` and auto-registers computer name, IP, and logged-in user.

3. **`dma/admin_console` (React 18 + Vite Glassmorphism UI)**:
   - EktaHR Auth Login UI.
   - Real-time LAN Devices Grid showing online employee PCs.
   - Canvas Remote Viewer with **View Screen** and **Remote Access** modes.

---

## 🔒 LAN-Only Mode

- **Server** rejects HTTP / WebSocket / UDP-discovery traffic from non-private IPs (`LAN_ONLY=true` in `server/.env`, see `server/src/lanGuard.js`). It still needs *outbound* internet for MongoDB Atlas and EktaHR login.
- **Agent & Admin Console launcher** only connect to private LAN addresses (10.x, 172.16–31.x, 192.168.x, localhost). There is no public fallback.
- Server discovery order: `domain.txt` next to the exe (e.g. `192.168.1.10` → `http://192.168.1.10:2005`) → saved `config.json` → UDP broadcast on port 9002 → subnet scan on port 2005.
- On the server PC, allow the ports on the **Private** network profile only:
  ```powershell
  New-NetFirewallRule -DisplayName "EktaDMA TCP 2005" -Direction Inbound -Protocol TCP -LocalPort 2005 -Profile Private -Action Allow
  New-NetFirewallRule -DisplayName "EktaDMA UDP 9002" -Direction Inbound -Protocol UDP -LocalPort 9002 -Profile Private -Action Allow
  ```
- Admins open the console at `http://<server-lan-ip>:2005`.
- Rebuild the agent (no .NET SDK needed):
  ```bash
  C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe -nologo -target:winexe -win32icon:ektaHr.ico -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:Microsoft.VisualBasic.dll -out:publish/EktaHR-Agent.exe AgentSingle.cs
  ```

## 🚀 How to Run

### 1. Start EktaDMA Server
```powershell
cd d:\Projects\ektaHr\dma\server
npm start
```
* Runs on `http://localhost:9000`

### 2. Start Admin Web Console
```powershell
cd d:\Projects\ektaHr\dma\admin_console
npm run dev
```
* Opens at `http://localhost:3000`
* Log in using your **EktaHR credentials** (or fallback admin login: `admin` / `admin123`).

### 3. Start C# Windows Agent
```powershell
cd d:\Projects\ektaHr\dma\agent
```
Run `EktaDMAAgent.exe` on employee PCs to auto-register and enable live screen viewing and remote access.
