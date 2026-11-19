// SlateHUDHelper - one small background helper for the SlateHUD Rainmeter suite.
//
//   SlateHUDHelper.exe ensure      start the daemon if it is not running, then exit (called by skins)
//   SlateHUDHelper.exe daemon      long-running: writes Cache\media.txt (+ cover) and Cache\gpu.txt
//   SlateHUDHelper.exe initnotes   create missing personal Notes files without changing existing data
//   SlateHUDHelper.exe playpause | next | prev | seek <percent>     one-shot media controls
//
// The daemon exits by itself when Rainmeter is no longer running.
// Written in C# 5 so it can be built with the csc.exe that ships with Windows.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

partial class SlateHUDHelper
{
    const string MutexName = "Local\\SlateHUDHelper.Daemon";
    internal const string SharedMemoryName = "Local\\SlateHUDHelper.SharedState";
    internal const string PipeName = "SlateHUDHelper.Pipe";

    const uint SharedMagic = 0x53485544u; // "SHUD"
    const uint SharedVersion = 1u;
    const int SharedSlotCount = 5;
    const int SharedHeaderBytes = 64;
    const int SharedSlotStride = 12288;
    const int SharedMaxPayloadBytes = 12272;
    const int SharedTotalBytes = 65536;

    static string BaseDir = AppDomain.CurrentDomain.BaseDirectory;
    static string CacheDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Cache");
    static volatile bool mediaNeeded = true;
    static volatile bool isDaemonProcess = false;
    static bool gpuNeeded = true;

    static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0].ToLowerInvariant() : "ensure";
        try
        {
            if (cmd == "initnotes")
            {
                InitializeNotes(Path.GetFullPath(Path.Combine(BaseDir, "..", "Notes")));
                Console.Write("READY");
                return 0;
            }
            if (cmd == "launchgame")
            {
                Console.OutputEncoding = new UTF8Encoding(false);
                string message;
                int code = LaunchCatalogGame(args, BaseDir, out message);
                if (!string.IsNullOrEmpty(message)) Console.Write(message);
                return code;
            }
            if (cmd == "ensure") return Ensure();
            if (cmd == "daemon") return Daemon();
            if (cmd == "status") { Console.Write(Status().GetAwaiter().GetResult()); return 0; }   // debug: print once
            return Control(args).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            if (cmd == "status") Console.Write("ERROR: " + ex);
            if (cmd == "initnotes") { Console.Write("ERROR"); return 1; }
            if (cmd == "launchgame") { Console.Write("GAMEHUB:FAILED " + ex.Message); return 1; }
            if (cmd != "ensure" && cmd != "daemon" && cmd != "status")
            {
                Console.Write("MEDIA:ERROR " + ex.Message);
                return 1;
            }
        }
        return 0;
    }

    static void InitializeNotes(string notesDir)
    {
        Directory.CreateDirectory(Path.Combine(notesDir, "Data"));
        CreateNotesFile(Path.Combine(notesDir, "Settings.inc"), "[Variables]\r\nCurrentPage=1\r\n");
        for (int page = 1; page <= 3; page++)
        {
            var text = new StringBuilder("[Variables]\r\nPageTitle=Page " + page + "\r\n");
            for (int row = 1; row <= 5; row++)
                text.Append("Note" + row + "=\r\nStatus" + row + "=0\r\n");
            CreateNotesFile(Path.Combine(notesDir, "Data", "Page" + page + ".inc"), text.ToString());
        }
    }

    static void CreateNotesFile(string path, string text)
    {
        if (File.Exists(path)) return;
        FileStream file;
        try { file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None); }
        catch (IOException) { if (File.Exists(path)) return; throw; }
        using (file)
        using (var writer = new StreamWriter(file, new UTF8Encoding(true))) writer.Write(text);
    }

    internal static void EnsureUserSettings(string resourcesDir)
    {
        if (string.IsNullOrEmpty(resourcesDir)) return;
        Directory.CreateDirectory(resourcesDir);
        CreateNotesFile(Path.Combine(resourcesDir, "UserSettings.inc"),
            "; Local user overrides (git-ignored). Values written here override Variables.inc.\r\n[Variables]\r\n");
    }

    // ------------------------------------------------------------------ ensure
    static int Ensure()
    {
        try { EnsureUserSettings(BaseDir); } catch { }
        try { SyncWindowsAccent(CacheDir); } catch { }
        try { SyncRainmeterPlugin(BaseDir); } catch { }
        Mutex existing;
        if (Mutex.TryOpenExisting(MutexName, out existing)) { existing.Dispose(); return 0; }

        // Start the daemon detached so it survives skin refreshes / unloads.
        var psi = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, "daemon");
        psi.CreateNoWindow = true;
        psi.UseShellExecute = false;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(psi);
        return 0;
    }

    // ------------------------------------------------------------------ daemon
    static int Daemon()
    {
        bool createdNew;
        using (var mutex = new Mutex(true, MutexName, out createdNew))
        {
            if (!createdNew) return 0;
            isDaemonProcess = true;
            Directory.CreateDirectory(CacheDir);
            try { EnsureUserSettings(BaseDir); } catch { }
            try { SyncWindowsAccent(CacheDir, false); } catch { }
            try { SyncRainmeterPlugin(BaseDir); } catch { }
            try { EnsureSharedState(SharedMemoryName); SeedSharedStateFromDisk(CacheDir, SharedMemoryName); } catch { }
            UserPreferenceChangedEventHandler prefHandler = delegate { accentDirty = true; };
            try { SystemEvents.UserPreferenceChanged += prefHandler; } catch { }
            try
            {
                // Media, pipe commands, and cover calls can stall independently of display and GPU sampling.
                Task.WhenAny(DaemonLoop(), MediaLoop(), PipeServerLoop()).GetAwaiter().GetResult().GetAwaiter().GetResult();
            }
            finally
            {
                try { SystemEvents.UserPreferenceChanged -= prefHandler; } catch { }
            }
            GC.KeepAlive(mutex);
        }
        return 0;
    }

    static Process rainmeterProc = null;

    static bool IsRainmeterRunning()
    {
        if (rainmeterProc != null)
        {
            try
            {
                if (!rainmeterProc.HasExited) return true;
                rainmeterProc.Dispose();
                rainmeterProc = null;
            }
            catch
            {
                rainmeterProc = null;
            }
        }
        var procs = Process.GetProcessesByName("Rainmeter");
        if (procs.Length > 0)
        {
            rainmeterProc = procs[0];
            for (int i = 1; i < procs.Length; i++) procs[i].Dispose();
            return true;
        }
        return false;
    }

    internal static uint GetActiveRainmeterPid()
    {
        if (rainmeterProc != null)
        {
            try
            {
                if (!rainmeterProc.HasExited) return (uint)rainmeterProc.Id;
            }
            catch { }
        }
        return IsRainmeterRunning() && rainmeterProc != null ? (uint)rainmeterProc.Id : 0u;
    }

    // Keep freshness timestamps without replacing unchanged files on every poll.
    // Commit the cache only after a successful write so failures retry next poll.
    internal sealed class SnapshotPublisher
    {
        string lastBody;
        long lastPublished;
        internal bool Publish(string path, string body, long now, int heartbeatSeconds)
        {
            if (body == lastBody && now >= lastPublished &&
                now - lastPublished < heartbeatSeconds && File.Exists(path)) return true;
            if (!WriteFast(path, "UPDATED=" + now.ToString(CultureInfo.InvariantCulture) + "\n" + body)) return false;
            lastBody = body;
            lastPublished = now;
            return true;
        }
    }

    static async Task DaemonLoop()
    {
        int tick = 0, rainmeterMisses = 0;
        bool nvmlOk = false;
        var displayPublisher = new SnapshotPublisher();
        DateTime nextGpuRetry = DateTime.MinValue;
        DateTime nextLhmRetry = DateTime.MinValue;
        string suitePath = Path.GetFullPath(Path.Combine(BaseDir, "..")) + Path.DirectorySeparatorChar;

        while (true)
        {
            var elapsed = Stopwatch.StartNew();
            // Quit when Rainmeter is gone (checked every 5 ticks, must be missing twice in a row).
            if (tick % 5 == 0)
            {
                if (!IsRainmeterRunning()) rainmeterMisses++; else rainmeterMisses = 0;
                if (rainmeterMisses >= 2) return;
            }

            string state = null;
            try
            {
                uint pid = GetActiveRainmeterPid();
                state = DisplayProbe.Snapshot(UnixSeconds(DateTimeOffset.UtcNow), pid, suitePath);
                if (state != null)
                    displayPublisher.Publish(Path.Combine(CacheDir, "monitors.txt"),
                        state.Substring(state.IndexOf('\n') + 1), UnixSeconds(DateTimeOffset.UtcNow), 2);
            }
            catch { /* Leave the previous snapshot for stale-data handling. */ }

            mediaNeeded = ConsumerNeeded(state, "Root");
            bool needed = ConsumerNeeded(state, "System");
            if (needed != gpuNeeded)
            {
                gpuNeeded = needed;
                nextGpuRetry = DateTime.MinValue;
                nextLhmRetry = DateTime.MinValue;
                if (!needed) { GpuFailed(); nvmlOk = false; }
            }

            // --- gpu / LHM telemetry (every 2nd tick) ---
            if (gpuNeeded && tick % 2 == 0)
            {
                bool cfgChanged;
                TelemetryConfig cfg = GetTelemetryConfig(BaseDir, out cfgChanged);
                if (cfgChanged)
                {
                    nextGpuRetry = DateTime.MinValue;
                    nextLhmRetry = DateTime.MinValue;
                }

                string gpu = UnavailableGpu;
                if (cfg.Provider != "lhm")
                {
                    if (!nvmlOk && DateTime.UtcNow >= nextGpuRetry)
                    {
                        nvmlOk = NvmlInit();
                        nextGpuRetry = DateTime.UtcNow.AddSeconds(30);
                    }
                    gpu = nvmlOk ? ReadGpu() : UnavailableGpu;
                    if (gpu == UnavailableGpu) nvmlOk = false;
                }
                else if (nvmlOk)
                {
                    GpuFailed();
                    nvmlOk = false;
                }

                string cpuTempLine = null;
                string lhmGpuLine = null;
                if (cfg.LhmEnabled && DateTime.UtcNow >= nextLhmRetry)
                {
                    LhmTelemetryResult lhm = await ReadLhmTelemetryAsync(cfg);
                    if (lhm.Reachable)
                    {
                        cpuTempLine = lhm.HasCpuTemp ? CpuTempLine(lhm) : null;
                        lhmGpuLine = lhm.HasGpu ? LhmGpuLine(lhm) : null;
                    }
                    else
                    {
                        nextLhmRetry = DateTime.UtcNow.AddSeconds(30);
                    }
                }

                // A timestamp is published even for unchanged values. Consumers can
                // distinguish a genuine idle GPU from a stopped or stalled helper.
                WriteFast(Path.Combine(CacheDir, "gpu.txt"),
                    GpuSnapshot(gpu, DateTimeOffset.UtcNow, ReadPageFile(), cpuTempLine, lhmGpuLine));
            }

            // Independent of media queries and widget demand; watchdogs never
            // spawn an extra CLR process while this heartbeat is healthy.
            if (tick % 5 == 0)
                WriteFast(Path.Combine(CacheDir, "helper-health.txt"),
                    "UPDATED=" + UnixSeconds(DateTimeOffset.UtcNow).ToString(CultureInfo.InvariantCulture));

            if (accentDirty || tick % 5 == 0)
                try { SyncWindowsAccent(CacheDir, true); } catch { }

            tick++;
            await Task.Delay(Math.Max(1, 1000 - (int)elapsed.ElapsedMilliseconds));
        }
    }

    static bool ConsumerNeeded(string snapshot, string config)
    {
        // Unknown inventory must not disable telemetry. Hidden but loaded skins
        // remain consumers so showing them again needs no initialization delay.
        if (snapshot == null || !snapshot.Contains("\nSKINS=1\n")) return true;
        return snapshot.IndexOf("\nSKIN\t" + config + "\t", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    static long UnixSeconds(DateTimeOffset now)
    {
        return (long)(now - new DateTimeOffset(1970, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool MoveFileEx(string existingPath, string newPath, uint flags);

    static bool WriteFast(string path, string text)
    {
        bool ok = WriteBytesFast(path, new UTF8Encoding(false).GetBytes(text));
        if (ok && isDaemonProcess)
        {
            try
            {
                string dir = Path.GetDirectoryName(Path.GetFullPath(path)) ?? "";
                string cacheFull = Path.GetFullPath(CacheDir).TrimEnd('\\', '/');
                if (string.Equals(dir.TrimEnd('\\', '/'), cacheFull, StringComparison.OrdinalIgnoreCase))
                    PublishSharedStream(SharedMemoryName, Path.GetFileName(path), text);
            }
            catch { }
        }
        return ok;
    }

    static bool WriteBytesFast(string path, byte[] bytes)
    {
        string tempPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllBytes(tempPath, bytes);
            // Keep the previous complete snapshot readable until its replacement is ready.
            // Same-directory rename: REPLACE_EXISTING | WRITE_THROUGH. A sharing
            // violation leaves the old snapshot intact and is retried next tick.
            return MoveFileEx(tempPath, path, 0x1 | 0x8);
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        finally
        {
            try { File.Delete(tempPath); } catch { }
        }
    }

    static string ReadTextSafe(string path)
    {
        try
        {
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var reader = new StreamReader(stream, Encoding.UTF8))
                return reader.ReadToEnd();
        }
        catch { return null; }
    }

    static uint lastAccentRaw = 0;
    static volatile bool accentDirty = true;
    static DateTime lastAccentRefreshUtc = DateTime.MinValue;

    static double LinearizeChannel(byte c)
    {
        double s = c / 255.0;
        return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
    }

    internal static double RelativeLuminance(byte r, byte g, byte b)
    {
        return 0.2126 * LinearizeChannel(r) + 0.7152 * LinearizeChannel(g) + 0.0722 * LinearizeChannel(b);
    }

    internal static void RgbToHsl(byte rByte, byte gByte, byte bByte, out double h, out double s, out double l)
    {
        double r = rByte / 255.0;
        double g = gByte / 255.0;
        double b = bByte / 255.0;
        double max = Math.Max(r, Math.Max(g, b));
        double min = Math.Min(r, Math.Min(g, b));
        l = (max + min) * 0.5;
        if (max - min < 1e-9)
        {
            h = 0.0;
            s = 0.0;
            return;
        }
        double d = max - min;
        s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
        if (max == r) h = (g - b) / d + (g < b ? 6.0 : 0.0);
        else if (max == g) h = (b - r) / d + 2.0;
        else h = (r - g) / d + 4.0;
        h /= 6.0;
    }

    static double HueToRgb(double p, double q, double t)
    {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }

    internal static void HslToRgb(double h, double s, double l, out byte r, out byte g, out byte b)
    {
        h = h - Math.Floor(h);
        if (s < 0.0) s = 0.0; else if (s > 1.0) s = 1.0;
        if (l < 0.0) l = 0.0; else if (l > 1.0) l = 1.0;
        if (s <= 1e-9)
        {
            byte v = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(l * 255.0)));
            r = v; g = v; b = v;
            return;
        }
        double q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        double p = 2.0 * l - q;
        r = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(HueToRgb(p, q, h + 1.0 / 3.0) * 255.0)));
        g = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(HueToRgb(p, q, h) * 255.0)));
        b = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(HueToRgb(p, q, h - 1.0 / 3.0) * 255.0)));
    }

    static double FindLightnessForLuminance(double h, double s, double lo, double hi, double targetLum, bool findMinimumAbove)
    {
        double best = findMinimumAbove ? hi : lo;
        for (int i = 0; i < 24; i++)
        {
            double mid = (lo + hi) * 0.5;
            byte tr, tg, tb;
            HslToRgb(h, s, mid, out tr, out tg, out tb);
            double lum = RelativeLuminance(tr, tg, tb);
            if (findMinimumAbove)
            {
                if (lum >= targetLum) { best = mid; hi = mid; }
                else lo = mid;
            }
            else
            {
                if (lum <= targetLum) { best = mid; lo = mid; }
                else hi = mid;
            }
        }
        return best;
    }

    internal static void ClampAccentLuminance(byte rIn, byte gIn, byte bIn, out byte rOut, out byte gOut, out byte bOut)
    {
        double lum = RelativeLuminance(rIn, gIn, bIn);
        if (lum >= 0.24 && lum <= 0.68)
        {
            rOut = rIn; gOut = gIn; bOut = bIn;
            return;
        }
        double h, s, l;
        RgbToHsl(rIn, gIn, bIn, out h, out s, out l);
        double targetL = lum < 0.24
            ? FindLightnessForLuminance(h, s, l, 0.94, 0.24, true)
            : FindLightnessForLuminance(h, s, 0.20, l, 0.68, false);
        HslToRgb(h, s, targetL, out rOut, out gOut, out bOut);
    }

    static byte BlendWithWhite(byte c, double whiteWeight)
    {
        return (byte)Math.Max(0, Math.Min(255, (int)Math.Round(c * (1.0 - whiteWeight) + 255.0 * whiteWeight)));
    }

    static bool TryReadDword(RegistryKey key, string valueName, out uint result)
    {
        result = 0;
        if (key == null) return false;
        object val = key.GetValue(valueName);
        if (val is int) { result = (uint)(int)val; return true; }
        if (val is long) { result = (uint)(long)val; return true; }
        return false;
    }

    static void ReadWindowsAccentRgb(out byte r, out byte g, out byte b)
    {
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"))
            {
                uint bgr;
                if (TryReadDword(key, "AccentColorMenu", out bgr) && bgr != 0u)
                {
                    r = (byte)(bgr & 0xFFu);
                    g = (byte)((bgr >> 8) & 0xFFu);
                    b = (byte)((bgr >> 16) & 0xFFu);
                    return;
                }
            }
        }
        catch { }

        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\DWM"))
            {
                uint bgr;
                if (TryReadDword(key, "AccentColor", out bgr) && bgr != 0u)
                {
                    r = (byte)(bgr & 0xFFu);
                    g = (byte)((bgr >> 8) & 0xFFu);
                    b = (byte)((bgr >> 16) & 0xFFu);
                    return;
                }
                uint argb;
                if (TryReadDword(key, "ColorizationColor", out argb) && argb != 0u)
                {
                    r = (byte)((argb >> 16) & 0xFFu);
                    g = (byte)((argb >> 8) & 0xFFu);
                    b = (byte)(argb & 0xFFu);
                    return;
                }
            }
        }
        catch { }

        r = 0; g = 120; b = 215; // Default Windows 10/11 blue
    }

    internal static string BuildWindowsAccentInclude(byte rRaw, byte gRaw, byte bRaw)
    {
        byte rUi, gUi, bUi;
        ClampAccentLuminance(rRaw, gRaw, bRaw, out rUi, out gUi, out bUi);

        double h, s, lUi;
        RgbToHsl(rUi, gUi, bUi, out h, out s, out lUi);
        double lumUi = RelativeLuminance(rUi, gUi, bUi);

        byte rBase, gBase, bBase;
        HslToRgb(h, Math.Min(1.0, s * 1.05), Math.Min(0.86, lUi + 0.14), out rBase, out gBase, out bBase);

        double lTip = Math.Max(0.32, lUi - 0.12);
        byte rTip, gTip, bTip;
        HslToRgb(h, s, lTip, out rTip, out gTip, out bTip);
        if (RelativeLuminance(rTip, gTip, bTip) < 0.14)
        {
            lTip = FindLightnessForLuminance(h, s, lTip, lUi, 0.14, true);
            HslToRgb(h, s, lTip, out rTip, out gTip, out bTip);
        }

        byte rSt = BlendWithWhite(rUi, 0.30);
        byte gSt = BlendWithWhite(gUi, 0.30);
        byte bSt = BlendWithWhite(bUi, 0.30);
        int strokeAlpha = lumUi >= 0.35 ? 48 : 58;

        byte rBb = BlendWithWhite(rUi, 0.60);
        byte gBb = BlendWithWhite(gUi, 0.60);
        byte bBb = BlendWithWhite(bUi, 0.60);

        byte rCard = (byte)(12 + (int)Math.Round((rRaw / 255.0) * 6.0));
        byte gCard = (byte)(13 + (int)Math.Round((gRaw / 255.0) * 6.0));
        byte bCard = (byte)(16 + (int)Math.Round((bRaw / 255.0) * 6.0));

        byte rCov = (byte)(26 + (int)Math.Round((rRaw / 255.0) * 10.0));
        byte gCov = (byte)(27 + (int)Math.Round((gRaw / 255.0) * 10.0));
        byte bCov = (byte)(31 + (int)Math.Round((bRaw / 255.0) * 10.0));

        byte rInp = (byte)(22 + (int)Math.Round((rRaw / 255.0) * 8.0));
        byte gInp = (byte)(22 + (int)Math.Round((gRaw / 255.0) * 8.0));
        byte bInp = (byte)(26 + (int)Math.Round((bRaw / 255.0) * 8.0));

        byte rH2, gH2, bH2;
        if (s < 0.12)
        {
            rH2 = 130; gH2 = 170; bH2 = 255;
        }
        else
        {
            double h2 = h + 50.0 / 360.0;
            double s2 = Math.Max(0.45, Math.Min(0.85, s));
            double l2 = 0.68;
            HslToRgb(h2, s2, l2, out rH2, out gH2, out bH2);
            if (RelativeLuminance(rH2, gH2, bH2) < 0.30)
            {
                l2 = FindLightnessForLuminance(h2, s2, l2, 0.90, 0.30, true);
                HslToRgb(h2, s2, l2, out rH2, out gH2, out bH2);
            }
        }

        return string.Format(CultureInfo.InvariantCulture,
            "; Generated dynamically by SlateHUDHelper\r\n[Variables]\r\n" +
            "WindowsAccentRaw={0},{1},{2},255\r\n" +
            "WindowsAccentR={3}\r\nWindowsAccentG={4}\r\nWindowsAccentB={5}\r\n" +
            "WindowsAccentColor={3},{4},{5},255\r\n" +
            "WindowsAccentStroke={6},{7},{8},{9}\r\n" +
            "WindowsAccentBarBack={10},{11},{12},32\r\n" +
            "WindowsAccentGradient=270 | {13},{14},{15},255 ; 0.0 | {3},{4},{5},255 ; 0.5 | {16},{17},{18},215 ; 1.0\r\n" +
            "WindowsAccentCardFill={19},{20},{21}\r\n" +
            "WindowsAccentCoverFill={22},{23},{24}\r\n" +
            "WindowsAccentInputFill={25},{26},{27}\r\n" +
            "WindowsAccentHistory2={28},{29},{30},235\r\n" +
            "WindowsAccentDivider={10},{11},{12},28\r\n" +
            "WindowsAccentPill={10},{11},{12},16\r\n" +
            "WindowsAccentSwitchFill={10},{11},{12},20\r\n" +
            "WindowsAccentCoverNote={10},{11},{12},75\r\n" +
            "WindowsAccentCheckboxEmpty={10},{11},{12},75\r\n",
            rRaw, gRaw, bRaw,
            rUi, gUi, bUi,
            rSt, gSt, bSt, strokeAlpha,
            rBb, gBb, bBb,
            rBase, gBase, bBase,
            rTip, gTip, bTip,
            rCard, gCard, bCard,
            rCov, gCov, bCov,
            rInp, gInp, bInp,
            rH2, gH2, bH2);
    }

    static bool IsWindowsAccentThemeActive()
    {
        try
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string varPath = Path.Combine(BaseDir, "Variables.inc");
            string userPath = Path.Combine(BaseDir, "UserSettings.inc");
            if (File.Exists(varPath)) ApplyIniVariables(ReadTextSafe(varPath), map);
            if (File.Exists(userPath)) ApplyIniVariables(ReadTextSafe(userPath), map);
            string theme;
            return map.TryGetValue("CurrentTheme", out theme) &&
                   string.Equals(theme.Trim(), "WindowsAccent", StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    static void SyncWindowsAccent(string cacheDir)
    {
        SyncWindowsAccent(cacheDir, false);
    }

    static bool SyncWindowsAccent(string cacheDir, bool notifyRainmeter)
    {
        byte rRaw, gRaw, bRaw;
        ReadWindowsAccentRgb(out rRaw, out gRaw, out bRaw);
        uint rawKey = 0xFF000000u | ((uint)rRaw << 16) | ((uint)gRaw << 8) | bRaw;

        try
        {
            string target = Path.Combine(cacheDir, "WindowsAccent.inc");
            bool targetExists = File.Exists(target);
            if (!accentDirty && rawKey == lastAccentRaw && targetExists) return false;

            bool changed = (lastAccentRaw != 0u && rawKey != lastAccentRaw) || !targetExists;
            accentDirty = false;
            lastAccentRaw = rawKey;

            string data = BuildWindowsAccentInclude(rRaw, gRaw, bRaw);
            if (!WriteFast(target, data)) return false;

            if (changed && notifyRainmeter && isDaemonProcess && IsWindowsAccentThemeActive() &&
                (DateTime.UtcNow - lastAccentRefreshUtc).TotalSeconds >= 2.0 && rainmeterProc != null)
            {
                try
                {
                    string rmExe = rainmeterProc.MainModule.FileName;
                    if (!string.IsNullOrEmpty(rmExe) && File.Exists(rmExe))
                    {
                        lastAccentRefreshUtc = DateTime.UtcNow;
                        var psi = new ProcessStartInfo(rmExe, "!RefreshGroup SlateHUD");
                        psi.CreateNoWindow = true;
                        psi.UseShellExecute = false;
                        using (Process p = Process.Start(psi)) { }
                    }
                }
                catch { }
            }
            return true;
        }
        catch { return false; }
    }

    // ------------------------------------------------------------------ shared memory & plugin sync
    static readonly object sharedLock = new object();
    static readonly Dictionary<string, MemoryMappedFile> sharedMaps = new Dictionary<string, MemoryMappedFile>(StringComparer.Ordinal);
    static readonly Dictionary<string, MemoryMappedViewAccessor> sharedViews = new Dictionary<string, MemoryMappedViewAccessor>(StringComparer.Ordinal);

    internal static int GetSharedSlotIndex(string nameOrPath)
    {
        if (string.IsNullOrWhiteSpace(nameOrPath)) return -1;
        string name = Path.GetFileName(nameOrPath.Trim()).ToLowerInvariant();
        if (name == "media.txt" || name == "media") return 0;
        if (name == "media-health.txt" || name == "media-health" || name == "mediahealth") return 1;
        if (name == "gpu.txt" || name == "gpu") return 2;
        if (name == "monitors.txt" || name == "monitors") return 3;
        if (name == "helper-health.txt" || name == "helper-health" || name == "helperhealth") return 4;
        return -1;
    }

    static MemoryMappedViewAccessor GetOrCreateSharedView(string mapName)
    {
        MemoryMappedViewAccessor view;
        if (sharedViews.TryGetValue(mapName, out view)) return view;

        MemoryMappedFile mmf = MemoryMappedFile.CreateOrOpen(mapName, SharedTotalBytes, MemoryMappedFileAccess.ReadWrite);
        view = mmf.CreateViewAccessor(0, SharedTotalBytes, MemoryMappedFileAccess.ReadWrite);
        if (view.ReadUInt32(0) != SharedMagic || view.ReadUInt32(4) != SharedVersion ||
            view.ReadInt32(8) != SharedSlotCount || view.ReadInt32(12) != SharedSlotStride)
        {
            view.Write(0, SharedMagic);
            view.Write(4, SharedVersion);
            view.Write(8, SharedSlotCount);
            view.Write(12, SharedSlotStride);
            for (int i = 0; i < SharedSlotCount; i++)
            {
                int slotOffset = SharedHeaderBytes + i * SharedSlotStride;
                view.Write(slotOffset, 0u);
                view.Write(slotOffset + 4, 0);
            }
            Thread.MemoryBarrier();
        }
        sharedMaps[mapName] = mmf;
        sharedViews[mapName] = view;
        return view;
    }

    internal static void EnsureSharedState(string mapName)
    {
        if (string.IsNullOrWhiteSpace(mapName)) return;
        lock (sharedLock)
        {
            GetOrCreateSharedView(mapName);
        }
    }

    internal static void CloseSharedState(string mapName)
    {
        if (string.IsNullOrWhiteSpace(mapName)) return;
        lock (sharedLock)
        {
            MemoryMappedViewAccessor view;
            if (sharedViews.TryGetValue(mapName, out view))
            {
                try { view.Dispose(); } catch { }
                sharedViews.Remove(mapName);
            }
            MemoryMappedFile mmf;
            if (sharedMaps.TryGetValue(mapName, out mmf))
            {
                try { mmf.Dispose(); } catch { }
                sharedMaps.Remove(mapName);
            }
        }
    }

    internal static bool PublishSharedStream(string mapName, string nameOrPath, string text)
    {
        int slot = GetSharedSlotIndex(nameOrPath);
        if (slot < 0 || string.IsNullOrWhiteSpace(mapName)) return false;

        byte[] bytes = new UTF8Encoding(false).GetBytes(text ?? "");
        int len = bytes.Length;
        if (len > SharedMaxPayloadBytes)
        {
            len = SharedMaxPayloadBytes;
            while (len > 0 && (bytes[len] & 0xC0) == 0x80) len--;
        }

        int slotOffset = SharedHeaderBytes + slot * SharedSlotStride;
        lock (sharedLock)
        {
            MemoryMappedViewAccessor view = GetOrCreateSharedView(mapName);
            uint seq = view.ReadUInt32(slotOffset);
            if ((seq & 1u) != 0u) seq++;
            view.Write(slotOffset, seq + 1u);
            Thread.MemoryBarrier();
            view.Write(slotOffset + 4, len);
            if (len > 0) view.WriteArray(slotOffset + 8, bytes, 0, len);
            view.Write(slotOffset + 8 + len, (byte)0);
            Thread.MemoryBarrier();
            view.Write(slotOffset, seq + 2u);
        }
        return true;
    }

    internal static string ReadSharedStream(string mapName, string nameOrPath)
    {
        int slot = GetSharedSlotIndex(nameOrPath);
        if (slot < 0 || string.IsNullOrWhiteSpace(mapName)) return null;
        try
        {
            using (MemoryMappedFile mmf = MemoryMappedFile.OpenExisting(mapName, MemoryMappedFileRights.Read))
            using (MemoryMappedViewAccessor view = mmf.CreateViewAccessor(0, SharedTotalBytes, MemoryMappedFileAccess.Read))
            {
                if (view.ReadUInt32(0) != SharedMagic || view.ReadUInt32(4) != SharedVersion) return null;
                int slotOffset = SharedHeaderBytes + slot * SharedSlotStride;
                for (int attempt = 0; attempt < 8; attempt++)
                {
                    uint seq1 = view.ReadUInt32(slotOffset);
                    Thread.MemoryBarrier();
                    if (seq1 == 0u || (seq1 & 1u) != 0u)
                    {
                        if (seq1 == 0u) return null;
                        Thread.Sleep(0);
                        continue;
                    }
                    int len = view.ReadInt32(slotOffset + 4);
                    if (len < 0 || len > SharedMaxPayloadBytes)
                    {
                        Thread.Sleep(0);
                        continue;
                    }
                    byte[] buf = new byte[len];
                    if (len > 0) view.ReadArray(slotOffset + 8, buf, 0, len);
                    Thread.MemoryBarrier();
                    uint seq2 = view.ReadUInt32(slotOffset);
                    if (seq1 == seq2) return Encoding.UTF8.GetString(buf);
                }
            }
        }
        catch { }
        return null;
    }

    static void SeedSharedStateFromDisk(string cacheDir, string mapName)
    {
        string[] files = new[] { "media.txt", "media-health.txt", "gpu.txt", "monitors.txt", "helper-health.txt" };
        for (int i = 0; i < files.Length; i++)
        {
            string full = Path.Combine(cacheDir, files[i]);
            if (File.Exists(full))
            {
                string content = ReadTextSafe(full);
                if (content != null) PublishSharedStream(mapName, files[i], content);
            }
        }
    }

    static void CopyPluginIfNewer(string src, string pluginsDir)
    {
        if (string.IsNullOrEmpty(pluginsDir)) return;
        Directory.CreateDirectory(pluginsDir);
        string dst = Path.Combine(pluginsDir, "SlateHUD.dll");

        var srcInfo = new FileInfo(src);
        if (File.Exists(dst))
        {
            var dstInfo = new FileInfo(dst);
            if (dstInfo.Length == srcInfo.Length &&
                Math.Abs((dstInfo.LastWriteTimeUtc - srcInfo.LastWriteTimeUtc).TotalSeconds) <= 2.0)
                return;
        }
        File.Copy(src, dst, true);
    }

    static void SyncRainmeterPlugin(string resourcesDir)
    {
        if (string.IsNullOrEmpty(resourcesDir)) return;
        string src = Path.Combine(resourcesDir, "Plugins", "SlateHUD.dll");
        if (!File.Exists(src)) return;

        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (!string.IsNullOrEmpty(appData))
        {
            string rmDir = Path.Combine(appData, "Rainmeter");
            if (Directory.Exists(rmDir))
            {
                CopyPluginIfNewer(src, Path.Combine(rmDir, "Plugins"));
                return;
            }
        }

        if (IsRainmeterRunning() && rainmeterProc != null)
        {
            try
            {
                string exePath = rainmeterProc.MainModule.FileName;
                string exeDir = !string.IsNullOrEmpty(exePath) ? Path.GetDirectoryName(exePath) : null;
                if (!string.IsNullOrEmpty(exeDir))
                    CopyPluginIfNewer(src, Path.Combine(exeDir, "Plugins"));
            }
            catch { }
        }
    }

    // ------------------------------------------------------------------ fast game launcher
    sealed class CatalogGameEntry
    {
        public string Id;
        public string Title;
        public string Path;
        public string Source;
        public string Folder;
        public string Arguments;
        public string WorkingDirectory;
        public bool Available;
    }

    sealed class GameLibraryJson
    {
        public int Version { get; set; }
        public string Revision { get; set; }
        public List<GameRecordJson> Games { get; set; }
    }

    sealed class GameRecordJson
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Path { get; set; }
        public string Source { get; set; }
        public string Folder { get; set; }
        public string Arguments { get; set; }
        public string WorkingDirectory { get; set; }
        public bool Available { get; set; }
    }

    static readonly Regex GameIdPattern = new Regex(
        @"^(steam:[0-9]+|hoyo:[a-z0-9]+|(folder|epic|legacy|shortcut):[a-f0-9]{64})$",
        RegexOptions.CultureInvariant);
    static readonly Regex RevisionPattern = new Regex(
        @"^(legacy|[a-f0-9]{32})$",
        RegexOptions.CultureInvariant);
    static readonly Regex GameUriPattern = new Regex(
        @"^[a-zA-Z][a-zA-Z0-9+.-]*://",
        RegexOptions.CultureInvariant);
    static readonly Regex GameVarLinePattern = new Regex(
        @"^Game(\d+)(Category|Title|GameId|GamePath|GameSource|GameFolder|GameArguments|GameWorkingDirectory|GameAvailable|GameConfidence)=(.*)$",
        RegexOptions.CultureInvariant);
    static readonly Regex LegacyMeterBlockPattern = new Regex(
        @"(?ms)^\[Meter(RPG|Action|Strategy|Other)\d+\]\r?\n(.*?)(?=^\[|\z)",
        RegexOptions.CultureInvariant);

    static string ParseGameLibraryRevision(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        Match m = Regex.Match(text, @"(?m)^GameLibraryRevision=([a-f0-9]{32})\r?$", RegexOptions.CultureInvariant);
        return m.Success ? m.Groups[1].Value : "";
    }

    static List<CatalogGameEntry> ParseGeneratedGamesFromInc(string text)
    {
        var result = new List<CatalogGameEntry>();
        if (string.IsNullOrEmpty(text)) return result;

        var indexed = new SortedDictionary<int, Dictionary<string, string>>();
        using (var reader = new StringReader(text))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                Match m = GameVarLinePattern.Match(line);
                if (!m.Success) continue;
                int idx = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                Dictionary<string, string> fields;
                if (!indexed.TryGetValue(idx, out fields))
                {
                    fields = new Dictionary<string, string>(StringComparer.Ordinal);
                    indexed[idx] = fields;
                }
                fields[m.Groups[2].Value] = m.Groups[3].Value;
            }
        }

        foreach (KeyValuePair<int, Dictionary<string, string>> kv in indexed)
        {
            Dictionary<string, string> v = kv.Value;
            string gid, gpath, gsrc;
            if (!v.TryGetValue("GameId", out gid) || string.IsNullOrEmpty(gid)) continue;
            if (!v.TryGetValue("GamePath", out gpath) || string.IsNullOrEmpty(gpath)) continue;
            if (!v.TryGetValue("GameSource", out gsrc) || string.IsNullOrEmpty(gsrc)) continue;

            string title = ""; v.TryGetValue("Title", out title);
            string folder = ""; v.TryGetValue("GameFolder", out folder);
            string args = ""; v.TryGetValue("GameArguments", out args);
            string workDir = ""; v.TryGetValue("GameWorkingDirectory", out workDir);
            string availStr = ""; v.TryGetValue("GameAvailable", out availStr);

            result.Add(new CatalogGameEntry
            {
                Id = gid,
                Title = title ?? "",
                Path = gpath,
                Source = gsrc,
                Folder = folder ?? "",
                Arguments = args ?? "",
                WorkingDirectory = workDir ?? "",
                Available = availStr == "1"
            });
        }

        foreach (Match block in LegacyMeterBlockPattern.Matches(text))
        {
            var v = new Dictionary<string, string>(StringComparer.Ordinal);
            using (var reader = new StringReader(block.Groups[2].Value))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0) v[line.Substring(0, eq)] = line.Substring(eq + 1);
                }
            }
            string gid, gpath, gsrc;
            if (!v.TryGetValue("GameId", out gid) || string.IsNullOrEmpty(gid)) continue;
            if (!v.TryGetValue("GamePath", out gpath) || string.IsNullOrEmpty(gpath)) continue;
            if (!v.TryGetValue("GameSource", out gsrc) || string.IsNullOrEmpty(gsrc)) continue;

            string textVal = ""; v.TryGetValue("Text", out textVal);
            if (textVal != null && textVal.StartsWith("[\\x25B8]", StringComparison.Ordinal))
                textVal = textVal.Substring(8).TrimStart();
            string folder = ""; v.TryGetValue("GameFolder", out folder);
            string args = ""; v.TryGetValue("GameArguments", out args);
            string workDir = ""; v.TryGetValue("GameWorkingDirectory", out workDir);
            string availStr = ""; v.TryGetValue("GameAvailable", out availStr);

            result.Add(new CatalogGameEntry
            {
                Id = gid,
                Title = textVal ?? "",
                Path = gpath,
                Source = gsrc,
                Folder = folder ?? "",
                Arguments = args ?? "",
                WorkingDirectory = workDir ?? "",
                Available = availStr == "1"
            });
        }

        return result;
    }

    static List<CatalogGameEntry> ParseGamesFromJson(string jsonText, out bool hasRevision)
    {
        hasRevision = false;
        var result = new List<CatalogGameEntry>();
        if (string.IsNullOrWhiteSpace(jsonText)) return result;

        var serializer = new JavaScriptSerializer();
        GameLibraryJson lib = serializer.Deserialize<GameLibraryJson>(jsonText);
        if (lib == null) return result;
        hasRevision = !string.IsNullOrEmpty(lib.Revision);
        if (lib.Games == null) return result;

        for (int i = 0; i < lib.Games.Count; i++)
        {
            GameRecordJson item = lib.Games[i];
            if (item == null || string.IsNullOrEmpty(item.Id)) continue;
            result.Add(new CatalogGameEntry
            {
                Id = item.Id,
                Title = item.Title ?? "",
                Path = item.Path ?? "",
                Source = item.Source ?? "",
                Folder = item.Folder ?? "",
                Arguments = item.Arguments ?? "",
                WorkingDirectory = item.WorkingDirectory ?? "",
                Available = item.Available
            });
        }
        return result;
    }

    internal static int LaunchCatalogGame(string[] args, string resourcesDir, out string output)
    {
        string id = "";
        string revision = "";
        bool openFolder = false;
        for (int i = 1; i < args.Length; i++)
        {
            string arg = args[i] ?? "";
            if (string.Equals(arg, "-OpenFolder", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "--open-folder", StringComparison.OrdinalIgnoreCase))
            {
                openFolder = true;
            }
            else if (string.Equals(arg, "-Id", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                id = args[++i] ?? "";
            }
            else if (string.Equals(arg, "-Revision", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                revision = args[++i] ?? "";
            }
            else if (arg.Length > 0 && arg[0] != '-')
            {
                if (string.IsNullOrEmpty(id)) id = arg;
                else if (string.IsNullOrEmpty(revision)) revision = arg;
            }
        }

        string suiteRoot = Path.GetFullPath(Path.Combine(resourcesDir, ".."));
        string gameListPath = Path.Combine(suiteRoot, "Games", "GameList.inc");
        string jsonCachePath = Path.Combine(resourcesDir, "Cache", "game_library.json");
        string target, launchArgs, workDir;
        return LaunchCatalogGame(id, revision, openFolder, gameListPath, jsonCachePath, false,
            out output, out target, out launchArgs, out workDir);
    }

    internal static int LaunchCatalogGame(string id, string revision, bool openFolder,
        string gameListPath, string jsonCachePath, bool dryRun,
        out string output, out string launchedTarget, out string launchedArgs, out string launchedWorkDir)
    {
        launchedTarget = null;
        launchedArgs = null;
        launchedWorkDir = null;

        if (string.IsNullOrEmpty(id) || !GameIdPattern.IsMatch(id))
        {
            output = "GAMEHUB:FAILED Invalid game identifier.";
            return 1;
        }
        if (!string.IsNullOrEmpty(revision) && !RevisionPattern.IsMatch(revision))
        {
            output = "GAMEHUB:FAILED Invalid library revision.";
            return 1;
        }

        string published = (!string.IsNullOrEmpty(gameListPath) && File.Exists(gameListPath))
            ? File.ReadAllText(gameListPath, Encoding.UTF8)
            : "";
        string publishedRevision = ParseGameLibraryRevision(published);
        string currentRevision = !string.IsNullOrEmpty(publishedRevision) ? publishedRevision : "legacy";
        if (!string.IsNullOrEmpty(revision) && !string.Equals(revision, currentRevision, StringComparison.Ordinal))
        {
            output = "GAMEHUB:STALE";
            return 2;
        }

        List<CatalogGameEntry> games;
        if (!string.IsNullOrEmpty(publishedRevision))
        {
            games = ParseGeneratedGamesFromInc(published);
        }
        else if (!string.IsNullOrEmpty(jsonCachePath) && File.Exists(jsonCachePath))
        {
            bool jsonHasRevision;
            List<CatalogGameEntry> jsonGames = ParseGamesFromJson(File.ReadAllText(jsonCachePath, Encoding.UTF8), out jsonHasRevision);
            games = jsonHasRevision ? ParseGeneratedGamesFromInc(published) : jsonGames;
        }
        else
        {
            games = ParseGeneratedGamesFromInc(published);
        }

        CatalogGameEntry entry = null;
        for (int i = 0; i < games.Count; i++)
        {
            if (string.Equals(games[i].Id, id, StringComparison.Ordinal))
            {
                entry = games[i];
                break;
            }
        }
        if (entry == null)
        {
            output = "GAMEHUB:FAILED Game unavailable. Scan to retry or correct its override.";
            return 1;
        }

        if (openFolder)
        {
            if (string.IsNullOrEmpty(entry.Folder))
            {
                output = "GAMEHUB:FAILED No installation folder is recorded for this game.";
                return 1;
            }
            if (!Directory.Exists(entry.Folder))
            {
                output = "GAMEHUB:FAILED Installation folder is unavailable.";
                return 1;
            }
            launchedTarget = entry.Folder;
            if (!dryRun) Process.Start(new ProcessStartInfo(entry.Folder) { UseShellExecute = true });
            output = "GAMEHUB:FOLDER";
            return 0;
        }

        if (!entry.Available)
        {
            output = "GAMEHUB:FAILED Game unavailable. Scan to retry or correct its override.";
            return 1;
        }
        if (!string.IsNullOrEmpty(entry.Folder) && !Directory.Exists(entry.Folder))
        {
            output = "GAMEHUB:FAILED Installation folder is unavailable.";
            return 1;
        }
        if (string.IsNullOrEmpty(entry.Path))
        {
            output = "GAMEHUB:FAILED Launch target is missing. Scan or correct its override.";
            return 1;
        }

        bool isUri = GameUriPattern.IsMatch(entry.Path);
        if (!isUri)
        {
            if (!File.Exists(entry.Path))
            {
                output = "GAMEHUB:FAILED Launch target is missing. Scan or correct its override.";
                return 1;
            }
            if (!string.IsNullOrEmpty(entry.WorkingDirectory) && !Directory.Exists(entry.WorkingDirectory))
            {
                output = "GAMEHUB:FAILED Working directory is missing.";
                return 1;
            }
        }

        launchedTarget = entry.Path;
        launchedArgs = !string.IsNullOrEmpty(entry.Arguments) ? entry.Arguments : null;
        launchedWorkDir = (!isUri && !string.IsNullOrEmpty(entry.WorkingDirectory)) ? entry.WorkingDirectory : null;

        if (!dryRun)
        {
            var psi = new ProcessStartInfo(entry.Path);
            psi.UseShellExecute = true;
            if (launchedArgs != null) psi.Arguments = launchedArgs;
            if (launchedWorkDir != null) psi.WorkingDirectory = launchedWorkDir;
            Process.Start(psi);
        }

        output = "GAMEHUB:LAUNCHED";
        return 0;
    }
}
