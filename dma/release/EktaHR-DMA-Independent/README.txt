EktaHR DMA - independent single-file build (05 Oct 2026)
========================================================

Two stand-alone files. No folders, no setup, no install.

EktaHR-AdminConsole.exe  -> admin PC   (just copy this one file and run it)
EktaHR-Agent.exe         -> employee PCs (just copy this one file and run it)

Admin PC
- Run EktaHR-AdminConsole.exe.
- If no DMA server is on the network, this PC becomes the server automatically.
  The server is built into the exe; it unpacks itself the first time (~20 s) to
  %LOCALAPPDATA%\EktaHR DMA. First run only: click "Yes" on the Windows prompt so
  other PCs can reach this one.
- The portal opens; sign in with the EktaHR admin email and password.

Employee PCs
- Run EktaHR-Agent.exe and sign in. It finds the server automatically.

Notes
- Tracking runs while a DMA server is up (the admin PC is on).
- Screenshots/logs: %LOCALAPPDATA%\EktaHR DMA on the admin PC.
- No database password on the admin PC; logins and staff list go through EktaHR.
- Agents on a different network/VLAN than the admin PC: put the admin PC's IP in a
  domain.txt next to EktaHR-Agent.exe.
