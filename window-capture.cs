using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// A reusable worker per window; the UI can still terminate a stalled capture.
internal static class WindowCapture {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);

    static bool IsTarget(IntPtr hwnd, uint expected) {
        uint actual;
        GetWindowThreadProcessId(hwnd, out actual);
        if (actual != expected) return false;
        using (Process process = Process.GetProcessById((int)actual))
            return String.Equals(Path.GetFileName(process.MainModule.FileName), "RobloxPlayerBeta.exe", StringComparison.OrdinalIgnoreCase);
    }

    [STAThread] static int Main(string[] args) {
        if (args.Length != 3 && (args.Length != 5 || args[3] != "--serve")) return 2;
        try {
            SetProcessDPIAware();
            IntPtr hwnd = new IntPtr(Int64.Parse(args[0]));
            uint pid = UInt32.Parse(args[1]);
            string path = Path.GetFullPath(args[2]);
            if (args.Length == 3) return Capture(hwnd, pid, path);
            using (Process parent = Process.GetProcessById(Int32.Parse(args[4]))) {
                // Acquire the parent's handle now so PID reuse cannot keep an orphan alive.
                IntPtr parentHandle = parent.Handle;
                DateTime lastRequest = DateTime.UtcNow;
                DateTime retireAt = lastRequest.AddSeconds(1800 + (hwnd.ToInt64() & 255));
                while (!parent.HasExited && DateTime.UtcNow < retireAt && (DateTime.UtcNow - lastRequest).TotalSeconds < 30) {
                    if (!File.Exists(path + ".request")) { Thread.Sleep(25); continue; }
                    File.Delete(path + ".request");
                    lastRequest = DateTime.UtcNow;
                    int result = Capture(hwnd, pid, path);
                    File.WriteAllText(path + ".result.tmp", result.ToString());
                    File.Move(path + ".result.tmp", path + ".result");
                }
            }
            return 0;
        } catch { return 7; }
    }

    static int Capture(IntPtr hwnd, uint pid, string path) {
        try {
            if (!IsTarget(hwnd, pid) || IsIconic(hwnd)) return 3;
            Rect rect;
            if (!GetClientRect(hwnd, out rect)) return 4;
            int width = rect.Right, height = rect.Bottom;
            if (width < 24 || height < 24 || width > 8192 || height > 8192) return 4;
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            using (Bitmap image = new Bitmap(width, height, PixelFormat.Format24bppRgb)) {
                using (Graphics graphics = Graphics.FromImage(image)) {
                    graphics.Clear(Color.Black);
                    IntPtr dc = graphics.GetHdc();
                    bool ok;
                    try { ok = PrintWindow(hwnd, dc, 3); }
                    finally { graphics.ReleaseHdc(dc); }
                    if (!ok) return 5;
                }
                if (!IsTarget(hwnd, pid)) return 3;
                int searchWidth = Math.Min(width, 600), searchHeight = Math.Min(height, 200);
                Rectangle area = new Rectangle((width - searchWidth) / 2, 0, searchWidth, searchHeight);
                using (Bitmap search = image.Clone(area, PixelFormat.Format24bppRgb)) {
                    bool hasContent = false;
                    for (int y = 0; y < searchHeight && !hasContent; y += 8)
                        for (int x = 0; x < searchWidth; x += 8) {
                            Color pixel = search.GetPixel(x, y);
                            if (pixel.R > 24 || pixel.G > 24 || pixel.B > 24) { hasContent = true; break; }
                        }
                    if (!hasContent) return 6; // GPU capture unavailable; do not treat black as no warning.
                }
                // A bounded, replaceable candidate; only a detected incident is retained.
                image.Save(path + ".jpg", ImageFormat.Jpeg);
                File.WriteAllText(path + ".ready", width + "," + height);
            }
            return 0;
        } catch { return 7; }
    }
}
