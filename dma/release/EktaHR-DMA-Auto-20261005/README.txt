EktaHR DMA - automatic LAN build (05 Oct 2026)
==============================================

No server setup needed. The PC where the admin opens the Admin Console becomes the DMA
server for that office network, and employee PCs on the same network connect to it by
themselves.

Admin\   -> copy the WHOLE folder to the admin PC (keep dma-server next to the exe)
            run EktaHR-AdminConsole.exe
Agent\   -> copy EktaHR-Agent.exe to every employee PC

What happens
1. Admin opens EktaHR-AdminConsole.exe
   - If a DMA server is already running on this network, it opens that one.
   - Otherwise this PC starts the bundled server (hidden) and opens the portal.
   - First time only: Windows asks "Yes" (UAC) to mark the office network Private and
     allow ports 2005/9002 so employee PCs can reach this PC.
2. Employees open EktaHR-Agent.exe and sign in - it finds the server automatically.
   If the connection drops (admin PC restarted, another admin PC took over) the agent
   finds the server again by itself - no new login needed.
3. Live Devices / Activity Report show the company's PCs.

Notes
- Tracking runs only while a DMA server is running on the network (the admin's PC is on).
- The server keeps running after the Admin Console window is closed, until the PC
  restarts or signs out; opening the Admin Console again starts it.
- Screenshots and logs: %LOCALAPPDATA%\EktaHR DMA on the admin PC.
- No database password on the admin PC: logins and the staff list go through EktaHR.
- PCs on a different network/VLAN than the admin PC: put the admin PC's IP in a
  domain.txt next to EktaHR-Agent.exe.
