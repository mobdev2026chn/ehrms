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

        public static string ServerUrl = "https://track.ektahr.com";

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
                    string text = File.ReadAllText(cfgFile).Trim();
                    if (!string.IsNullOrEmpty(text))
                    {
                        if (!text.StartsWith("http://") && !text.StartsWith("https://")) 
                        {
                            text = text.Contains(".") && !text.StartsWith("192.") && !text.StartsWith("127.")
                                ? "https://" + text 
                                : "http://" + text;
                        }
                        if (!text.Substring(text.IndexOf("//") + 2).Contains(":") && (text.Contains("127.0.0.1") || text.Contains("localhost")))
                        {
                            text = text + ":2005";
                        }
                        ServerUrl = text.TrimEnd('/');
                    }
                }
            }
            catch { }
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
            if (string.IsNullOrEmpty(url)) return false;
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
                    if (url.Contains("track.ektahr.com")) return true;
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
            quickCandidates.Add("https://track.ektahr.com");
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
            // 1. Always keep configured domain URL if present
            if (!string.IsNullOrEmpty(ServerUrl) && (ServerUrl.Contains("track.ektahr.com") || PingHealthEndpointFast(ServerUrl)))
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

            // 4. Default fallback to track.ektahr.com
            ServerUrl = "https://track.ektahr.com";
        }
    }
}
