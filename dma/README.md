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
- **Online server setup:** nothing to edit on the server. `"serverMode": "online"` in `dma.config.json` makes the server run from the repo (`track.ektahr.com`) the online server.
  - Without its own `JWT_SECRET` in `.env`, it creates a random one once in its storage folder (`server/storage/.jwt-secret`) and never uses the public default.
  - The office server inside the Admin Console always runs `lan`. A server's `.env` `DMA_MODE` overrides the config file.
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
- Build the exes with `dma/build.ps1`. No .NET SDK is needed; it uses the C# compiler that ships with Windows.
  ```powershell
  cd dma
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -AgentOnly   # agent only -> agent\publish + release\EktaHR-DMA-<today>
  powershell -ExecutionPolicy Bypass -File .\build.ps1              # agent + Admin Console (office server, console, Node packed inside)
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -AdminOnly   # Admin Console only, packing the published agent (agent\publish)
  ```
  - Versions and environment come from [`dma.config.json`](dma.config.json) (see **Release config** below).
  - `-Env development` builds another environment than the config file's; `-Release <folder name>` picks the release folder.
  - Each exe gets Windows file details (right-click → **Properties → Details**): description, version, and in **Comments** the environment, login service, online server and build time.

## 🚀 Release config: `dma.config.json`

Everything a release changes is in one file, [`dma.config.json`](dma.config.json):

```json
"environment": "production",            // production | development
"serverMode": "online",                 // the server run from the repo (track.ektahr.com) is the online server
"agentVersion": "1.2.1",                // raise for every new agent: 1.2.1 -> 1.2.2
"adminConsoleVersion": "2026.10.30.7",  // raise for every new Admin Console
"environments": { "production": { ... }, "development": { ... } }
```

**Release steps** (PowerShell, in the `dma` folder):

```powershell
# 1. edit dma.config.json (version / environment)
# 2. build
powershell -ExecutionPolicy Bypass -File .\build.ps1              # or: .\build.ps1 -AgentOnly
# 3. push
git add .
git commit -m "DMA: agent 1.2.1"
git push origin main
```

4. **Deploy:** on the online server, `cd <repo>; git pull --ff-only`. Restart the DMA app (`pm2 restart <dma-app>`) only when server code or the environment changed.
5. **Check:** `https://track.ektahr.com/api/v1/agent/latest` shows the new version, and the agent's **Settings → Update** offers it.

## 🌍 Environments: production / development

One switch picks the environment for the whole DMA. Its values live in `environments` in [`dma.config.json`](dma.config.json):

| | production | development |
|---|---|---|
| EktaHR login service (`hrmsApiUrl`) | `https://my.ektahr.com` | `https://uat.ektahr.com` |
| Online DMA server (`onlineServerUrl`) | `https://track.ektahr.com` | none: office LAN only, until you set up a test online server |
| `MONGODB_URI` / old `DEV_HRMS` database (`useDatabase`) | ignored | allowed (logins checked there first) |

**Where it is picked**

- **DMA server** (online server, or the repo server on a dev PC): `"environment"` in `dma.config.json`, so it changes with a push and `git pull` plus a restart.
  - To pin one server regardless of the file, set `DMA_ENV=production` (or `development`) in that server's `server/.env`.
  - The server prints `[Env] production (from dma.config.json)` at start, and `/api/v1/server-info` reports `env`.
  - The Admin Console shows a purple badge on non-production servers.
- **Agent and Admin Console exes:** `"environment"` in `dma.config.json`, or `build.ps1 -Env <name>` for a one-off.
  - The values are compiled into the agent (`BuildEnv`), and the office server inside the Admin Console gets `DMA_ENV=<env>`.
  - A development agent shows "1.2.0 (development)" in Settings.
  - Development builds go to `release\EktaHR-DMA-<date>-development` and never to `agent\publish`, so servers only ever hand out production agents.

To change a URL, edit `environments` in `dma.config.json`, then restart the servers and rebuild the exes.

## 🔄 Agent Auto-Update (agent 1.1.0 and later)

Employee PCs update themselves; only the first 1.1.0 agent has to be copied by hand.

**Releasing a new agent version**

1. In `dma.config.json`, raise `agentVersion`, for example `"1.2.0"` → `"1.2.1"`. Every release needs a higher number.
2. Build it: `powershell -ExecutionPolicy Bypass -File .\build.ps1 -AgentOnly`. This writes `agent/publish/EktaHR-Agent.exe`, the copy servers hand out.
3. Commit and push **after** building, then on the online server run `git pull`. No restart is needed: the server reads the version from the exe itself.

**What happens next**

- When an agent connects, the server compares the agent's version with the published exe. Already-connected PCs are checked again every 10 minutes.
- If the published exe is newer, the agent downloads it from `/api/v1/download/agent` in the background. It checks size, SHA-256 and version, and keeps the copy in `%LOCALAPPDATA%\EktaHR Agent\update`.
- It installs when nobody is working in it: at the next agent start, at logout, on Exit, or from **Settings → Update**.
- Older or same-version agents are never offered, so an office server built earlier can't downgrade a PC.
- If the exe's folder isn't writable (for example Program Files), the update waits.

**Checking for updates**

- **Employee:** Settings → **Update** asks the servers right away, downloads a newer agent and offers to install it. Otherwise it says "up to date".
- **Admin:** Live Devices shows each PC's agent version.
- **Anyone:** `https://track.ektahr.com/api/v1/agent/latest` shows the version the server is hosting.

**Notes**

- Agents from before 1.1.0 report no version and can't auto-update. The Admin Console marks them "Agent: old version — update by hand once".
- An office server (inside the Admin Console exe) offers the agent it was built with. Rebuild the Admin Console when you want office servers to carry the new agent too, though the online server alone is enough.

## 🔄 Admin Console Auto-Update (2026.10.31.1 and later) + Profile & Settings

The office server inside the Admin Console updates itself from the online server. Only the first self-updating version (`2026.10.31.1`) has to be copied by hand.

**Releasing a new Admin Console version**

1. In `dma.config.json`, raise `adminConsoleVersion`, for example `"2026.10.31.1"` → `"2026.11.05.1"`.
2. Build: `powershell -ExecutionPolicy Bypass -File .\build.ps1 -AdminOnly` (or without `-AdminOnly` to also build a new agent). This rebuilds `admin_console/dist` too.
3. Push, then on the online server run `git pull` and `pm2 restart <dma-app>`.

**What happens next**

- The online server hands out the release straight from its git checkout: `server/src`, `admin_console/dist`, the published agent and `dma.config.json`.
  - These routes are public, and `.env` is never included: `/api/v1/admin-console/latest`, `/manifest` and `/file`.
- Every office server checks every 30 minutes. When **Auto update** is on and no admin is watching a screen, it downloads only the changed files and sets them up as `%LOCALAPPDATA%\EktaHR DMA\server-<new version>`.
  - It reuses its Node, npm packages and `.env`, then restarts into the new version in about a second.
  - Admins stay signed in, and the console reloads.
- The Admin Console exe always starts the newest installed version. The version before is kept, and older ones are removed.
- A version that needs different npm packages (`server/package.json` dependencies) can't update this way. Settings shows a message, and the new Admin Console exe has to be copied by hand once.

**Profile & Settings tab** (also opened by clicking your name at the top right)

- **Profile:** name, email, role, environment, and which servers you're signed in to.
- **Admin Console:** version, latest version, **Auto update** switch, **Update** (install now) and **Check now**.
- On the online server's own console, the version is shown, with a note that it's updated by its deploy.

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
Build it with `build.ps1` (see **LAN-Only Mode**), then run `EktaHR-Agent.exe` on employee PCs and sign in to enable live screen viewing and remote access. Ready-made builds are in `dma/release/`.
