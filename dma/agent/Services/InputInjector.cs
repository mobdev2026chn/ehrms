using System;
using System.Runtime.InteropServices;

namespace EktaDMAAgent.Services
{
    public class InputInjector
    {
        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int X, int Y);

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
        private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
        private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
        private const uint MOUSEEVENTF_WHEEL = 0x0800;

        private const uint KEYEVENTF_KEYDOWN = 0x0000;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        public static void InjectMouseMove(int x, int y)
        {
            try
            {
                SetCursorPos(x, y);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[InputInjector] MouseMove error: " + ex.Message);
            }
        }

        public static void InjectMouseClick(int x, int y, string button = "LEFT", bool isDoubleClick = false)
        {
            try
            {
                SetCursorPos(x, y);

                uint downFlag = MOUSEEVENTF_LEFTDOWN;
                uint upFlag = MOUSEEVENTF_LEFTUP;

                if (button.ToUpper() == "RIGHT")
                {
                    downFlag = MOUSEEVENTF_RIGHTDOWN;
                    upFlag = MOUSEEVENTF_RIGHTUP;
                }
                else if (button.ToUpper() == "MIDDLE")
                {
                    downFlag = MOUSEEVENTF_MIDDLEDOWN;
                    upFlag = MOUSEEVENTF_MIDDLEUP;
                }

                mouse_event(downFlag, (uint)x, (uint)y, 0, 0);
                mouse_event(upFlag, (uint)x, (uint)y, 0, 0);

                if (isDoubleClick)
                {
                    System.Threading.Thread.Sleep(50);
                    mouse_event(downFlag, (uint)x, (uint)y, 0, 0);
                    mouse_event(upFlag, (uint)x, (uint)y, 0, 0);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[InputInjector] MouseClick error: " + ex.Message);
            }
        }

        public static void InjectMouseWheel(int delta)
        {
            try
            {
                mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (uint)delta, 0);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[InputInjector] MouseWheel error: " + ex.Message);
            }
        }

        public static void InjectKeyEvent(byte vkCode, bool isKeyDown)
        {
            try
            {
                uint flags = isKeyDown ? KEYEVENTF_KEYDOWN : KEYEVENTF_KEYUP;
                keybd_event(vkCode, 0, flags, 0);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[InputInjector] KeyEvent error: " + ex.Message);
            }
        }
    }
}
