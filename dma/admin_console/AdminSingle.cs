using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace EktaHR.AdminConsole
{
    static class Program
    {
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

        // LAN-only: no public default server — resolved from domain.txt / UDP discovery / subnet scan
        public static string ServerUrl = "";

        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072 | System.Net.SecurityProtocolType.Tls11 | System.Net.SecurityProtocolType.Tls;
                SetCurrentProcessExplicitAppUserModelID("EktaHR.AdminConsole.App");
            }
            catch { }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            LoadConfig();

            if (args != null && args.Length > 0)
            {
                foreach (string arg in args)
                {
                    if (arg.StartsWith("http://") || arg.StartsWith("https://"))
                    {
                        ServerUrl = arg.Trim();
                    }
                }
            }

            AutoDetectPort();

            // No DMA server on this LAN yet: this PC becomes it (bundled server next to the exe).
            if (string.IsNullOrEmpty(ServerUrl) && TryStartBundledServer())
            {
                ServerUrl = "http://127.0.0.1:2005";
            }

            if (string.IsNullOrEmpty(ServerUrl))
            {
                // Say why, so it can be fixed on the spot.
                string reason = string.IsNullOrEmpty(BundledServerProblem)
                    ? "No EktaHR DMA server found on this LAN."
                    : BundledServerProblem;
                MessageBox.Show(reason + "\n\nApp folder: " + AppDomain.CurrentDomain.BaseDirectory,
                    "EktaHR Admin Console", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            bool isNewInstance;
            using (System.Threading.Mutex mutex = new System.Threading.Mutex(true, "Global\\EktaHR_AdminConsole_SingleInstance_Mutex", out isNewInstance))
            {
                if (!isNewInstance)
                {
                    MessageBox.Show("EktaHR Admin Console is already running.", "EktaHR Admin Console", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                LaunchStandaloneEdgeApp(ServerUrl);
            }
        }

        // ================= BUNDLED LAN SERVER (this admin PC becomes the DMA server) =================
        // Layout next to the exe:  dma-server\node\node.exe,  dma-server\server\src\index.js,
        //                          dma-server\admin_console\dist (portal),  dma-server\agent\publish
        // The server holds no database credentials: logins and the staff list go through the
        // EktaHR backend with the user's own token. Screenshots/logs go to %LOCALAPPDATA%\EktaHR DMA.
        private static string DataDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EktaHR DMA"); }
        }

        /// Why the bundled server could not be started (shown to the admin), or null.
        private static string BundledServerProblem = null;

        // Version stamp of the embedded server payload. Bump it whenever the embedded zip changes
        // so the unpacked copy is refreshed on the next run.
        private const string ServerPayloadVersion = "2026.10.05.2";

        /// Returns the folder holding node\node.exe and server\src\index.js:
        ///  - a "dma-server" folder next to the exe, if one was shipped that way; else
        ///  - the server embedded in this exe, unpacked once to %LOCALAPPDATA%\EktaHR DMA\server-<ver>.
        /// Sets BundledServerProblem and returns null on failure.
        private static string ResolveServerRoot()
        {
            try
            {
                string beside = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "dma-server");
                if (File.Exists(Path.Combine(beside, "node", "node.exe"))) return beside;

                string target = Path.Combine(DataDir, "server-" + ServerPayloadVersion);
                string ready = Path.Combine(target, "ready.ok");
                if (File.Exists(ready)) return target;

                var asm = System.Reflection.Assembly.GetExecutingAssembly();
                using (Stream zip = asm.GetManifestResourceStream("EktaHR.DmaServer.zip"))
                {
                    if (zip == null)
                    {
                        BundledServerProblem = "This build has no embedded DMA server, and no \"dma-server\" folder is next to the exe.";
                        return null;
                    }
                    // Fresh unpack: clear any half-written earlier attempt.
                    try { if (Directory.Exists(target)) Directory.Delete(target, true); } catch { }
                    Directory.CreateDirectory(target);
                    string tmpZip = Path.Combine(DataDir, "server-payload.zip");
                    Directory.CreateDirectory(DataDir);
                    using (var fs = new FileStream(tmpZip, FileMode.Create, FileAccess.Write))
                    {
                        zip.CopyTo(fs);
                    }
                    System.IO.Compression.ZipFile.ExtractToDirectory(tmpZip, target);
                    try { File.Delete(tmpZip); } catch { }
                }
                File.WriteAllText(ready, DateTime.Now.ToString("s"));
                return target;
            }
            catch (Exception ex)
            {
                BundledServerProblem = "Could not unpack the DMA server: " + ex.Message;
                return null;
            }
        }

        private static bool TryStartBundledServer()
        {
            string logFile = Path.Combine(DataDir, "logs", "dma-server.log");
            try
            {
                // The server lives INSIDE this exe (unpacked once per version), so a single file is
                // enough. A "dma-server" folder next to the exe, if present, is used instead.
                string root = ResolveServerRoot();
                if (root == null) return false; // ResolveServerRoot set BundledServerProblem
                string nodeExe = Path.Combine(root, "node", "node.exe");
                string serverDir = Path.Combine(root, "server");
                if (!File.Exists(nodeExe) || !File.Exists(Path.Combine(serverDir, "src", "index.js")))
                {
                    BundledServerProblem = "The DMA server files are incomplete.\n\nFolder: " + root;
                    return false;
                }

                Directory.CreateDirectory(Path.Combine(DataDir, "logs"));
                Directory.CreateDirectory(Path.Combine(DataDir, "storage"));

                EnsureFirewallOnce(nodeExe);

                // cmd keeps the log redirection alive after this launcher exits (a redirected pipe
                // would close with the launcher and stop the server).
                var psi = new ProcessStartInfo("cmd.exe",
                    "/c \"\"" + nodeExe + "\" src\\index.js >> \"" + logFile + "\" 2>&1\"")
                {
                    WorkingDirectory = serverDir,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                psi.EnvironmentVariables["PORT"] = "2005";
                psi.EnvironmentVariables["LAN_ONLY"] = "true";
                psi.EnvironmentVariables["DMA_STORAGE_DIR"] = Path.Combine(DataDir, "storage");
                Process.Start(psi);

                // Wait for it to answer (first start of node can take a few seconds)
                for (int i = 0; i < 40; i++)
                {
                    System.Threading.Thread.Sleep(500);
                    if (PingHealthEndpointFast("http://127.0.0.1:2005")) return true;
                }
                BundledServerProblem = "This PC tried to start the DMA server but it did not answer." + LastLogLines(logFile);
            }
            catch (Exception ex)
            {
                BundledServerProblem = "This PC could not start the DMA server: " + ex.Message + LastLogLines(logFile);
            }
            return false;
        }

        // The end of the server log, for the error message (antivirus block, port in use, ...).
        private static string LastLogLines(string logFile)
        {
            try
            {
                if (!File.Exists(logFile)) return "\n\n(Antivirus may have blocked dma-server\\node\\node.exe.)";
                string[] lines = File.ReadAllLines(logFile);
                int from = Math.Max(0, lines.Length - 6);
                return "\n\nServer log (" + logFile + "):\n" + string.Join("\n", lines, from, lines.Length - from);
            }
            catch { return ""; }
        }

        // Once per PC: mark the office network Private and let other PCs reach the server
        // (TCP 2005 portal + live stream, UDP 9002 auto-discovery). Needs one UAC "Yes".
        private static void EnsureFirewallOnce(string nodeExe)
        {
            string marker = Path.Combine(DataDir, "firewall.ok");
            if (File.Exists(marker)) return;
            try
            {
                string script = Path.Combine(Path.GetTempPath(), "ektahr_dma_firewall.ps1");
                File.WriteAllText(script,
                    "$r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1\r\n" +
                    "if ($r) { Get-NetConnectionProfile -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private }\r\n" +
                    "Get-NetFirewallRule -DisplayName 'EktaDMA *' -ErrorAction SilentlyContinue | Remove-NetFirewallRule\r\n" +
                    "New-NetFirewallRule -DisplayName 'EktaDMA TCP 2005' -Direction Inbound -Protocol TCP -LocalPort 2005 -Profile Private,Domain -Action Allow | Out-Null\r\n" +
                    "New-NetFirewallRule -DisplayName 'EktaDMA UDP 9002' -Direction Inbound -Protocol UDP -LocalPort 9002 -Profile Private,Domain -Action Allow | Out-Null\r\n" +
                    "New-NetFirewallRule -DisplayName 'EktaDMA Server (node)' -Direction Inbound -Program '" + nodeExe.Replace("'", "''") + "' -Profile Private,Domain -Action Allow | Out-Null\r\n");
                var p = Process.Start(new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"")
                {
                    Verb = "runas",
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                });
                if (p != null)
                {
                    p.WaitForExit(60000);
                    if (p.HasExited && p.ExitCode == 0) File.WriteAllText(marker, DateTime.Now.ToString("s"));
                }
            }
            catch
            {
                // UAC declined: the server still runs for this PC; other PCs connect once allowed.
            }
        }

        private static void LaunchStandaloneEdgeApp(string url)
        {
            string edgePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe");
            if (!File.Exists(edgePath))
            {
                edgePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe");
            }
            if (!File.Exists(edgePath))
            {
                edgePath = "msedge.exe";
            }

            string userDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EktaHRAdminConsoleApp");

            // This private Edge profile may still hold the old (Flutter) favicon; drop its favicon cache so
            // the window / taskbar always shows the current EktaHR icon. Only this app's own profile is touched.
            foreach (string cacheFile in new[] { "Favicons", "Favicons-journal" })
            {
                try
                {
                    string cachePath = Path.Combine(userDataDir, "Default", cacheFile);
                    if (File.Exists(cachePath)) File.Delete(cachePath);
                }
                catch { }
            }
            string arguments = string.Format("--app=\"{0}\" --user-data-dir=\"{1}\" --start-maximized", url, userDataDir);

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo()
                {
                    FileName = edgePath,
                    Arguments = arguments,
                    UseShellExecute = true
                };
                Process.Start(psi);
            }
            catch { }
        }

        private static void LoadConfig()
        {
            try
            {
                string cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "domain.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "domain_config.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "admin_config.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "server_ip.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "server.txt");
                if (File.Exists(cfgFile))
                {
                    string text = File.ReadAllText(cfgFile).Trim().TrimEnd('/');
                    if (!string.IsNullOrEmpty(text))
                    {
                        if (!text.StartsWith("http://") && !text.StartsWith("https://")) text = "http://" + text;
                        if (!text.Substring(text.IndexOf("//") + 2).Contains(":") && text.StartsWith("http://")) text = text + ":2005";
                        if (IsLanUrl(text)) ServerUrl = text;
                    }
                }
            }
            catch { }
        }

        private static bool IsPrivateIp(IPAddress ip)
        {
            if (IPAddress.IsLoopback(ip)) return true;
            if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
            if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
            {
                byte[] v6 = ip.GetAddressBytes();
                return ip.IsIPv6LinkLocal || (v6[0] & 0xFE) == 0xFC;
            }
            byte[] b = ip.GetAddressBytes();
            return b[0] == 10 ||
                   (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
                   (b[0] == 192 && b[1] == 168) ||
                   (b[0] == 169 && b[1] == 254);
        }

        // True only if the URL's host is (or resolves exclusively to) a private LAN / loopback address
        private static bool IsLanUrl(string url)
        {
            try
            {
                if (string.IsNullOrEmpty(url)) return false;
                string host = new Uri(url.Trim()).Host;
                IPAddress parsed;
                if (IPAddress.TryParse(host.Trim('[', ']'), out parsed)) return IsPrivateIp(parsed);

                IPAddress[] resolved = Dns.GetHostAddresses(host);
                if (resolved.Length == 0) return false;
                foreach (IPAddress addr in resolved)
                {
                    if (!IsPrivateIp(addr)) return false;
                }
                return true;
            }
            catch { return false; }
        }

        private static string GetLocalIPAddress()
        {
            try
            {
                var host = System.Net.Dns.GetHostEntry(System.Net.Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        return ip.ToString();
                    }
                }
            }
            catch { }
            return "127.0.0.1";
        }

        private static string DiscoverViaUdpBroadcast()
        {
            try
            {
                using (var client = new System.Net.Sockets.UdpClient())
                {
                    client.EnableBroadcast = true;
                    client.Client.ReceiveTimeout = 400;
                    byte[] reqBytes = System.Text.Encoding.UTF8.GetBytes("EKTA_DISCOVER");
                    var targetEp = new System.Net.IPEndPoint(System.Net.IPAddress.Broadcast, 9002);
                    client.Send(reqBytes, reqBytes.Length, targetEp);

                    var remoteEp = new System.Net.IPEndPoint(System.Net.IPAddress.Any, 0);
                    byte[] respBytes = client.Receive(ref remoteEp);
                    string respStr = System.Text.Encoding.UTF8.GetString(respBytes).Trim();

                    if (respStr.StartsWith("EKTA_SERVER:"))
                    {
                        string portStr = respStr.Replace("EKTA_SERVER:", "").Trim();
                        string serverIp = remoteEp.Address.ToString();
                        return "http://" + serverIp + ":" + (string.IsNullOrEmpty(portStr) ? "2005" : portStr);
                    }
                }
            }
            catch { }
            return null;
        }

        private static bool PingHealthEndpointFast(string url)
        {
            if (string.IsNullOrEmpty(url) || !IsLanUrl(url)) return false;
            try
            {
                System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072 | System.Net.SecurityProtocolType.Tls11 | System.Net.SecurityProtocolType.Tls;
                System.Net.ServicePointManager.DefaultConnectionLimit = 500;
                System.Net.ServicePointManager.Expect100Continue = false;

                string targetUrl = url.TrimEnd('/');
                if (!targetUrl.EndsWith("/health") && !targetUrl.EndsWith("/api/v1/health"))
                {
                    targetUrl += "/api/v1/health";
                }

                var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(targetUrl);
                req.Timeout = 1500;
                req.ReadWriteTimeout = 1500;
                req.Method = "GET";
                using (var resp = (System.Net.HttpWebResponse)req.GetResponse())
                {
                    return resp.StatusCode == System.Net.HttpStatusCode.OK;
                }
            }
            catch
            {
                try
                {
                    var req2 = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url.TrimEnd('/') + "/health");
                    req2.Timeout = 1500;
                    req2.ReadWriteTimeout = 1500;
                    req2.Method = "GET";
                    using (var resp2 = (System.Net.HttpWebResponse)req2.GetResponse())
                    {
                        return resp2.StatusCode == System.Net.HttpStatusCode.OK;
                    }
                }
                catch
                {
                    return false;
                }
            }
        }

        private static string DiscoverActiveLanServerUrl()
        {
            // 1. Instant UDP Broadcast Discovery (10ms speed)
            string udpUrl = DiscoverViaUdpBroadcast();
            if (!string.IsNullOrEmpty(udpUrl) && PingHealthEndpointFast(udpUrl)) return udpUrl;

            // 2. Try loopbacks & cached config
            string localIp = GetLocalIPAddress();
            List<string> quickCandidates = new List<string>();

            if (!string.IsNullOrEmpty(ServerUrl)) quickCandidates.Add(ServerUrl);
            quickCandidates.Add("http://127.0.0.1:2005");
            quickCandidates.Add("http://localhost:2005");
            quickCandidates.Add("http://192.168.0.31:2005");
            quickCandidates.Add("http://192.168.1.31:2005");
            if (!string.IsNullOrEmpty(localIp)) quickCandidates.Add("http://" + localIp + ":2005");

            foreach (string candidate in quickCandidates)
            {
                if (PingHealthEndpointFast(candidate)) return candidate;
            }

            // 3. High-speed parallel LAN Subnet Auto-Scanner
            if (!string.IsNullOrEmpty(localIp) && localIp.Contains("."))
            {
                string subnetPrefix = localIp.Substring(0, localIp.LastIndexOf('.') + 1);
                string foundUrl = null;
                object lockObj = new object();

                System.Threading.Tasks.Parallel.For(1, 255, new System.Threading.Tasks.ParallelOptions { MaxDegreeOfParallelism = 100 }, i =>
                {
                    if (foundUrl != null) return;
                    string target = "http://" + subnetPrefix + i + ":2005";
                    if (PingHealthEndpointFast(target))
                    {
                        lock (lockObj)
                        {
                            if (foundUrl == null) foundUrl = target;
                        }
                    }
                });

                if (!string.IsNullOrEmpty(foundUrl)) return foundUrl;
            }

            return null;
        }

        private static void AutoDetectPort()
        {
            // 1. Keep configured LAN server URL if it is reachable
            if (!string.IsNullOrEmpty(ServerUrl) && PingHealthEndpointFast(ServerUrl))
            {
                return;
            }

            // 2. Try 127.0.0.1:2005 loopback ONLY if local server is active
            if (PingHealthEndpointFast("http://127.0.0.1:2005"))
            {
                ServerUrl = "http://127.0.0.1:2005";
                return;
            }

            // 3. Discover LAN active server
            string discovered = DiscoverActiveLanServerUrl();
            if (!string.IsNullOrEmpty(discovered))
            {
                ServerUrl = discovered;
                return;
            }

            // 4. LAN-only: no public fallback
            ServerUrl = "";
        }
    }
}
