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

        public static string ServerUrl = "https://track.ektahr.com:2005";

        [STAThread]
        static void Main(string[] args)
        {
            try
            {
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

                Application.Run(new EktaAdminForm(ServerUrl));
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
                string cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "server_ip.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "admin_config.txt");
                if (!File.Exists(cfgFile)) cfgFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "server.txt");
                if (File.Exists(cfgFile))
                {
                    string text = File.ReadAllText(cfgFile).Trim();
                    if (!string.IsNullOrEmpty(text))
                    {
                        if (!text.StartsWith("http://") && !text.StartsWith("https://")) text = "http://" + text;
                        if (!text.Substring(text.IndexOf("//") + 2).Contains(":")) text = text + ":2005";
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
            try
            {
                System.Net.ServicePointManager.DefaultConnectionLimit = 500;
                System.Net.ServicePointManager.Expect100Continue = false;
                var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url.TrimEnd('/') + "/api/v1/health");
                req.Timeout = 600;
                req.ReadWriteTimeout = 600;
                req.Method = "GET";
                using (var resp = (System.Net.HttpWebResponse)req.GetResponse())
                {
                    return resp.StatusCode == System.Net.HttpStatusCode.OK;
                }
            }
            catch
            {
                return false;
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
            quickCandidates.Add("https://track.ektahr.com:2005");
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
            // 1. If ServerUrl configured and responding, keep it
            if (!string.IsNullOrEmpty(ServerUrl) && PingHealthEndpointFast(ServerUrl))
            {
                return;
            }

            // 2. Try 127.0.0.1:2005 loopback if local server is active
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
            if (string.IsNullOrEmpty(ServerUrl) || ServerUrl.Contains("127.0.0.1") || ServerUrl.Contains("localhost"))
            {
                ServerUrl = "https://track.ektahr.com:2005";
            }
        }
    }

    public class EktaAdminForm : Form
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        private const int GWL_STYLE = -16;
        private const int GWL_EXSTYLE = -20;
        private const int WS_VISIBLE = 0x10000000;
        private const int WS_CHILD = 0x40000000;
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_APPWINDOW = 0x00040000;
        private const int WM_SETICON = 0x80;
        private const int ICON_SMALL = 0;
        private const int ICON_BIG = 1;

        private Panel pnlBrowserHost;
        private Process browserProcess;
        private string targetUrl;

        public EktaAdminForm(string url)
        {
            targetUrl = url;
            InitializeComponent();
            Icon appIcon = ExtractAppIcon();
            if (appIcon != null)
            {
                this.Icon = appIcon;
                try
                {
                    SendMessage(this.Handle, WM_SETICON, (IntPtr)ICON_SMALL, appIcon.Handle);
                    SendMessage(this.Handle, WM_SETICON, (IntPtr)ICON_BIG, appIcon.Handle);
                }
                catch { }
            }
        }

        private Icon ExtractAppIcon()
        {
            try
            {
                string explicitIco = @"d:\Projects\ektaHr\dma\agent\publish\ektaHr.ico";
                if (File.Exists(explicitIco)) return new Icon(explicitIco);
                return Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                return SystemIcons.Application;
            }
        }

        private void InitializeComponent()
        {
            this.Text = "EktaHR DMA Admin Console";
            this.FormBorderStyle = FormBorderStyle.Sizable;
            this.Size = new Size(1360, 850);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(245, 247, 250);
            this.ShowInTaskbar = true;

            pnlBrowserHost = new Panel()
            {
                Dock = DockStyle.Fill,
                BackColor = Color.White
            };

            this.Controls.Add(pnlBrowserHost);
            this.Load += EktaAdminForm_Load;
            this.FormClosing += EktaAdminForm_FormClosing;
            this.Resize += EktaAdminForm_Resize;
        }

        private void EktaAdminForm_Load(object sender, EventArgs e)
        {
            LaunchAndEmbedBrowser();
        }

        private void LaunchAndEmbedBrowser()
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
            try
            {
                if (Directory.Exists(userDataDir)) Directory.Delete(userDataDir, true);
            }
            catch { }

            string arguments = string.Format("--app=\"{0}\" --user-data-dir=\"{1}\"", targetUrl, userDataDir);

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo()
                {
                    FileName = edgePath,
                    Arguments = arguments,
                    UseShellExecute = true
                };
                browserProcess = Process.Start(psi);

                // Wait for window handle and dock inside pnlBrowserHost
                Timer embedTimer = new Timer() { Interval = 150 };
                int attempts = 0;
                embedTimer.Tick += (s, ev) =>
                {
                    attempts++;
                    IntPtr hWnd = GetBrowserWindowHandle();
                    if (hWnd != IntPtr.Zero)
                    {
                        embedTimer.Stop();
                        embedTimer.Dispose();

                        // Strip inner window frame and remove child Edge window from taskbar
                        int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
                        SetWindowLong(hWnd, GWL_EXSTYLE, (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);

                        SetWindowLong(hWnd, GWL_STYLE, WS_CHILD | WS_VISIBLE);
                        SetParent(hWnd, pnlBrowserHost.Handle);
                        MoveWindow(hWnd, 0, 0, pnlBrowserHost.Width, pnlBrowserHost.Height, true);

                        Icon appIcon = ExtractAppIcon();
                        if (appIcon != null)
                        {
                            try
                            {
                                SendMessage(hWnd, WM_SETICON, (IntPtr)0, appIcon.Handle);
                                SendMessage(hWnd, WM_SETICON, (IntPtr)1, appIcon.Handle);
                                SendMessage(this.Handle, WM_SETICON, (IntPtr)0, appIcon.Handle);
                                SendMessage(this.Handle, WM_SETICON, (IntPtr)1, appIcon.Handle);
                            }
                            catch { }
                        }
                    }
                    else if (attempts > 40)
                    {
                        embedTimer.Stop();
                        embedTimer.Dispose();
                    }
                };
                embedTimer.Start();
            }
            catch { }
        }

        private IntPtr GetBrowserWindowHandle()
        {
            try
            {
                Process[] processes = Process.GetProcessesByName("msedge");
                foreach (Process p in processes)
                {
                    if (p.MainWindowHandle != IntPtr.Zero)
                    {
                        string title = p.MainWindowTitle;
                        if (!string.IsNullOrEmpty(title) && (title.Contains("EktaHR") || title.Contains("127.0.0.1") || title.Contains("localhost")))
                        {
                            return p.MainWindowHandle;
                        }
                    }
                }
            }
            catch { }
            return IntPtr.Zero;
        }

        private void EktaAdminForm_Resize(object sender, EventArgs e)
        {
            IntPtr hWnd = GetBrowserWindowHandle();
            if (hWnd != IntPtr.Zero && pnlBrowserHost != null)
            {
                MoveWindow(hWnd, 0, 0, pnlBrowserHost.Width, pnlBrowserHost.Height, true);
            }
        }

        private void EktaAdminForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            try
            {
                if (browserProcess != null && !browserProcess.HasExited)
                {
                    browserProcess.Kill();
                }
            }
            catch { }
        }
    }
}
