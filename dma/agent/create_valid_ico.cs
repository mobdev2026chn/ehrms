using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

class IcoGenerator
{
    static void Main(string[] args)
    {
        try
        {
            string jpegPath = @"d:\Projects\ektaHr\dma\agent\publish\ekta_logo.jpeg";
            if (!File.Exists(jpegPath))
            {
                jpegPath = @"d:\Projects\ektaHr\dma\admin_console\public\ekta_logo.jpeg";
            }

            Console.WriteLine("Reading JPEG: " + jpegPath);
            using (Bitmap originalBmp = new Bitmap(jpegPath))
            {
                // Resize to 256x256 square with transparent/clean background for crisp icon
                using (Bitmap iconBmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(iconBmp))
                    {
                        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                        g.Clear(Color.Transparent);

                        // Draw centered image keeping aspect ratio
                        float scale = Math.Min(256f / originalBmp.Width, 256f / originalBmp.Height);
                        int w = (int)(originalBmp.Width * scale);
                        int h = (int)(originalBmp.Height * scale);
                        int x = (256 - w) / 2;
                        int y = (256 - h) / 2;

                        g.DrawImage(originalBmp, x, y, w, h);
                    }

                    IntPtr hIcon = iconBmp.GetHicon();
                    using (Icon icon = Icon.FromHandle(hIcon))
                    {
                        string outPath1 = @"d:\Projects\ektaHr\dma\agent\ektaHr.ico";
                        string outPath2 = @"d:\Projects\ektaHr\dma\admin_console\public\favicon.ico";
                        string outPath3 = @"d:\Projects\ektaHr\dma\admin_console\public\ektaHr.ico";

                        using (FileStream fs = new FileStream(outPath1, FileMode.Create))
                        {
                            icon.Save(fs);
                        }
                        using (FileStream fs = new FileStream(outPath2, FileMode.Create))
                        {
                            icon.Save(fs);
                        }
                        using (FileStream fs = new FileStream(outPath3, FileMode.Create))
                        {
                            icon.Save(fs);
                        }
                        Console.WriteLine("SUCCESSFULLY GENERATED VALID WIN32 ICO FILES!");
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("ERROR: " + ex.Message + "\n" + ex.StackTrace);
        }
    }
}
