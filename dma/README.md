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
