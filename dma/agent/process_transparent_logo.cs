using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

class LogoProcessor
{
    static void Main(string[] args)
    {
        try
        {
            string srcPath = @"d:\Projects\ektaHr\ehrms-main\ehrms-main\hrms\assets\images\ektahr_rec.jpeg";
            if (!File.Exists(srcPath))
            {
                srcPath = @"d:\Projects\ektaHr\dma\agent\publish\ekta_logo.jpeg";
            }

            Console.WriteLine("Loading source logo: " + srcPath);
            using (Bitmap orig = new Bitmap(srcPath))
            {
                // Create transparent ARGB bitmap
                Bitmap transparentBmp = new Bitmap(orig.Width, orig.Height, PixelFormat.Format32bppArgb);

                for (int y = 0; y < orig.Height; y++)
                {
                    for (int x = 0; x < orig.Width; x++)
                    {
                        Color c = orig.GetPixel(x, y);
                        // If pixel is white or near white, make it transparent
                        if (c.R > 235 && c.G > 235 && c.B > 235)
                        {
                            transparentBmp.SetPixel(x, y, Color.Transparent);
                        }
                        else
                        {
                            transparentBmp.SetPixel(x, y, c);
                        }
                    }
                }

                // 1. Save transparent PNG to public folders
                string pngPath1 = @"d:\Projects\ektaHr\dma\admin_console\public\ektahr_transparent.png";
                string pngPath2 = @"d:\Projects\ektaHr\dma\agent\publish\ektahr_transparent.png";
                transparentBmp.Save(pngPath1, ImageFormat.Png);
                transparentBmp.Save(pngPath2, ImageFormat.Png);
                Console.WriteLine("Saved ektahr_transparent.png!");

                // 2. Generate valid Win32 ICO icon with transparent background
                using (Bitmap iconBmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(iconBmp))
                    {
                        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                        g.Clear(Color.Transparent);

                        float scale = Math.Min(256f / transparentBmp.Width, 256f / transparentBmp.Height);
                        int w = (int)(transparentBmp.Width * scale);
                        int h = (int)(transparentBmp.Height * scale);
                        int px = (256 - w) / 2;
                        int py = (256 - h) / 2;

                        g.DrawImage(transparentBmp, px, py, w, h);
                    }

                    IntPtr hIcon = iconBmp.GetHicon();
                    using (Icon icon = Icon.FromHandle(hIcon))
                    {
                        string icoPath1 = @"d:\Projects\ektaHr\dma\agent\ektaHr.ico";
                        string icoPath2 = @"d:\Projects\ektaHr\dma\admin_console\public\favicon.ico";
                        string icoPath3 = @"d:\Projects\ektaHr\dma\admin_console\public\ektaHr.ico";

                        using (FileStream fs = new FileStream(icoPath1, FileMode.Create)) { icon.Save(fs); }
                        using (FileStream fs = new FileStream(icoPath2, FileMode.Create)) { icon.Save(fs); }
                        using (FileStream fs = new FileStream(icoPath3, FileMode.Create)) { icon.Save(fs); }
                        Console.WriteLine("Generated transparent Win32 ICO files!");
                    }
                }

                // 3. Embed transparent PNG Base64 into AgentSingle.cs
                byte[] pngBytes = File.ReadAllBytes(pngPath1);
                string base64Data = Convert.ToBase64String(pngBytes);
                string csPath = @"d:\Projects\ektaHr\dma\agent\AgentSingle.cs";
                string csContent = File.ReadAllText(csPath);

                System.Text.RegularExpressions.Regex regex = new System.Text.RegularExpressions.Regex(@"public const string LOGO_BASE64_DATA = "".*?"";", System.Text.RegularExpressions.RegexOptions.Singleline);
                csContent = regex.Replace(csContent, "public const string LOGO_BASE64_DATA = \"" + base64Data + "\";");
                File.WriteAllText(csPath, csContent);

                Console.WriteLine("Embedded transparent PNG Base64 into AgentSingle.cs! Length: " + base64Data.Length);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("ERROR: " + ex.Message + "\n" + ex.StackTrace);
        }
    }
}
