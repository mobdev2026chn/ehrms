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

2. **`dma/agent` (single-file C# agent, `AgentSingle.cs` → `EktaHR-Agent.exe`)**:
   - GDI screen capture with JPEG frame compression (smaller frames over the online connection).
   - Win32 mouse and keyboard event injector for Remote Access.
   - Connects to the office LAN server (`ws://<server>:2005/agent`) and the online server, and registers computer name, IP and logged-in user.
   - `agent/publish/EktaHR-Agent.exe` is the copy the server offers at `/api/v1/download/agent`.

3. **`dma/admin_console` (React 18 + Vite Glassmorphism UI)**:
   - EktaHR Auth Login UI.
   - Real-time LAN Devices Grid showing online employee PCs.
   - Canvas Remote Viewer with **View Screen** and **Remote Access** modes.

---

## 🌐 Office LAN + Online

The admin sees an employee wherever they log in: on the office LAN **and** from any other network.

- **Two servers, same code.** The office LAN server runs on the admin's PC (`DMA_MODE=lan`, the default). The online server, `track.ektahr.com`, runs with `DMA_MODE=online` behind HTTPS.
- **Agent** keeps LAN detection and connects to the office LAN server when it finds one. It also connects to the online server from any network.
  - It tells the online server whether it is on the office LAN, which sets the PC's **LAN** or **Online** badge.
  - Screenshots go to the online server first and fall back to the office server.
  - An `online.txt` next to the exe overrides the online server URL; `off` keeps that PC LAN-only.
- **Admin Console** has **All / LAN / Online** buttons on Live Devices.
  - Served by an office LAN server, it also signs in to `ONLINE_SERVER_URL` (default `https://track.ektahr.com`) with the same login.
  - Office PCs live-stream directly over the LAN. Everyone else streams through the online server, at a reduced 1366 px width.
  - The Activity Report, screenshots and idle alerts come from the online server when the console is signed in to it.
- **Online server setup** (`server/.env`): `DMA_MODE=online` and a long random `JWT_SECRET`.
  - The server refuses to start with a missing or default secret.
  - In online mode, agents and viewers must send a valid DMA token.
  - The LAN guard and UDP discovery are off.
- **Every live view needs the admin's token.** On both servers, an admin only reaches their own company's PCs.

## 🔒 LAN-Only Mode (office LAN server)

- **Server** rejects HTTP / WebSocket / UDP-discovery traffic from non-private IPs (`LAN_ONLY=true` in `server/.env`, see `server/src/lanGuard.js`). It still needs *outbound* internet for MongoDB Atlas and EktaHR login.
- **Agent & Admin Console launcher** only look for the office server on private LAN addresses (10.x, 172.16–31.x, 192.168.x, localhost). The agent's online connection is separate (see above).
- Server discovery order: `domain.txt` next to the exe (e.g. `192.168.1.10` → `http://192.168.1.10:2005`) → saved `config.json` → UDP broadcast on port 9002 → subnet scan on port 2005.
- On the server PC, allow the ports on the **Private** network profile only:
  ```powershell
  New-NetFirewallRule -DisplayName "EktaDMA TCP 2005" -Direction Inbound -Protocol TCP -LocalPort 2005 -Profile Private -Action Allow
  New-NetFirewallRule -DisplayName "EktaDMA UDP 9002" -Direction Inbound -Protocol UDP -LocalPort 9002 -Profile Private -Action Allow
  ```
- Admins open the console at `http://<server-lan-ip>:2005`.
- Rebuild the agent (no .NET SDK needed):
  ```bash
  C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe -nologo -target:winexe -win32icon:ektaHr.ico -resource:ektaHr_icon_256.png,EktaHr.AppIcon.png -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:Microsoft.VisualBasic.dll -out:publish/EktaHR-Agent.exe AgentSingle.cs
  ```

## 🔄 Agent Auto-Update (agent 1.1.0 and later)

Employee PCs update themselves; only the first 1.1.0 agent has to be copied by hand.

**Releasing a new agent version**

1. In `agent/AgentSingle.cs`, raise `AgentVersion`, for example `"1.1.0"` → `"1.1.1"`. Every release needs a higher number.
2. Build it into `agent/publish/EktaHR-Agent.exe` with the `csc` command above.
3. Commit and push, then on the online server run `git pull`. No restart is needed: the server reads the version from the exe itself.

**What happens next**

- When an agent connects, the server compares the agent's version with the published exe. Already-connected PCs are checked again every 10 minutes.
- If the published exe is newer, the agent downloads it from `/api/v1/download/agent` in the background. It checks size, SHA-256 and version, and keeps the copy in `%LOCALAPPDATA%\EktaHR Agent\update`.
- It installs when nobody is working in it: at the next agent start, at logout, on Exit, or from **Settings → Update**.
- Older or same-version agents are never offered, so an office server built earlier can't downgrade a PC.
- If the exe's folder isn't writable (for example Program Files), the update waits.

**Notes**

- Agents from before 1.1.0 report no version and can't auto-update. The Admin Console marks them "Agent: old version — update by hand once".
- An office server (inside the Admin Console exe) offers the agent it was built with. Rebuild the Admin Console when you want office servers to carry the new agent too, though the online server alone is enough.

## ⚙️ Idle Time Setting (one place)

Set in `server/.env` only, then restart the server:

```
IDLE_THRESHOLD_SECONDS=300   # 300 = 5 min, 120 = 2 min, 600 = 10 min (allowed 30–7200)
```

No mouse/keyboard input for this long marks the employee IDLE (idle screenshot, idle badge, admin alert). The server sends the value to every agent at login and on each connect, so the agent exe does **not** need rebuilding; the admin console uses the server's `isIdle` flag. Code: `server/src/config.js`.

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

### 3. Start the Windows Agent
Build it with the `csc` command under **LAN-Only Mode**, then run `EktaHR-Agent.exe` on employee PCs and sign in to enable live screen viewing and remote access. Ready-made builds are in `dma/release/`.
