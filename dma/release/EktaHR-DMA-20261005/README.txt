EktaHR DMA - build 05 Oct 2026 (LAN only)
=========================================

EktaHR-Agent.exe         -> install on every EMPLOYEE PC
EktaHR-AdminConsole.exe  -> install on the ADMIN PC(s)

Both work ONLY on the office network, and only while the DMA server is running
on an office PC (dma/server, port 2005).

Install / update
1. Close the old app first (tray icon -> right-click -> Exit).
2. Replace the old .exe with the new one.
3. Put a domain.txt next to the .exe containing the DMA server PC's office IP,
   e.g.   192.168.0.25
   (Without it the app searches the office network, which is slower.)
4. Open the app and sign in with the EktaHR email and password.

How it finds the server
1. domain.txt next to the .exe (office IP)
2. Last server that worked
3. UDP broadcast on the office network (port 9002)
4. Scan of the office network (port 2005)
