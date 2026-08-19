using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;

namespace EktaDMAAgent.Services
{
    public class DxgiScreenCapturer : IDisposable
    {
        private readonly object _lock = new object();

        public Size PrimaryScreenBounds { get; private set; }

        public DxgiScreenCapturer()
        {
            Rectangle bounds = Screen.PrimaryScreen != null ? Screen.PrimaryScreen.Bounds : new Rectangle(0, 0, 1920, 1080);
            PrimaryScreenBounds = bounds.Size;
        }

        public byte[] CaptureScreenFrame(long jpegQualityLevel)
        {
            lock (_lock)
            {
                try
                {
                    Rectangle bounds = Screen.PrimaryScreen != null ? Screen.PrimaryScreen.Bounds : new Rectangle(0, 0, 1920, 1080);
                    PrimaryScreenBounds = bounds.Size;

                    using (Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb))
                    {
                        using (Graphics g = Graphics.FromImage(bitmap))
                        {
                            g.CopyFromScreen(bounds.X, bounds.Y, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
                            BlurSensitiveWindows(g, bitmap);
                        }

                        return CompressToJpeg(bitmap, jpegQualityLevel);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[DxgiScreenCapturer] Capture error: " + ex.Message);
                    return null;
                }
            }
        }

        private byte[] CompressToJpeg(Bitmap bmp, long quality)
        {
            ImageCodecInfo jpegEncoder = GetEncoderInfo(ImageFormat.Jpeg);
            if (jpegEncoder == null) return null;

            using (EncoderParameters encoderParams = new EncoderParameters(1))
            {
                encoderParams.Param[0] = new EncoderParameter(Encoder.Quality, quality);
                using (MemoryStream ms = new MemoryStream())
                {
                    bmp.Save(ms, jpegEncoder, encoderParams);
                    return ms.ToArray();
                }
            }
        }

        private ImageCodecInfo GetEncoderInfo(ImageFormat format)
        {
            ImageCodecInfo[] codecs = ImageCodecInfo.GetImageEncoders();
            foreach (ImageCodecInfo codec in codecs)
            {
                if (codec.FormatID == format.Guid)
                {
                    return codec;
                }
            }
            return null;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto, SetLastError = true)]
        private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        private void BlurSensitiveWindows(Graphics g, Bitmap bmp)
        {
            try
            {
                EnumWindows((hWnd, lParam) =>
                {
                    if (!IsWindowVisible(hWnd)) return true;

                    System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
                    GetWindowText(hWnd, sb, 256);
                    string title = sb.ToString().ToLower();

                    uint procId = 0;
                    GetWindowThreadProcessId(hWnd, out procId);
                    string procName = "";
                    try
                    {
                        using (var proc = System.Diagnostics.Process.GetProcessById((int)procId))
                        {
                            procName = proc.ProcessName.ToLower();
                        }
                    }
                    catch { }

                    // Detect WhatsApp (both desktop app & browser tabs in light/dark mode) + Social/Banking apps
                    bool isWhatsApp = title.Contains("whatsapp") || procName.Contains("whatsapp") || title.Contains("web.whatsapp");
                    bool isSensitive = isWhatsApp || title.Contains("telegram") || title.Contains("facebook") || title.Contains("instagram") || title.Contains("banking") || procName.Contains("telegram");

                    if (isSensitive)
                    {
                        RECT r;
                        if (GetWindowRect(hWnd, out r))
                        {
                            int width = r.Right - r.Left;
                            int height = r.Bottom - r.Top;
                            if (width > 60 && height > 60)
                            {
                                Rectangle targetRect = new Rectangle(r.Left, r.Top, width, height);

                                // 1. Dark Mask Privacy Overlay
                                using (SolidBrush maskBrush = new SolidBrush(Color.FromArgb(245, 18, 24, 30)))
                                {
                                    g.FillRectangle(maskBrush, targetRect);
                                }

                                // 2. Golden Accent Privacy Border
                                using (Pen borderPen = new Pen(Color.FromArgb(239, 170, 31), 3f))
                                {
                                    g.DrawRectangle(borderPen, targetRect);
                                }

                                // 3. Privacy Protection Text Badge
                                string badgeText = isWhatsApp ? "🔒 Privacy Protected: WhatsApp (Dark/Light Mode)" : "🔒 Privacy Protected Content";
                                using (Font font = new Font("Segoe UI", 12f, FontStyle.Bold))
                                using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(239, 170, 31)))
                                {
                                    g.DrawString(badgeText, font, textBrush, targetRect.X + 20, targetRect.Y + 20);
                                }
                            }
                        }
                    }
                    return true;
                }, IntPtr.Zero);
            }
            catch { }
        }

        public void Dispose()
        {
        }
    }
}
