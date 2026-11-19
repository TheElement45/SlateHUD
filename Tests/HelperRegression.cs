using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Compiled alongside SlateHUDHelper.cs with /main:HelperRegression; never starts the daemon.
class HelperRegression
{
    static object Call(string name, params object[] args)
    {
        var methods = typeof(SlateHUDHelper).GetMethods(BindingFlags.NonPublic | BindingFlags.Static);
        for (int i = 0; i < methods.Length; i++)
            if (methods[i].Name == name && methods[i].GetParameters().Length == args.Length)
                return methods[i].Invoke(null, args);
        throw new MissingMethodException("SlateHUDHelper." + name);
    }

    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    static int Main(string[] args)
    {
        try
        {
            bool cancelledMedia = false;
            var stalledMedia = new TaskCompletionSource<int>();
            var deadline = Stopwatch.StartNew();
            try
            {
                SlateHUDHelper.Bounded(stalledMedia.Task, 30, () => cancelledMedia = true).GetAwaiter().GetResult();
                throw new Exception("Stalled media operation completed without timing out");
            }
            catch (TimeoutException) { }
            Check(cancelledMedia && deadline.ElapsedMilliseconds < 2000, "Media timeout did not cancel promptly");
            stalledMedia.SetException(new IOException("Late media failure"));
            Check(SlateHUDHelper.Bounded(Task.FromResult(42), 1000, () => { throw new Exception("Unexpected cancellation"); })
                .GetAwaiter().GetResult() == 42, "Media loop could not recover after timeout");
            var failedMedia = new TaskCompletionSource<int>();
            failedMedia.SetException(new IOException("Player disconnected"));
            try
            {
                SlateHUDHelper.Bounded(failedMedia.Task, 1000, () => { }).GetAwaiter().GetResult();
                throw new Exception("Media failure was swallowed");
            }
            catch (IOException) { }
            Console.WriteLine("PASS: Bounded media calls, cancellation, failure propagation and recovery");

            string artworkJson = "{\"results\":[{\"trackName\":\"Wrong Song\",\"artistName\":\"Artist\",\"artworkUrl100\":\"https://example.com/wrong.png\"}," +
                "{\"trackName\":\"Song!\",\"artistName\":\"Artist\",\"artworkUrl100\":\"https://example.com/correct.png\"}]}";
            Check(SlateHUDHelper.MatchingArtwork(artworkJson, "song", "ARTIST") == "https://example.com/correct.png", "Validated artwork result was not selected");
            Check(SlateHUDHelper.MatchingArtwork(artworkJson, "Song", "Other Artist") == null, "Wrong artist replaced artwork");
            Check(SlateHUDHelper.MatchingArtwork(artworkJson, "Podcast episode", "Artist") == null, "Unrelated title replaced artwork");
            Check(SlateHUDHelper.MatchingArtwork(artworkJson, "Song", "Unknown Artist") == null, "Unknown artist accepted an unverified match");
            Check(SlateHUDHelper.MatchingArtwork("{\"results\":[]}", "Song", "Artist") == null, "Empty search returned artwork");
            var helperFlags = BindingFlags.Static | BindingFlags.NonPublic;
            foreach (string field in new[] { "onlineLookupKey", "onlineArtworkTrack", "activeCoverPath", "staleCoverHash" })
                typeof(SlateHUDHelper).GetField(field, helperFlags).SetValue(null, "old");
            SlateHUDHelper.InvalidateArtwork();
            foreach (string field in new[] { "onlineLookupKey", "onlineArtworkTrack", "activeCoverPath", "staleCoverHash" })
                Check((string)typeof(SlateHUDHelper).GetField(field, helperFlags).GetValue(null) == "", "Refresh retained " + field);
            var refreshedSchedule = (SlateHUDHelper.CoverSchedule)typeof(SlateHUDHelper).GetField("coverSchedule", helperFlags).GetValue(null);
            Check(refreshedSchedule.Due("same track", 0, DateTime.UtcNow), "Manual refresh did not force an artwork read");

            SlateHUDHelper.ConfigureTls();
            Check((ServicePointManager.SecurityProtocol & (SecurityProtocolType.Tls | SecurityProtocolType.Tls11)) == 0,
                "Legacy TLS 1.0/1.1 protocols remained enabled");
            Check((ServicePointManager.SecurityProtocol & SecurityProtocolType.Tls12) == SecurityProtocolType.Tls12,
                "TLS 1.2 was not enabled");

            var stalledReq = (HttpWebRequest)WebRequest.Create("https://itunes.apple.com/search?term=test");
            var httpDeadline = Stopwatch.StartNew();
            try
            {
                SlateHUDHelper.FetchHttpBytesAsync(stalledReq, 30, r => new TaskCompletionSource<byte[]>().Task).GetAwaiter().GetResult();
                throw new Exception("Stalled HTTP artwork request completed without timing out");
            }
            catch (TimeoutException) { }
            Check(httpDeadline.ElapsedMilliseconds < 2000, "HTTP artwork timeout did not fire promptly");
            bool reqAborted = false;
            try
            {
                stalledReq.GetResponseAsync().GetAwaiter().GetResult();
            }
            catch (WebException wex)
            {
                reqAborted = wex.Status == WebExceptionStatus.RequestCanceled;
            }
            Check(reqAborted, "Timed-out HTTP artwork request was not aborted");

            SlateHUDHelper.UpdateTrackIdentity("player\tSong A\tArtist\tAlbum", "Song A", "Artist", "Album");
            int genA = (int)typeof(SlateHUDHelper).GetField("artworkGeneration", helperFlags).GetValue(null);
            SlateHUDHelper.UpdateTrackIdentity("player\tSong B\tOther\tAlbum2", "Song B", "Other", "Album2");
            int genB = (int)typeof(SlateHUDHelper).GetField("artworkGeneration", helperFlags).GetValue(null);
            Check(!SlateHUDHelper.TryCommitOnlineArtwork(genA, "player\tSong A\tArtist\tAlbum", "cover_a.png", "hashA"),
                "Stale online artwork commit succeeded after track change");
            Check((string)typeof(SlateHUDHelper).GetField("activeCoverPath", helperFlags).GetValue(null) == "",
                "Stale online artwork overwrote activeCoverPath");
            Check(SlateHUDHelper.TryCommitOnlineArtwork(genB, "player\tSong B\tOther\tAlbum2", "cover_b.png", "hashB"),
                "Current online artwork commit failed");
            Check((string)typeof(SlateHUDHelper).GetField("activeCoverPath", helperFlags).GetValue(null) == "cover_b.png",
                "Current online artwork did not update activeCoverPath");
            SlateHUDHelper.InvalidateArtwork();
            Check(!SlateHUDHelper.TryCommitOnlineArtwork(genB, "player\tSong B\tOther\tAlbum2", "cover_late.png", "hashLate"),
                "Late online artwork commit succeeded after InvalidateArtwork");

            var procField = typeof(SlateHUDHelper).GetField("rainmeterProc", helperFlags);
            var originalProc = (Process)procField.GetValue(null);
            var exited = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { CreateNoWindow = true, UseShellExecute = false });
            int exitedId = exited.Id;
            exited.WaitForExit();
            try
            {
                procField.SetValue(null, exited);
                uint refreshedPid = SlateHUDHelper.GetActiveRainmeterPid();
                Check(refreshedPid != (uint)exitedId, "GetActiveRainmeterPid returned exited process ID");
            }
            finally
            {
                var currentProc = (Process)procField.GetValue(null);
                if (currentProc != null && !object.ReferenceEquals(currentProc, originalProc))
                    try { currentProc.Dispose(); } catch { }
                procField.SetValue(null, originalProc);
                try { exited.Dispose(); } catch { }
            }
            Console.WriteLine("PASS: Conservative artwork matching, thread-safe generation guard, TLS/timeout enforcement, and stale PID refresh");
            string root = args[0];
            var publisher = new SlateHUDHelper.SnapshotPublisher();
            string snapshotPath = Path.Combine(root, "publisher.txt");
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 100, 2), "Initial snapshot failed");
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 101, 2) &&
                File.ReadAllText(snapshotPath).StartsWith("UPDATED=100\n"), "Unchanged snapshot rewritten early");
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 102, 2) &&
                File.ReadAllText(snapshotPath).StartsWith("UPDATED=102\n"), "Heartbeat not renewed");
            Check(publisher.Publish(snapshotPath, "CONNECTED=0", 102, 2) &&
                File.ReadAllText(snapshotPath).EndsWith("CONNECTED=0"), "State change was delayed");
            using (var locked = new FileStream(snapshotPath, FileMode.Open, FileAccess.Read, FileShare.None))
                Check(!publisher.Publish(snapshotPath, "CONNECTED=1", 103, 2), "Locked write unexpectedly succeeded");
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 103, 2) &&
                File.ReadAllText(snapshotPath).EndsWith("CONNECTED=1"), "Failed write was not retried");
            File.Delete(snapshotPath);
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 103, 2) && File.Exists(snapshotPath), "Deleted snapshot not restored");
            Check(publisher.Publish(snapshotPath, "CONNECTED=1", 90, 2) &&
                File.ReadAllText(snapshotPath).StartsWith("UPDATED=90\n"), "Clock rollback suppressed heartbeat");
            Console.WriteLine("PASS: Snapshot throttling, immediate changes, failed-write retry, deletion and clock rollback");
            string notes = Path.Combine(root, "Notes");
            Call("InitializeNotes", notes);
            Check(File.ReadAllText(Path.Combine(notes, "Settings.inc")).Contains("CurrentPage=1"), "Missing initial tab");
            for (int page = 1; page <= 3; page++)
            {
                string text = File.ReadAllText(Path.Combine(notes, "Data", "Page" + page + ".inc"));
                Check(text.Contains("PageTitle=Page " + page) && text.Contains("Note5=\r\nStatus5=0"), "Incomplete page");
            }
            string personal = Path.Combine(notes, "Data", "Page1.inc");
            string settings = Path.Combine(notes, "Settings.inc");
            byte[] original = new UTF8Encoding(true).GetBytes("[Variables]\r\nNote1=Personal note: \u96e8\r\nStatus1=1\r\n");
            File.WriteAllBytes(personal, original);
            File.WriteAllText(settings, "[Variables]\r\nCurrentPage=3\r\n");
            File.Delete(Path.Combine(notes, "Data", "Page2.inc"));
            Call("InitializeNotes", notes);
            Check(Convert.ToBase64String(File.ReadAllBytes(personal)) == Convert.ToBase64String(original), "Personal data changed");
            Check(File.ReadAllText(settings).Contains("CurrentPage=3"), "Active tab changed");
            Check(File.Exists(Path.Combine(notes, "Data", "Page2.inc")), "Missing page not repaired");
            string resDir = Path.Combine(root, "Resources");
            string userSettingsPath = Path.Combine(resDir, "UserSettings.inc");
            SlateHUDHelper.EnsureUserSettings(resDir);
            Check(File.Exists(userSettingsPath) && File.ReadAllText(userSettingsPath).Contains("[Variables]"),
                "UserSettings.inc was not initialized with [Variables]");
            File.WriteAllText(userSettingsPath, "[Variables]\r\nCurrentTheme=TokyoNight\r\n");
            SlateHUDHelper.EnsureUserSettings(resDir);
            Check(File.ReadAllText(userSettingsPath).Contains("CurrentTheme=TokyoNight"),
                "EnsureUserSettings overwrote existing UserSettings.inc");
            Console.WriteLine("PASS: Notes and UserSettings creation and preservation");

            byte rOut, gOut, bOut;
            foreach (byte[] darkSample in new[] { new byte[] { 16, 38, 76 }, new byte[] { 76, 74, 72 }, new byte[] { 0, 0, 0 }, new byte[] { 108, 111, 157 } })
            {
                SlateHUDHelper.ClampAccentLuminance(darkSample[0], darkSample[1], darkSample[2], out rOut, out gOut, out bOut);
                double lumDark = SlateHUDHelper.RelativeLuminance(rOut, gOut, bOut);
                Check(lumDark >= 0.238 && lumDark <= 0.685,
                    "Dark Windows accent luminance out of safe range: " + lumDark);
            }
            SlateHUDHelper.ClampAccentLuminance(245, 245, 245, out rOut, out gOut, out bOut);
            double lumBright = SlateHUDHelper.RelativeLuminance(rOut, gOut, bOut);
            Check(lumBright >= 0.238 && lumBright <= 0.685,
                "Bright Windows accent luminance was not capped below white: " + lumBright);
            string winInc = SlateHUDHelper.BuildWindowsAccentInclude(0, 120, 215);
            Check(winInc.Contains("WindowsAccentColor=") && winInc.Contains("WindowsAccentGradient=270 |") &&
                winInc.Contains("WindowsAccentCardFill=") && winInc.Contains("WindowsAccentHistory2="),
                "BuildWindowsAccentInclude missing derived palette keys");
            Console.WriteLine("PASS: Windows accent luminance clamping and palette derivation");

            string gpu = (string)Call("GpuSnapshot", "0, 0, 8192, -1, -1, -1", new DateTimeOffset(1970, 1, 1, 0, 1, 40, TimeSpan.Zero));
            Check(gpu == "0, 0, 8192, -1, -1, -1\nUPDATED=100", "GPU heartbeat format or epoch incorrect");
            string gpuWithPage = (string)Call("GpuSnapshot", "0, 0, 8192, -1, -1, -1", new DateTimeOffset(1970, 1, 1, 0, 1, 40, TimeSpan.Zero), "1024,2048");
            Check(gpuWithPage == "0, 0, 8192, -1, -1, -1\nUPDATED=100\nPAGEFILE=1024,2048", "Pagefile snapshot format incorrect");
            Check((string)typeof(SlateHUDHelper).GetField("UnavailableGpu", BindingFlags.NonPublic | BindingFlags.Static).GetRawConstantValue() == "-1, -1, -1, -1, -1, -1", "Unavailable GPU was replaced with a plausible reading");
            Check(SlateHUDHelper.IsLoopbackEndpoint("http://127.0.0.1:8085/data.json") &&
                SlateHUDHelper.IsLoopbackEndpoint("http://localhost:8085/data.json") &&
                SlateHUDHelper.IsLoopbackEndpoint("http://localhost/data.json"),
                "Valid LHM loopback endpoint was rejected");
            Check(!SlateHUDHelper.IsLoopbackEndpoint("https://example.com/data.json") &&
                !SlateHUDHelper.IsLoopbackEndpoint("http://192.168.1.10:8085/data.json") &&
                !SlateHUDHelper.IsLoopbackEndpoint("file:///C:/test.json") &&
                !SlateHUDHelper.IsLoopbackEndpoint("http://user:pass@127.0.0.1:8085/data.json") &&
                !SlateHUDHelper.IsLoopbackEndpoint(""),
                "Non-loopback or unsafe LHM endpoint was accepted");

            var lhmCfg = SlateHUDHelper.ParseTelemetryConfig(
                "[Variables]\r\nSysSensorProvider=auto\r\nSysLhmEnabled=0\r\nLhmSource=auto\r\nLhmEndpoint=http://127.0.0.1:8085/data.json\r\n",
                "[Variables]\r\nSysSensorProvider=lhm\r\nLhmSource=http\r\nLhmEndpoint=http://localhost:9090/data.json\r\n");
            Check(lhmCfg.Provider == "lhm" && lhmCfg.LhmEnabled && lhmCfg.LhmSource == "http" &&
                lhmCfg.LhmEndpoint == "http://localhost:9090/data.json",
                "TelemetryConfig override parsing failed");
            var unsafeCfg = SlateHUDHelper.ParseTelemetryConfig(
                "SysSensorProvider=bogus\nSysLhmEnabled=1\n",
                "LhmEndpoint=http://10.0.0.5:8085/data.json\n");
            Check(unsafeCfg.Provider == "auto" && unsafeCfg.LhmEnabled &&
                unsafeCfg.LhmEndpoint == "http://127.0.0.1:8085/data.json",
                "Invalid telemetry config did not fall back safely");

            string intelAmdJson = "{\"Text\":\"Sensor\",\"Children\":[{\"Text\":\"PC\",\"Children\":[" +
                "{\"Text\":\"Intel Core i7\",\"HardwareId\":\"/intelcpu/0\",\"ImageURL\":\"images_icon/cpu.png\",\"Children\":[" +
                "{\"Text\":\"Temperatures\",\"Children\":[" +
                "{\"Text\":\"Distance to TjMax\",\"Value\":\"20.0 °C\"}," +
                "{\"Text\":\"Core Average\",\"Value\":\"58.0 °C\"}," +
                "{\"Text\":\"CPU Package\",\"Value\":\"64.5 °C\"}]}]}," +
                "{\"Text\":\"AMD Radeon RX 7800 XT\",\"HardwareId\":\"/gpu-amd/0\",\"ImageURL\":\"images_icon/ati.png\",\"Children\":[" +
                "{\"Text\":\"Loads\",\"Children\":[{\"Text\":\"GPU Core\",\"Value\":\"42.0 %\"}]}," +
                "{\"Text\":\"Temperatures\",\"Children\":[{\"Text\":\"GPU Hot Spot\",\"Value\":\"72.0 °C\"},{\"Text\":\"GPU Core\",\"Value\":\"61.0 °C\"}]}," +
                "{\"Text\":\"Data\",\"Children\":[{\"Text\":\"GPU Memory Used\",\"Value\":\"2.0 GB\"}]}," +
                "{\"Text\":\"SmallData\",\"Children\":[{\"Text\":\"GPU Memory Total\",\"Value\":\"8192.0 MB\"}]}," +
                "{\"Text\":\"Powers\",\"Children\":[{\"Text\":\"GPU Package\",\"Value\":\"145.0 W\"}]}," +
                "{\"Text\":\"Controls\",\"Children\":[{\"Text\":\"GPU Fan\",\"Value\":\"55.0 %\"}]}," +
                "{\"Text\":\"Fans\",\"Children\":[{\"Text\":\"GPU Fan\",\"Value\":\"1450 RPM\"}]}]}]}]}";
            var intelAmdSamples = SlateHUDHelper.ParseLhmJson(intelAmdJson);
            var intelAmdRes = SlateHUDHelper.SelectLhmTelemetry(intelAmdSamples);
            Check(intelAmdRes.Reachable && intelAmdRes.HasCpuTemp && Math.Abs(intelAmdRes.CpuTempC - 64.5) < 0.01 &&
                intelAmdRes.CpuTempName == "CPU Package", "Intel CPU Package selection failed");
            Check(intelAmdRes.HasGpu && intelAmdRes.GpuUsage == 42 && intelAmdRes.GpuVramUsedMiB == 2048 &&
                intelAmdRes.GpuVramTotalMiB == 8192 && intelAmdRes.GpuTempC == 61 &&
                intelAmdRes.GpuPowerW == 145 && intelAmdRes.GpuFan == 55 && intelAmdRes.GpuFanUnit == "%",
                "AMD GPU JSON parsing or selection failed");
            string fullGpuSnap = SlateHUDHelper.GpuSnapshot("-1, -1, -1, -1, -1, -1",
                new DateTimeOffset(1970, 1, 1, 0, 1, 40, TimeSpan.Zero), "1024,2048",
                SlateHUDHelper.CpuTempLine(intelAmdRes), SlateHUDHelper.LhmGpuLine(intelAmdRes));
            Check(fullGpuSnap.Contains("\nPAGEFILE=1024,2048") &&
                fullGpuSnap.Contains("\nCPUTEMP=64.5|CPU Package") &&
                fullGpuSnap.Contains("\nLHMGPU=42, 2048, 8192, 61, 145, 55, %"),
                "Extended LHM GpuSnapshot format incorrect: " + fullGpuSnap);

            string amdIntelJson = "{\"Text\":\"Sensor\",\"Children\":[{\"Text\":\"PC\",\"Children\":[" +
                "{\"Text\":\"AMD Ryzen 7\",\"HardwareId\":\"/amdcpu/0\",\"Children\":[" +
                "{\"Text\":\"Temperatures\",\"Children\":[" +
                "{\"Text\":\"Core Average\",\"Value\":\"52.0 °C\"}," +
                "{\"Text\":\"Core (Tctl/Tdie)\",\"Value\":\"140.0 °F\"}]}]}," +
                "{\"Text\":\"Intel Arc\",\"HardwareId\":\"/gpu-intel/0\",\"Children\":[" +
                "{\"Text\":\"Loads\",\"Children\":[{\"Text\":\"D3D 3D\",\"Value\":\"35.0 %\"}]}," +
                "{\"Text\":\"Temperatures\",\"Children\":[{\"Text\":\"GPU Core\",\"Value\":\"55.0 °C\"}]}," +
                "{\"Text\":\"Fans\",\"Children\":[{\"Text\":\"GPU Fan\",\"Value\":\"1450 RPM\"}]}]}]}]}";
            var amdIntelRes = SlateHUDHelper.SelectLhmTelemetry(SlateHUDHelper.ParseLhmJson(amdIntelJson));
            Check(amdIntelRes.HasCpuTemp && Math.Abs(amdIntelRes.CpuTempC - 60.0) < 0.01 &&
                amdIntelRes.CpuTempName == "Core (Tctl/Tdie)", "AMD Tctl/Tdie Fahrenheit conversion failed");
            Check(amdIntelRes.HasGpu && amdIntelRes.GpuUsage == 35 && amdIntelRes.GpuTempC == 55 &&
                amdIntelRes.GpuVramTotalMiB == -1 && amdIntelRes.GpuFan == 1450 && amdIntelRes.GpuFanUnit == "RPM",
                "Intel GPU RPM/partial VRAM parsing failed");
            Console.WriteLine("PASS: GPU heartbeat, unavailable sentinel, and LibreHardwareMonitor config/JSON telemetry");

            var monitor = new DisplayProbe.Rect { Left = -1920, Top = 0, Right = 0, Bottom = 1080 };
            var work = new DisplayProbe.Rect { Left = -1920, Top = 0, Right = 0, Bottom = 1040 };
            Check(DisplayProbe.IsCaptureOverlay("Microsoft-Windows-SnipperCaptureForm", "") &&
                DisplayProbe.IsCaptureOverlay("Windows.UI.Core.CoreWindow", "ScreenClippingHost") &&
                DisplayProbe.IsCaptureOverlay("WinUIDesktopWin32WindowClass", "SnippingTool") &&
                !DisplayProbe.IsCaptureOverlay("Chrome_WidgetWin_1", "game"), "Capture overlay identification failed");
            Check(DisplayProbe.CaptureCoversMonitor(new DisplayProbe.Rect { Left=-1920, Top=0, Right=1920, Bottom=1080 }, monitor) &&
                !DisplayProbe.CaptureCoversMonitor(work, monitor), "Spanning capture overlay or editor geometry failed");
            Check(DisplayProbe.CoversMonitor(monitor, monitor) && !DisplayProbe.CoversMonitor(work, monitor),
                "Fullscreen geometry confused monitor bounds with work-area bounds");
            string monitors = DisplayProbe.Snapshot(100, (uint)Process.GetCurrentProcess().Id, @"C:\Suite\");
            Check(monitors == null || (monitors.StartsWith("UPDATED=100\n") && monitors.Contains("\t") && monitors.Contains("\nSKINS=1\n")),
                "Malformed native display snapshot or missing skin inventory header");
            int pidLookups = 0, titleLookups = 0;
            var testSkins = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            Func<IntPtr, uint> fakePid = delegate(IntPtr w) { pidLookups++; return w == new IntPtr(30) ? 9999u : 4242u; };
            Func<IntPtr, string> fakeTitle = delegate(IntPtr w)
            {
                titleLookups++;
                if (w == new IntPtr(10)) return @"C:\Suite\Apps\Apps.ini";
                if (w == new IntPtr(20)) return @"C:\Suite\System\System.ini";
                if (w == new IntPtr(25)) return @"C:\Suite\NowPlaying.ini";
                return @"C:\Other\Widget.ini";
            };
            Check(DisplayProbe.InspectWindow(new IntPtr(1), new IntPtr(99), true, "Chrome_WidgetWin_1", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "Visible non-Rainmeter window was skipped before fullscreen check");
            Check(!DisplayProbe.InspectWindow(new IntPtr(2), new IntPtr(99), false, "Chrome_WidgetWin_1", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "Hidden non-Rainmeter window was treated as fullscreen candidate");
            Check(pidLookups == 0, "Owner PID was queried for non-Rainmeter windows");
            Check(!DisplayProbe.InspectWindow(new IntPtr(10), new IntPtr(99), false, "RainmeterMeterWindow", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "RainmeterMeterWindow was treated as fullscreen candidate");
            Check(!DisplayProbe.InspectWindow(new IntPtr(20), new IntPtr(99), true, "RainmeterMeterWindow", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "Visible RainmeterMeterWindow was treated as fullscreen candidate");
            Check(!DisplayProbe.InspectWindow(new IntPtr(25), new IntPtr(99), false, "RainmeterMeterWindow", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "Root RainmeterMeterWindow was treated as fullscreen candidate");
            Check(!DisplayProbe.InspectWindow(new IntPtr(30), new IntPtr(99), true, "RainmeterMeterWindow", 4242u, @"C:\Suite\", fakePid, fakeTitle, testSkins),
                "Foreign RainmeterMeterWindow was treated as fullscreen candidate");
            Check(pidLookups == 4 && titleLookups == 3, "RainmeterMeterWindow owner/title filtering was not applied");
            Check(testSkins.ContainsKey("Apps") && !testSkins["Apps"], "Hidden loaded Rainmeter skin was omitted from inventory");
            Check(testSkins.ContainsKey("System") && testSkins["System"], "Visible loaded Rainmeter skin was omitted from inventory");
            Check(testSkins.ContainsKey("Root") && !testSkins["Root"], "Hidden root Rainmeter skin was omitted from inventory");
            Console.WriteLine(monitors == null ? "PASS: Fullscreen geometry (native desktop unavailable)" :
                "PASS: Fullscreen geometry and native display snapshot");

            string snapshot = Path.Combine(root, "media.txt");
            Check((bool)Call("WriteFast", snapshot, "previous"), "Initial snapshot failed");
            Check(File.ReadAllText(snapshot) == "previous", "Initial snapshot disappeared");
            using (var locked = new FileStream(snapshot, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                Check(!(bool)Call("WriteFast", snapshot, "replacement"), "Locked replacement reported success");
                Check(File.ReadAllText(snapshot) == "previous", "Failed replacement damaged previous snapshot");
            }
            Check((bool)Call("WriteFast", snapshot, "replacement"), "Retry failed after unlocking");
            Check(File.ReadAllText(snapshot) == "replacement", "Retry did not publish new value");
            Console.WriteLine("PASS: Locked-write failure and retry");

            string coverFolder = Path.Combine(root, "covers");
            Directory.CreateDirectory(coverFolder);
            for (int i = 0; i < 12; i++)
            {
                string cover = Path.Combine(coverFolder, "cover_" + i.ToString("D2") + ".png");
                Check((bool)Call("WriteBytesFast", cover, new byte[] { 137, 80, 78, 71 }), "Atomic image publication failed");
                File.SetLastWriteTimeUtc(cover, DateTime.UtcNow.AddHours(-i));
            }
            string activeCover = Path.Combine(coverFolder, "cover_11.png");
            Call("CleanupCovers", coverFolder, activeCover, DateTime.UtcNow);
            Check(File.Exists(activeCover), "Current cover was deleted");
            Check(File.Exists(Path.Combine(coverFolder, "cover_07.png")), "Recent cover was deleted too early");
            Check(!File.Exists(Path.Combine(coverFolder, "cover_08.png")), "Old unused cover was not cleaned up");
            Console.WriteLine("PASS: Atomic album-art publication and deferred cleanup preserve current/recent images");

            byte[] earlyArtwork = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");
            byte[] updatedArtwork = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aBV8AAAAASUVORK5CYII=");
            string earlyPath = (string)Call("PublishCover", coverFolder, earlyArtwork);
            string updatedPath = (string)Call("PublishCover", coverFolder, updatedArtwork);
            Check(earlyPath != "" && updatedPath != "" && earlyPath != updatedPath,
                "Late artwork correction reused the old Rainmeter image path");
            Check(Convert.ToBase64String(File.ReadAllBytes(updatedPath)) == Convert.ToBase64String(updatedArtwork),
                "Corrected artwork was not published");
            Check(File.Exists(earlyPath), "Artwork correction removed a cover Rainmeter may still be using");
            DateTime originalWrite = DateTime.UtcNow.AddMinutes(-1);
            File.SetLastWriteTimeUtc(updatedPath, originalWrite);
            originalWrite = File.GetLastWriteTimeUtc(updatedPath);
            using (var locked = new FileStream(updatedPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                Check((string)Call("PublishCover", coverFolder, updatedArtwork) == updatedPath,
                    "Unchanged artwork was unnecessarily rewritten");
            Check(File.GetLastWriteTimeUtc(updatedPath) == originalWrite, "Unchanged artwork touched disk");
            Check((string)Call("PublishCover", coverFolder, earlyArtwork) == earlyPath,
                "Returning to an earlier image did not reuse its content cache");
            Check((string)Call("PublishCover", coverFolder, new byte[0]) == "", "Empty artwork reused a stale cover");
            Check((string)Call("PublishCover", coverFolder, (byte[])null) == "", "Missing artwork reused a stale cover");
            Check((string)Call("PublishCover", Path.Combine(root, "missing-cover-folder"), updatedArtwork) == "",
                "Failed artwork publication returned a nonexistent or stale path");
            Console.WriteLine("PASS: Delayed artwork correction, distinct image paths, cache reuse and publication failure");

            var schedule = new SlateHUDHelper.CoverSchedule();
            DateTime coverClock = new DateTime(2026, 11, 5, 0, 0, 0, DateTimeKind.Utc);
            int coverReads = 0;
            for (int elapsedSecond = 0; elapsedSecond <= 100; elapsedSecond++)
            {
                DateTime now = coverClock.AddSeconds(elapsedSecond);
                if (schedule.Due("same track", 0, now))
                {
                    coverReads++;
                    schedule.Attempted(now);
                    if (elapsedSecond == 2)
                        Check((string)Call("PublishCover", coverFolder, updatedArtwork) == updatedPath,
                            "Delayed thumbnail retry lost the corrected image");
                }
                else if (elapsedSecond == 2) throw new Exception("Missing early retry for delayed artwork");
            }
            Check(coverReads <= 10 && coverReads >= 7, "Artwork polling did not back off or lost fallback checks");
            Check(!schedule.Due("same track", 0, coverClock.AddSeconds(101)), "Stable artwork reread every poll");
            Check(schedule.Due("same track", 1, coverClock.AddSeconds(101)), "Artwork event with unchanged metadata was ignored");
            schedule.Attempted(coverClock.AddSeconds(101));
            Check(schedule.Due("next track", 1, coverClock.AddSeconds(101)), "Track change waited for fallback timer");
            Check((bool)Call("ConsumerNeeded", null, "Root") &&
                (bool)Call("ConsumerNeeded", "UPDATED=100\n", "System"), "Unknown inventory disabled telemetry");
            string consumers = "UPDATED=100\nSKINS=1\nSKIN\tRoot\t0\nSKIN\tGames\t1\n";
            Check((bool)Call("ConsumerNeeded", consumers, "Root"), "Hidden loaded media skin lost telemetry");
            Check(!(bool)Call("ConsumerNeeded", consumers, "System"), "Unloaded GPU widget kept sampling");
            Check(!(bool)Call("ConsumerNeeded", "UPDATED=100\nSKINS=1\n", "Root"), "Empty suite kept media sampling");
            Console.WriteLine("PASS: Artwork retries, event invalidation, slow fallback and loaded-widget demand");

            string first = new string('A', 8192) + "\u96e8";
            string second = new string('B', 8192) + "\u97f3";
            Check((bool)Call("WriteFast", snapshot, first), "Unicode snapshot failed");
            Exception readFailure = null;
            int reads = 0;
            using (var stop = new ManualResetEvent(false))
            using (var started = new ManualResetEvent(false))
            {
                var reader = new Thread(() =>
                {
                    try
                    {
                        while (!stop.WaitOne(0))
                        {
                            using (var stream = new FileStream(snapshot, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                            using (var text = new StreamReader(stream, Encoding.UTF8))
                            {
                                string value = text.ReadToEnd();
                                Check(value == first || value == second, "Concurrent reader saw incomplete snapshot");
                            }
                            Interlocked.Increment(ref reads);
                            started.Set();
                        }
                    }
                    catch (Exception ex) { readFailure = ex; started.Set(); }
                });
                reader.Start();
                try
                {
                    Check(started.WaitOne(5000), "Reader did not start");
                    int published = 0;
                    for (int i = 0; i < 200; i++)
                        if ((bool)Call("WriteFast", snapshot, i % 2 == 0 ? second : first)) published++;
                    Check(published > 0, "No concurrent snapshot could be published");
                }
                finally { stop.Set(); reader.Join(); }
            }
            if (readFailure != null) throw readFailure;
            Check(reads > 0, "Concurrent reader did not run");
            Check(Directory.GetFiles(root, "*.tmp").Length == 0, "Temporary snapshots leaked");

            TimeSpan start = TimeSpan.FromSeconds(100), end = TimeSpan.FromSeconds(300);
            Check((long)Call("CalculateSeekPosition", start, end, 25.0) == TimeSpan.FromSeconds(150).Ticks, "Seek ignored start offset");
            Check((long)Call("CalculateSeekPosition", start, end, -10.0) == start.Ticks, "Seek did not clamp lower bound");
            Check((long)Call("CalculateSeekPosition", start, end, 150.0) == end.Ticks, "Seek did not clamp upper bound");
            Check((long)Call("CalculateSeekPosition", TimeSpan.Zero, end, 50.0) == TimeSpan.FromSeconds(150).Ticks, "Zero-start seeking regressed");

            string wakeName = "Local\\SlateHUDHelper.TestWake." + Guid.NewGuid().ToString("N");
            Check(!(bool)Call("SignalMediaWake", wakeName), "Missing media wake event reported signalled");
            using (var wake = new EventWaitHandle(false, EventResetMode.AutoReset, wakeName))
            {
                Check((bool)Call("SignalMediaWake", wakeName) && wake.WaitOne(0), "Media wake event was not signalled");
                Check(!SlateHUDHelper.RequestCoverRefresh(wakeName + ".missing", wakeName), "Missing daemon accepted a refresh");
                using (var refresh = new EventWaitHandle(false, EventResetMode.AutoReset, wakeName + ".refresh"))
                {
                    Check(SlateHUDHelper.RequestCoverRefresh(wakeName + ".refresh", wakeName), "Refresh request failed");
                    Check(refresh.WaitOne(0) && wake.WaitOne(0), "Refresh did not deliver invalidation and wake signals");
                    Check(!refresh.WaitOne(0), "Refresh signal was not consumed once");
                }
            }
            string prefDir = Path.Combine(root, "prefs");
            Directory.CreateDirectory(prefDir);
            string prefFile = Path.Combine(prefDir, "media_player.txt");
            File.WriteAllText(prefFile, "Spotify.exe");
            using (var hold = new FileStream(prefFile, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                Check(!SlateHUDHelper.ResetPlayerPreference(prefDir, 2, 10), "Locked player preference reset falsely succeeded");
                Check(File.Exists(prefFile), "Locked player preference disappeared unexpectedly");
            }
            var unlockThread = new Thread(() =>
            {
                using (var transientHold = new FileStream(prefFile, FileMode.Open, FileAccess.Read, FileShare.Read))
                    Thread.Sleep(40);
            });
            unlockThread.Start();
            Thread.Sleep(10);
            Check(SlateHUDHelper.ResetPlayerPreference(prefDir, 8, 15), "Transient sharing violation prevented resetting player preference");
            unlockThread.Join();
            Check(!File.Exists(prefFile), "Player preference was not cleared");
            Check(SlateHUDHelper.ResetPlayerPreference(prefDir, 1, 5), "Missing player preference reset reported failure");
            var missingPref = SlateHUDHelper.ReadPlayerPreference(prefDir);
            Check(string.IsNullOrEmpty(missingPref.Id) && !missingPref.Locked, "Missing preference file did not return empty preference");

            Check(SlateHUDHelper.WritePlayerPreference(prefDir, "Spotify.exe", false), "Could not write unlocked preference");
            var unlockedPref = SlateHUDHelper.ReadPlayerPreference(prefDir);
            Check(unlockedPref.Id == "Spotify.exe" && !unlockedPref.Locked, "Unlocked preference was not read back");
            Check(SlateHUDHelper.WritePlayerPreference(prefDir, "Spotify.exe", true), "Could not write locked preference");
            var lockedPref = SlateHUDHelper.ReadPlayerPreference(prefDir);
            Check(lockedPref.Id == "Spotify.exe" && lockedPref.Locked, "Locked preference was not read back");

            var candidates = new SlateHUDHelper.SessionCandidate[]
            {
                new SlateHUDHelper.SessionCandidate { Id = "Spotify.exe", Playing = false, IsMusic = false, IsCurrent = false },
                new SlateHUDHelper.SessionCandidate { Id = "Brave.exe", Playing = true, IsMusic = false, IsCurrent = true }
            };
            Check(SlateHUDHelper.ChooseSessionIndex(candidates, unlockedPref) == 1,
                "Saved paused player overrode a currently playing session");
            Check(SlateHUDHelper.ChooseSessionIndex(candidates, lockedPref) == 0,
                "Explicitly locked player did not override another playing session");
            candidates[1].Playing = false;
            Check(SlateHUDHelper.ChooseSessionIndex(candidates, unlockedPref) == 0,
                "Saved paused player was not selected when all sessions were idle");

            string cmdMediaPath = Path.Combine(root, "cmd-media.txt");
            string cmdHealthPath = Path.Combine(root, "cmd-health.txt");
            File.WriteAllText(cmdMediaPath, "TITLE=Song A||STATE=1");
            int polls = 0;
            bool publishedDelayed = SlateHUDHelper.PublishCommandSnapshot(
                () =>
                {
                    int current = Interlocked.Increment(ref polls);
                    return Task.FromResult(current < 4 ? "TITLE=Song A||STATE=1" : "TITLE=Song A||STATE=2");
                },
                cmdMediaPath, cmdHealthPath, "TITLE=Song A||STATE=1", 600, 35).GetAwaiter().GetResult();
            Check(publishedDelayed && polls == 4 && File.ReadAllText(cmdMediaPath) == "TITLE=Song A||STATE=2",
                "Media command exited before delayed player update was published to snapshot");
            CheckSharedMemoryAndPipe();
            CheckLaunchCatalogGame(root);
            CheckNativePluginExports(root);

            Console.WriteLine("PASS: Notes creation/preservation, locked-write retry, concurrent snapshots, seek offsets, media wake and session reset");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool FreeLibrary(IntPtr hModule);

    static void CheckSharedMemoryAndPipe()
    {
        string mapName = "Local\\SlateHUDHelper.TestShared." + Guid.NewGuid().ToString("N");
        try
        {
            var streams = new Dictionary<string, string>
            {
                { "media.txt", "TITLE=Test Track||ARTIST=\u96e8||STATE=1||CAPS=1,1,1,1" },
                { "media-health.txt", "UPDATED=12345\nCONNECTED=1" },
                { "gpu.txt", "12, 1024, 8192, 55, 60, 30\nUPDATED=12345" },
                { "monitors.txt", "UPDATED=12345\nAA\texternal\t1\t100\t0\t0\t1920\t1080\t0\n" },
                { "helper-health.txt", "UPDATED=12345" }
            };
            foreach (KeyValuePair<string, string> kv in streams)
            {
                Check(SlateHUDHelper.PublishSharedStream(mapName, kv.Key, kv.Value),
                    "Failed to publish shared memory slot: " + kv.Key);
                string readBack = SlateHUDHelper.ReadSharedStream(mapName, kv.Key);
                Check(readBack == kv.Value, "Shared memory mismatch for " + kv.Key);
            }
            Check(!SlateHUDHelper.PublishSharedStream(mapName, "WindowsAccent.inc", "ignored"),
                "Unexpectedly published non-stream file to shared memory");
        }
        finally
        {
            SlateHUDHelper.CloseSharedState(mapName);
        }

        string pipeName = "SlateHUDHelper.TestPipe." + Guid.NewGuid().ToString("N");
        var cts = new CancellationTokenSource();
        Task serverTask = SlateHUDHelper.PipeServerLoop(pipeName, cts.Token);
        try
        {
            string reply = null;
            bool connected = false;
            for (int attempt = 0; attempt < 20; attempt++)
            {
                if (SlateHUDHelper.TrySendPipeCommand(pipeName, "ping", 200, out reply))
                {
                    connected = true;
                    break;
                }
                Thread.Sleep(25);
            }
            Check(connected && reply == "OK", "Pipe ping failed: " + (reply ?? "null"));

            string unknownReply = null;
            Check(SlateHUDHelper.TrySendPipeCommand(pipeName, "unknowncmd", 500, out unknownReply) &&
                  unknownReply != null && unknownReply.StartsWith("MEDIA:ERROR", StringComparison.Ordinal),
                "Unknown pipe command did not return MEDIA:ERROR");

            using (var silentClient = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.None))
            {
                silentClient.Connect(500);
                string replyAfterSilent = null;
                Check(SlateHUDHelper.TrySendPipeCommand(pipeName, "ping", 500, out replyAfterSilent) &&
                      replyAfterSilent == "OK",
                    "Silent pipe client blocked subsequent ping: " + (replyAfterSilent ?? "null"));
            }
        }
        finally
        {
            cts.Cancel();
            try { serverTask.Wait(1000); } catch { }
            cts.Dispose();
        }
    }

    static void CheckLaunchCatalogGame(string scratch)
    {
        string launchDir = Path.Combine(scratch, "launch-test");
        string gameFolder = Path.Combine(launchDir, "GameOne");
        string workDir = Path.Combine(gameFolder, "bin");
        Directory.CreateDirectory(workDir);
        string exePath = Path.Combine(workDir, "GameOne.exe");
        File.WriteAllText(exePath, "stub");

        string rev = "0123456789abcdef0123456789abcdef";
        string gameListPath = Path.Combine(launchDir, "GameList.inc");
        string jsonPath = Path.Combine(launchDir, "game_library.json");
        string validInc = string.Join("\r\n", new[]
        {
            "[Variables]",
            "GameLibraryRevision=" + rev,
            "Game1Category=RPG",
            "Game1Title=Game One",
            "Game1GameId=steam:101",
            "Game1GamePath=" + exePath,
            "Game1GameSource=steam:test",
            "Game1GameFolder=" + gameFolder,
            "Game1GameArguments=-fullscreen",
            "Game1GameWorkingDirectory=" + workDir,
            "Game1GameAvailable=1",
            "Game1GameConfidence=platform",
            "Game2Category=Other",
            "Game2Title=Unavailable Game",
            "Game2GameId=steam:102",
            "Game2GamePath=D:\\Missing\\nope.exe",
            "Game2GameSource=steam:test",
            "Game2GameFolder=",
            "Game2GameArguments=",
            "Game2GameWorkingDirectory=",
            "Game2GameAvailable=0",
            "Game2GameConfidence=platform"
        });
        File.WriteAllText(gameListPath, validInc, new UTF8Encoding(false));

        string outMsg, target, launchArgs, launchWorkDir;
        int rc = SlateHUDHelper.LaunchCatalogGame("steam:101", rev, false, gameListPath, jsonPath, true,
            out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc == 0 && outMsg == "GAMEHUB:LAUNCHED" && target == exePath &&
              launchArgs == "-fullscreen" && launchWorkDir == workDir,
            "Fast C# game launcher failed valid dry-run: " + outMsg);

        rc = SlateHUDHelper.LaunchCatalogGame("steam:101", rev, true, gameListPath, jsonPath, true,
            out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc == 0 && outMsg == "GAMEHUB:FOLDER" && target == gameFolder,
            "Fast C# game launcher failed open-folder dry-run: " + outMsg);

        rc = SlateHUDHelper.LaunchCatalogGame("steam:101", "fedcba9876543210fedcba9876543210", false,
            gameListPath, jsonPath, true, out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc != 0 && outMsg == "GAMEHUB:STALE",
            "Fast C# game launcher missed stale library revision: " + outMsg);

        rc = SlateHUDHelper.LaunchCatalogGame("steam:102", rev, false, gameListPath, jsonPath, true,
            out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc != 0 && outMsg.StartsWith("GAMEHUB:FAILED", StringComparison.Ordinal),
            "Fast C# game launcher launched an unavailable game: " + outMsg);

        rc = SlateHUDHelper.LaunchCatalogGame("bad id", rev, false, gameListPath, jsonPath, true,
            out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc != 0 && outMsg.StartsWith("GAMEHUB:FAILED", StringComparison.Ordinal),
            "Fast C# game launcher accepted an invalid ID: " + outMsg);

        // Legacy fallback using unrevisioned game_library.json
        File.WriteAllText(gameListPath, "[Variables]\r\nGameCardH=348\r\n", new UTF8Encoding(false));
        string escapedExe = exePath.Replace("\\", "\\\\");
        string escapedFolder = gameFolder.Replace("\\", "\\\\");
        File.WriteAllText(jsonPath,
            "{\"Version\":1,\"Revision\":\"\",\"Games\":[{\"Id\":\"hoyo:starrail\",\"Path\":\"" +
            escapedExe + "\",\"Folder\":\"" + escapedFolder + "\",\"Arguments\":\"\",\"WorkingDirectory\":\"\",\"Available\":true}]}",
            new UTF8Encoding(false));
        rc = SlateHUDHelper.LaunchCatalogGame("hoyo:starrail", "legacy", false, gameListPath, jsonPath, true,
            out outMsg, out target, out launchArgs, out launchWorkDir);
        Check(rc == 0 && outMsg == "GAMEHUB:LAUNCHED" && target == exePath,
            "Fast C# game launcher JSON fallback failed: " + outMsg);
    }

    static void CheckNativePluginExports(string scratch)
    {
        if (IntPtr.Size != 8) return;
        string dllPath = Path.GetFullPath(Path.Combine(scratch, "..", "..", "@Resources", "Plugins", "SlateHUD.dll"));
        Check(File.Exists(dllPath), "Missing compiled native plugin: " + dllPath);
        IntPtr mod = LoadLibrary(dllPath);
        Check(mod != IntPtr.Zero, "Failed to load SlateHUD.dll via LoadLibrary");
        try
        {
            string[] exports = new[] { "Initialize", "Reload", "Update", "GetString", "ExecuteBang", "Finalize" };
            for (int i = 0; i < exports.Length; i++)
            {
                Check(GetProcAddress(mod, exports[i]) != IntPtr.Zero,
                    "SlateHUD.dll missing export: " + exports[i]);
            }
        }
        finally
        {
            FreeLibrary(mod);
        }
    }
}
