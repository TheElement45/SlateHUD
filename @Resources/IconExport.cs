using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IconExport
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string displayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string typeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHDefExtractIcon(string file, int index, uint flags, out IntPtr large, out IntPtr small, uint size);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SHGetFileInfo(string path, uint attrs, out SHFILEINFO info, uint size, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHGetFileInfoW")]
    static extern IntPtr SHGetFileInfoPidl(IntPtr pidl, uint attrs, out SHFILEINFO info, uint size, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHParseDisplayName(string path, IntPtr binding, out IntPtr pidl, uint attrs, out uint found);

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr icon);

    public static void SaveFallback(string output)
    {
        using (var bitmap = SystemIcons.Application.ToBitmap()) bitmap.Save(output, ImageFormat.Png);
    }

    public static void Fallback(string output)
    {
        SaveFallback(output);
    }

    public static bool Save(string shortcut, string source, int index, string output)
    {
        IntPtr large = IntPtr.Zero, small = IntPtr.Zero;
        try
        {
            if (!String.IsNullOrEmpty(source) && source.StartsWith("shell:AppsFolder\\", StringComparison.OrdinalIgnoreCase))
            {
                IntPtr pidl;
                uint found;
                if (SHParseDisplayName(source, IntPtr.Zero, out pidl, 0, out found) == 0)
                {
                    try
                    {
                        SHFILEINFO info;
                        SHGetFileInfoPidl(pidl, 0, out info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x108);
                        large = info.hIcon;
                    }
                    finally { Marshal.FreeCoTaskMem(pidl); }
                }
            }
            else if (!String.IsNullOrEmpty(source))
            {
                SHDefExtractIcon(source, index, 0, out large, out small, 64);
            }
            if (large == IntPtr.Zero && !String.IsNullOrEmpty(shortcut))
            {
                SHFILEINFO info;
                SHGetFileInfo(shortcut, 0, out info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x100);
                large = info.hIcon;
            }
            if (large == IntPtr.Zero) return false;
            using (var icon = Icon.FromHandle(large))
            using (var bitmap = icon.ToBitmap())
                bitmap.Save(output, ImageFormat.Png);
            return true;
        }
        finally
        {
            if (large != IntPtr.Zero) DestroyIcon(large);
            if (small != IntPtr.Zero) DestroyIcon(small);
        }
    }

    public static bool Save(string source, int index, string output)
    {
        return Save(null, source, index, output);
    }
}

public static class AppIconExport
{
    public static void SaveFallback(string output) { IconExport.SaveFallback(output); }
    public static bool Save(string shortcut, string source, int index, string output) { return IconExport.Save(shortcut, source, index, output); }
}

public static class GameIconExport
{
    public static void Fallback(string output) { IconExport.Fallback(output); }
    public static void SaveFallback(string output) { IconExport.SaveFallback(output); }
    public static bool Save(string shortcut, string source, int index, string output) { return IconExport.Save(shortcut, source, index, output); }
    public static bool Save(string source, int index, string output) { return IconExport.Save(source, index, output); }
}
