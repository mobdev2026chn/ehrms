EktaHR DMA - office LAN + online build (30 Oct 2026)
====================================================

Two stand-alone files. No folders, no setup, no install.

EktaHR-AdminConsole.exe  -> admin PC   (just copy this one file and run it)
EktaHR-Agent.exe         -> employee PCs (just copy this one file and run it)

What is new
- The admin sees every employee wherever they log in: in the office (LAN) or from
  home / any other network (Online).
- Live Devices has three buttons: All | LAN | Online. Each PC shows a LAN or ONLINE badge.
- View Screen and Remote Access work for both. Office PCs stream over the LAN;
  remote employees stream through the online server (smaller picture, for the internet).
- Activity Report, screenshots and idle alerts cover office and remote employees.

Before handing these out
- The online server (track.ektahr.com) must run the new DMA server with
  DMA_MODE=online and its own new JWT_SECRET (see dma/README.md). Until then
  everything still works on the office LAN, and remote employees are not shown.

Admin PC
- Replace the old EktaHR-AdminConsole.exe with this one, then RESTART the PC once.
  (The old built-in server keeps running until a restart, and the console would
  open that old one.)
- Run EktaHR-AdminConsole.exe. If no DMA server is on the network, this PC becomes
  the office server automatically. The new server unpacks itself the first time
  (~20 s) to %LOCALAPPDATA%\EktaHR DMA.
- Sign in with the EktaHR admin email and password. The console signs in to the
  online server with the same login. The "Network Mode" card says
  "Office LAN + Online" when both are connected.

Employee PCs
- Replace EktaHR-Agent.exe on EVERY employee PC (older agents never connect online).
- Run it and sign in. Sign-in only checks the email/password (a few seconds) - it
  does not search the office network. After sign-in the agent connects to the online
  server and, in the office, also finds the office server in the background; the PC
  then shows under LAN in the Admin Console (anywhere else: under Online).

Automatic updates (agent 1.1.0 in this folder and later)
- Copy this agent to every employee PC ONCE. From then on, new agent versions
  published on the server download by themselves and install at the next agent
  start / logout / exit (or Settings -> Update) - no more copying.
- Admin Console > Live Devices shows each PC's agent version; "old version" means
  that PC still needs this agent copied by hand.

Notes
- Do not run the agent from this folder and then hand the folder out: the agent
  saves config.json and daily_session_*.json next to itself.
- Screenshots/logs: %LOCALAPPDATA%\EktaHR DMA on the admin PC, and on the online
  server for every employee who reaches it.
- No database password on the admin PC; logins and staff list go through EktaHR.
- Agents on a different network/VLAN than the admin PC: put the admin PC's IP in a
  domain.txt next to EktaHR-Agent.exe (same as before).
- To keep one PC office-only, put an online.txt containing  off  next to
  EktaHR-Agent.exe.
