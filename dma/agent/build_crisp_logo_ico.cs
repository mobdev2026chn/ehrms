using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

class CrispLogoIcoBuilder
{
    static void Main()
    {
        string jpegPath = @"d:\Projects\ektaHr\dma\admin_console\dist\ekta_logo.jpeg";
        Console.WriteLine("Loading JPEG from: " + jpegPath);

        using (Bitmap originalBmp = new Bitmap(jpegPath))
        {
            int[] sizes = new int[] { 256, 48, 32, 16 };
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
                        g.CompositingQuality = CompositingQuality.HighQuality;

                        g.Clear(Color.White);
                        g.DrawImage(originalBmp, 0, 0, sz, sz);

                        if (sz <= 32)
                        {
                            float dotX = sz * 0.16f;
                            float dotY = sz * 0.10f;
                            float dotSize = Math.Max(4.0f, sz * 0.25f);

                            using (SolidBrush yellowBrush = new SolidBrush(Color.FromArgb(254, 218, 3)))
                            {
                                g.FillEllipse(yellowBrush, dotX, dotY, dotSize, dotSize);
                            }
                        }
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
        Console.WriteLine("CRISP LOGO ICO GENERATION COMPLETE!");
    }
}
