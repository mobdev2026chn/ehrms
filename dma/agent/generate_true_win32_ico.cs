using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

class TrueWin32IcoGenerator
{
    static void Main()
    {
        string jpegPath = @"d:\Projects\ektaHr\dma\agent\publish\ekta_logo.jpeg";
        Console.WriteLine("Reading 1024x1024 logo from: " + jpegPath);

        using (Bitmap originalBmp = new Bitmap(jpegPath))
        {
            using (Bitmap iconBmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(iconBmp))
                {
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.Clear(Color.Transparent);

                    g.DrawImage(originalBmp, 0, 0, 256, 256);
                }

                IntPtr hIcon = iconBmp.GetHicon();
                using (Icon icon = Icon.FromHandle(hIcon))
                {
                    string[] targetPaths = new string[]
                    {
                        @"d:\Projects\ektaHr\dma\agent\ektaHr.ico",
                        @"d:\Projects\ektaHr\dma\agent\publish\ektaHr.ico",
                        @"d:\Projects\ektaHr\dma\admin_console\publish\ektaHr.ico",
                        @"d:\Projects\ektaHr\dma\admin_console\public\ektaHr.ico",
                        @"d:\Projects\ektaHr\dma\admin_console\public\favicon.ico",
                        @"d:\Projects\ektaHr\dma\admin_console\dist\ektaHr.ico",
                        @"d:\Projects\ektaHr\dma\admin_console\dist\favicon.ico"
                    };

                    foreach (string path in targetPaths)
                    {
                        using (FileStream fs = new FileStream(path, FileMode.Create))
                        {
                            icon.Save(fs);
                        }
                        Console.WriteLine("Saved native Win32 icon to: " + path);
                    }
                }
            }
        }
        Console.WriteLine("NATIVE ICON GENERATION COMPLETE!");
    }
}
