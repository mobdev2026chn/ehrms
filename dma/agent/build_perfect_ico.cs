using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

class PerfectIcoBuilder
{
    static void Main()
    {
        string jpegPath = @"d:\Projects\ektaHr\dma\agent\publish\ekta_logo.jpeg";
        Console.WriteLine("Loading JPEG: " + jpegPath);

        using (Image srcImg = Image.FromFile(jpegPath))
        {
            int[] sizes = new int[] { 256, 128, 64, 48, 32, 16 };
            List<byte[]> pngBytesList = new List<byte[]>();

            foreach (int sz in sizes)
            {
                using (Bitmap bmp = new Bitmap(sz, sz, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.SmoothingMode = SmoothingMode.HighQuality;
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.Clear(Color.White);

                        float scale = Math.Min((float)sz / srcImg.Width, (float)sz / srcImg.Height);
                        int w = (int)(srcImg.Width * scale);
                        int h = (int)(srcImg.Height * scale);
                        int x = (sz - w) / 2;
                        int y = (sz - h) / 2;

                        g.DrawImage(srcImg, x, y, w, h);
                    }

                    using (MemoryStream ms = new MemoryStream())
                    {
                        bmp.Save(ms, ImageFormat.Png);
                        pngBytesList.Add(ms.ToArray());
                    }
                }
            }

            using (MemoryStream icoMs = new MemoryStream())
            using (BinaryWriter bw = new BinaryWriter(icoMs))
            {
                bw.Write((short)0);
                bw.Write((short)1);
                bw.Write((short)sizes.Length);

                int offset = 6 + (sizes.Length * 16);

                for (int i = 0; i < sizes.Length; i++)
                {
                    int sz = sizes[i];
                    byte bSz = (byte)(sz >= 256 ? 0 : sz);
                    byte[] pngData = pngBytesList[i];

                    bw.Write(bSz);
                    bw.Write(bSz);
                    bw.Write((byte)0);
                    bw.Write((byte)0);
                    bw.Write((short)1);
                    bw.Write((short)32);
                    bw.Write((int)pngData.Length);
                    bw.Write((int)offset);

                    offset += pngData.Length;
                }

                for (int i = 0; i < sizes.Length; i++)
                {
                    bw.Write(pngBytesList[i]);
                }

                byte[] finalIcoBytes = icoMs.ToArray();

                string[] outPaths = new string[]
                {
                    @"d:\Projects\ektaHr\dma\agent\ektaHr.ico",
                    @"d:\Projects\ektaHr\dma\agent\publish\ektaHr.ico",
                    @"d:\Projects\ektaHr\dma\admin_console\publish\ektaHr.ico",
                    @"d:\Projects\ektaHr\dma\admin_console\public\ektaHr.ico",
                    @"d:\Projects\ektaHr\dma\admin_console\public\favicon.ico",
                    @"d:\Projects\ektaHr\dma\admin_console\dist\ektaHr.ico",
                    @"d:\Projects\ektaHr\dma\admin_console\dist\favicon.ico"
                };

                foreach (string p in outPaths)
                {
                    File.WriteAllBytes(p, finalIcoBytes);
                    Console.WriteLine("Wrote " + finalIcoBytes.Length + " bytes to: " + p);
                }
            }
        }
    }
}
