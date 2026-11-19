using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Microsoft.Win32;

// Reads the active Windows desktop in physical pixels, in the helper's session.
static class DisplayProbe
{
    static int topologyVersion, cachedVersion = -1;
    static DateTime targetsExpire;
    static Dictionary<string, TargetName> cachedTargets;
    static readonly Dictionary<string, string> identities = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    static DisplayProbe()
    {
        // SystemEvents supplies its own message thread. The timed fallback also
        // covers environments that cannot subscribe to desktop notifications.
        try { SystemEvents.DisplaySettingsChanged += delegate { Interlocked.Increment(ref topologyVersion); }; }
        catch { }
    }
    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        public int Left, Top, Right, Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MonitorInfo
    {
        public int Size;
        public Rect Bounds, Work;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }

    // DISPLAYCONFIG identifiers and paths. LUID is two 32-bit fields.
    [StructLayout(LayoutKind.Sequential)]
    struct Endpoint { public uint AdapterLow, AdapterHigh, Id; }
    [StructLayout(LayoutKind.Sequential)]
    struct Path
    {
        public Endpoint Source;
        public uint SourceMode, SourceFlags;
        public Endpoint Target;
        public uint TargetMode, Technology, Rotation, Scaling, RefreshNumerator, RefreshDenominator,
            ScanLineOrdering, TargetAvailable, TargetFlags, Flags;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Request { public uint Type, Size; public Endpoint Endpoint; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SourceName
    {
        public Request Header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct TargetName
    {
        public Request Header;
        public uint Flags, Technology;
        public ushort EdidManufacturer, EdidProduct;
        public uint Connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string FriendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DevicePath;
    }
    // DISPLAYCONFIG_MODE_INFO is required by QueryDisplayConfig. We use GetMonitorInfo
    // for geometry and never read the returned union.
    [StructLayout(LayoutKind.Sequential, Size = 64)]
    struct Mode { public uint InfoType; }

    delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, ref Rect rect, IntPtr data);
    delegate bool WindowCallback(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback callback, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] Path[] pathInfo,
        ref uint modes, [Out] Mode[] modeInfo, IntPtr topology);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName request);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName request);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("shcore.dll")] static extern int GetScaleFactorForMonitor(IntPtr monitor, out int scale);
    [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int capacity);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern uint GetWindowStyle(IntPtr window, int index);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out uint value, int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect value, int size);

    class Display
    {
        public MonitorInfo Info;
        public string Id, Role;
        public int Scale;
        public bool Occupied;
    }

    static Path[] ActivePaths()
    {
        const uint active = 2;
        for (int retry = 0; retry < 3; retry++)
        {
            uint paths, modes;
            if (GetDisplayConfigBufferSizes(active, out paths, out modes) != 0) break;
            var result = new Path[paths];
            int error = QueryDisplayConfig(active, ref paths, result, ref modes, new Mode[modes], IntPtr.Zero);
            if (error == 0) { Array.Resize(ref result, (int)paths); return result; }
            if (error != 122) break; // Topology changed between calls.
        }
        return new Path[0];
    }

    static Dictionary<string, TargetName> Targets()
    {
        int version = Interlocked.CompareExchange(ref topologyVersion, 0, 0);
        if (cachedTargets != null && cachedVersion == version && DateTime.UtcNow < targetsExpire)
            return cachedTargets;
        var targets = new Dictionary<string, TargetName>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in ActivePaths())
        {
            if (path.TargetAvailable == 0) continue;
            var source = new SourceName { Header = new Request { Type = 1, Size = (uint)Marshal.SizeOf(typeof(SourceName)), Endpoint = path.Source } };
            var target = new TargetName { Header = new Request { Type = 2, Size = (uint)Marshal.SizeOf(typeof(TargetName)), Endpoint = path.Target } };
            if (DisplayConfigGetDeviceInfo(ref source) != 0 || DisplayConfigGetDeviceInfo(ref target) != 0) continue;
            TargetName existing;
            // Cloned targets share one desktop rectangle. Prefer the built-in panel.
            if (!targets.TryGetValue(source.Device, out existing) || Internal(target.Technology))
                targets[source.Device] = target;
        }
        cachedTargets = targets;
        cachedVersion = version;
        targetsExpire = DateTime.UtcNow.AddSeconds(targets.Count == 0 ? 5 : 30);
        identities.Clear();
        return targets;
    }

    static bool Internal(uint technology)
    {
        return technology == 0x80000000 || technology == 6 || technology == 11 || technology == 13;
    }

    static string Identity(string device)
    {
        string identity;
        if (identities.TryGetValue(device, out identity)) return identity;
        using (var hash = SHA256.Create())
            identity = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(device.ToUpperInvariant())), 0, 12).Replace("-", "");
        identities[device] = identity;
        return identity;
    }

    internal static bool CoversMonitor(Rect frame, Rect monitor)
    {
        const int edgeTolerance = 2;
        return Math.Abs(frame.Left - monitor.Left) <= edgeTolerance &&
            Math.Abs(frame.Top - monitor.Top) <= edgeTolerance &&
            Math.Abs(frame.Right - monitor.Right) <= edgeTolerance &&
            Math.Abs(frame.Bottom - monitor.Bottom) <= edgeTolerance;
    }

    static bool Fullscreen(IntPtr window, Rect monitor, StringBuilder className)
    {
        Rect frame;
        if (DwmGetWindowAttribute(window, 9, out frame, 16) != 0 && !GetWindowRect(window, out frame)) return false;
        if (!CoversMonitor(frame, monitor)) return false;
        uint cloaked;
        if (DwmGetWindowAttribute(window, 14, out cloaked, 4) == 0 && cloaked != 0) return false;
        className.Clear();
        GetClassName(window, className, className.Capacity);
        switch (className.ToString())
        {
            case "Progman": case "WorkerW": case "Shell_TrayWnd": case "Shell_SecondaryTrayWnd":
            case "RainmeterMeterWindow":
                return false;
        }
        // An ordinary maximized window can cover the monitor when the taskbar
        // auto-hides. Its caption or resizing frame distinguishes that case.
        const uint framed = 0x00c40000; // WS_CAPTION | WS_THICKFRAME
        if (IsZoomed(window) && (GetWindowStyle(window, -16) & framed) != 0) return false;
        return true;
    }

    internal static bool IsCaptureOverlay(string cls, string processName)
    {
        return cls == "Microsoft-Windows-SnipperCaptureForm" || cls == "ScreenClippingHost" ||
            string.Equals(processName, "ScreenClippingHost", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(processName, "SnippingTool", StringComparison.OrdinalIgnoreCase);
    }

    internal static bool CaptureCoversMonitor(Rect frame, Rect bounds)
    {
        return frame.Left <= bounds.Left + 2 && frame.Top <= bounds.Top + 2 &&
            frame.Right >= bounds.Right - 2 && frame.Bottom >= bounds.Bottom - 2;
    }

    static bool CaptureOverlay(IntPtr window, string cls, Rect bounds)
    {
        Rect frame;
        if (!GetWindowRect(window, out frame) || !CaptureCoversMonitor(frame, bounds)) return false;
        uint cloaked;
        if (DwmGetWindowAttribute(window, 14, out cloaked, 4) == 0 && cloaked != 0) return false;
        if (IsCaptureOverlay(cls, "")) return true;
        uint pid;
        GetWindowThreadProcessId(window, out pid);
        try {
            using (var process = System.Diagnostics.Process.GetProcessById((int)pid))
                return IsCaptureOverlay(cls, process.ProcessName);
        } catch (ArgumentException) { return false; }
        catch (System.ComponentModel.Win32Exception) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    internal static bool InspectWindow(IntPtr window, IntPtr shell, bool visible, string cls, uint rainmeterPid,
        string suitePath, Func<IntPtr, uint> getOwnerPid, Func<IntPtr, string> getTitle, Dictionary<string, bool> skins)
    {
        if (window == shell) return false;
        if (cls == "RainmeterMeterWindow")
        {
            if (rainmeterPid != 0 && getOwnerPid(window) == rainmeterPid)
            {
                string title = getTitle(window);
                if (title != null && title.StartsWith(suitePath, StringComparison.OrdinalIgnoreCase) &&
                    title.EndsWith(".ini", StringComparison.OrdinalIgnoreCase))
                {
                    string config = System.IO.Path.GetDirectoryName(title.Substring(suitePath.Length));
                    if (string.IsNullOrEmpty(config)) config = "Root";
                    bool prior;
                    skins.TryGetValue(config, out prior);
                    skins[config] = prior || visible;
                }
            }
            return false;
        }
        return visible;
    }

    internal static string Snapshot(long updated, uint rainmeterPid, string suitePath)
    {
        IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4)); // Per-monitor aware V2.
        try
        {
            var targets = Targets();
            var displays = new Dictionary<IntPtr, Display>();
            bool enumerated = EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
                delegate(IntPtr handle, IntPtr dc, ref Rect bounds, IntPtr data)
                {
                    var info = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
                    if (!GetMonitorInfo(handle, ref info) || info.Work.Width <= 0 || info.Work.Height <= 0) return true;
                    TargetName target;
                    bool known = targets.TryGetValue(info.Device, out target);
                    if (!known) targetsExpire = DateTime.MinValue;
                    int scale;
                    if (GetScaleFactorForMonitor(handle, out scale) != 0) scale = 100;
                    displays[handle] = new Display
                    {
                        Info = info, Scale = scale,
                        Id = Identity(known && !string.IsNullOrEmpty(target.DevicePath) ? target.DevicePath : info.Device),
                        Role = known ? (Internal(target.Technology) ? "laptop" : "external") : "unknown"
                    };
                    return true;
                }, IntPtr.Zero);
            if (!enumerated || displays.Count == 0) return null;

            var className = new StringBuilder(128);
            var windowTitle = new StringBuilder(1024);
            var skins = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            IntPtr shell = GetShellWindow();
            Func<IntPtr, uint> getOwnerPid = delegate(IntPtr w)
            {
                uint owner;
                GetWindowThreadProcessId(w, out owner);
                return owner;
            };
            Func<IntPtr, string> getTitle = delegate(IntPtr w)
            {
                windowTitle.Clear();
                GetWindowText(w, windowTitle, windowTitle.Capacity);
                return windowTitle.ToString();
            };
            bool capturing = false;
            bool valid = EnumWindows(delegate(IntPtr window, IntPtr data)
            {
                if (window == shell) return true;
                bool visible = IsWindowVisible(window);
                if (!visible && rainmeterPid == 0) return true;
                className.Clear();
                GetClassName(window, className, className.Capacity);
                string cls = className.ToString();
                if (!InspectWindow(window, shell, visible, cls, rainmeterPid, suitePath, getOwnerPid, getTitle, skins))
                    return true;
                if (IsIconic(window)) return true;
                Display display;
                if (displays.TryGetValue(MonitorFromWindow(window, 0), out display)) {
                    if (CaptureOverlay(window, cls, display.Info.Bounds)) capturing = true;
                    else if (!display.Occupied) display.Occupied = Fullscreen(window, display.Info.Bounds, className);
                }
                return true;
            }, IntPtr.Zero);
            var snapshot = new StringBuilder();
            snapshot.AppendFormat(CultureInfo.InvariantCulture, "UPDATED={0}\n", updated);
            foreach (var display in displays.Values)
            {
                var area = display.Info.Work;
                snapshot.AppendFormat(CultureInfo.InvariantCulture, "{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}\t{8}\n",
                    display.Id, display.Role, display.Info.Flags & 1, display.Scale, area.Left, area.Top,
                    area.Width, area.Height, valid && !capturing ? (display.Occupied ? "1" : "0") : "?");
            }
            if (valid && rainmeterPid != 0)
            {
                snapshot.Append("SKINS=1\n");
                foreach (var skin in skins)
                    snapshot.Append("SKIN\t").Append(skin.Key).Append('\t').Append(skin.Value ? '1' : '0').Append('\n');
            }
            return snapshot.ToString();
        }
        finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
}
