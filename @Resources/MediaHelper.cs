using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Windows.Foundation;
using Windows.Media.Control;

partial class SlateHUDHelper
{
    const string MediaWakeName = "Local\\SlateHUDHelper.MediaWake";
    const string CoverRefreshName = "Local\\SlateHUDHelper.CoverRefresh";
    const string NoTrack = "TITLE=No Track Playing||ARTIST=Unknown Artist||STATE=0||POS=00:00||DUR=00:00||PROG=0||COVER=||PLAYER=||CAPS=0,0,0,0";

    // Playback position is shown this many ms ahead to cancel the delay between sampling and drawing.
    const int PositionLeadMs = 500;

    static bool SignalMediaWake(string eventName)
    {
        EventWaitHandle wake;
        if (!EventWaitHandle.TryOpenExisting(eventName, out wake)) return false;
        using (wake) return wake.Set();
    }

    internal static bool RequestCoverRefresh(string refreshName, string wakeName)
    {
        if (!SignalMediaWake(refreshName)) return false;
        SignalMediaWake(wakeName);
        return true;
    }

    internal struct PlayerPreference
    {
        public string Id;
        public bool Locked;
    }

    internal static PlayerPreference ReadPlayerPreference(string cacheFolder)
    {
        string preference = Path.Combine(cacheFolder, "media_player.txt");
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                using (var stream = new FileStream(preference, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    string raw = (reader.ReadToEnd() ?? "").Trim();
                    if (raw.Length == 0) return new PlayerPreference();
                    if (raw.StartsWith("LOCK=", StringComparison.OrdinalIgnoreCase))
                        return new PlayerPreference { Id = raw.Substring(5).Trim(), Locked = true };
                    if (raw.StartsWith("PREFER=", StringComparison.OrdinalIgnoreCase))
                        return new PlayerPreference { Id = raw.Substring(7).Trim(), Locked = false };
                    return new PlayerPreference { Id = raw, Locked = false };
                }
            }
            catch (FileNotFoundException) { return new PlayerPreference(); }
            catch (DirectoryNotFoundException) { return new PlayerPreference(); }
            catch (IOException) { if (attempt == 2) return new PlayerPreference(); Thread.Sleep(10); }
            catch (UnauthorizedAccessException) { return new PlayerPreference(); }
        }
        return new PlayerPreference();
    }

    internal static bool WritePlayerPreference(string cacheFolder, string id, bool locked)
    {
        if (string.IsNullOrWhiteSpace(id)) return false;
        Directory.CreateDirectory(cacheFolder);
        return WriteFast(Path.Combine(cacheFolder, "media_player.txt"), (locked ? "LOCK=" : "") + id.Trim());
    }

    internal static bool ResetPlayerPreference(string cacheFolder, int retries = 5, int delayMs = 25)
    {
        string preference = Path.Combine(cacheFolder, "media_player.txt");
        for (int attempt = 0; attempt <= retries; attempt++)
        {
            if (!File.Exists(preference)) return true;
            try
            {
                File.Delete(preference);
                if (!File.Exists(preference)) return true;
            }
            catch (FileNotFoundException) { return true; }
            catch (DirectoryNotFoundException) { return true; }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            if (attempt < retries && delayMs > 0) Thread.Sleep(delayMs);
        }
        return !File.Exists(preference);
    }

    static async Task MediaLoop()
    {
        GlobalSystemMediaTransportControlsSessionManager mgr = null;
        string lastMedia = null;
        var healthPublisher = new SnapshotPublisher();
        string mediaPath = Path.Combine(CacheDir, "media.txt");
        int tick = 0;
        bool followUp = false;
        using (var refresh = new EventWaitHandle(false, EventResetMode.AutoReset, CoverRefreshName))
        using (var wake = new EventWaitHandle(false, EventResetMode.AutoReset, MediaWakeName))
        while (true)
        {
            if (!mediaNeeded)
            {
                TrackMediaSession(null);
                mgr = null;
                lastMedia = null;
                followUp = false;
                await Task.Run(() => wake.WaitOne(1000));
                continue;
            }
            bool connected = false;
            try
            {
                if (refresh.WaitOne(0)) InvalidateArtwork();
                if (mgr == null) mgr = await AsTask(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
                string media = await BuildMediaStatus(mgr);
                connected = (media == lastMedia && File.Exists(mediaPath)) || WriteFast(mediaPath, media);
                if (connected) lastMedia = media;
            }
            catch
            {
                TrackMediaSession(null);
                mgr = null;
                if (lastMedia != NoTrack && WriteFast(mediaPath, NoTrack)) lastMedia = NoTrack;
            }

            healthPublisher.Publish(Path.Combine(CacheDir, "media-health.txt"),
                "CONNECTED=" + (connected ? "1" : "0"), UnixSeconds(DateTimeOffset.UtcNow), 2);
            if (tick++ % 60 == 0)
            {
                string currentCover;
                lock (artworkLock) { currentCover = activeCoverPath; }
                CleanupCovers(CacheDir, currentCover, DateTime.UtcNow);
            }
            int delay = followUp ? 150 : 1000;
            followUp = await Task.Run(() => wake.WaitOne(delay));
        }
    }

    // ------------------------------------------------------------------ SMTC helpers
    internal static async Task<T> Bounded<T>(Task<T> task, int timeoutMs, Action cancel)
    {
        using (var timer = new CancellationTokenSource())
        {
            if (await Task.WhenAny(task, Task.Delay(timeoutMs, timer.Token)) != task)
            {
                try { cancel(); } catch { }
                ObserveFailure(task);
                throw new TimeoutException("Media operation timed out");
            }
            timer.Cancel();
            return await task;
        }
    }

    static void ObserveFailure(Task task)
    {
        task.ContinueWith(t => { var ignored = t.Exception; }, TaskContinuationOptions.OnlyOnFaulted);
    }

    static Task<T> AsTask<T>(IAsyncOperation<T> operation)
    {
        var tcs = new TaskCompletionSource<T>();
        operation.Completed = (info, status) =>
        {
            try
            {
                if (status == AsyncStatus.Completed) tcs.TrySetResult(info.GetResults());
                else if (status == AsyncStatus.Error) tcs.TrySetException(info.ErrorCode);
                else tcs.TrySetCanceled();
            }
            catch (Exception ex) { tcs.TrySetException(ex); }
        };
        return Bounded(tcs.Task, 1500, () => operation.Cancel());
    }

    static bool IsMusicApp(string id)
    {
        return id.IndexOf("youtube", StringComparison.OrdinalIgnoreCase) >= 0 ||
               id.IndexOf("pear", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    internal struct SessionCandidate
    {
        public string Id;
        public bool Playing;
        public bool IsMusic;
        public bool IsCurrent;
    }

    internal static int ChooseSessionIndex(IList<SessionCandidate> candidates, PlayerPreference pref)
    {
        if (candidates == null || candidates.Count == 0) return -1;
        if (pref.Locked && !string.IsNullOrEmpty(pref.Id))
        {
            for (int i = 0; i < candidates.Count; i++)
                if (string.Equals(candidates[i].Id, pref.Id, StringComparison.OrdinalIgnoreCase)) return i;
        }
        if (!string.IsNullOrEmpty(pref.Id))
        {
            for (int i = 0; i < candidates.Count; i++)
                if (candidates[i].Playing && string.Equals(candidates[i].Id, pref.Id, StringComparison.OrdinalIgnoreCase)) return i;
        }
        for (int i = 0; i < candidates.Count; i++)
            if (candidates[i].Playing && candidates[i].IsMusic) return i;
        for (int i = 0; i < candidates.Count; i++)
            if (candidates[i].Playing) return i;
        if (!string.IsNullOrEmpty(pref.Id))
        {
            for (int i = 0; i < candidates.Count; i++)
                if (string.Equals(candidates[i].Id, pref.Id, StringComparison.OrdinalIgnoreCase)) return i;
        }
        for (int i = 0; i < candidates.Count; i++)
            if (candidates[i].IsMusic) return i;
        for (int i = 0; i < candidates.Count; i++)
            if (candidates[i].IsCurrent) return i;
        return 0;
    }

    static GlobalSystemMediaTransportControlsSession SelectBestSession(GlobalSystemMediaTransportControlsSessionManager mgr)
    {
        var sessions = mgr.GetSessions();
        if (sessions == null || sessions.Count == 0) return mgr.GetCurrentSession();
        var current = mgr.GetCurrentSession();
        var candidates = new SessionCandidate[sessions.Count];
        for (int i = 0; i < sessions.Count; i++)
        {
            var s = sessions[i];
            string id = s.SourceAppUserModelId ?? "";
            var pb = s.GetPlaybackInfo();
            candidates[i] = new SessionCandidate
            {
                Id = id,
                Playing = pb != null && pb.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                IsMusic = IsMusicApp(id),
                IsCurrent = current != null && string.Equals(id, current.SourceAppUserModelId, StringComparison.OrdinalIgnoreCase)
            };
        }
        int best = ChooseSessionIndex(candidates, ReadPlayerPreference(CacheDir));
        return best >= 0 && best < sessions.Count ? sessions[best] : (current ?? sessions[0]);
    }

    static string Clean(string input, string fallback)
    {
        if (string.IsNullOrWhiteSpace(input)) return fallback;
        return input.Replace("\r", " ").Replace("\n", " ").Replace("||", " ").Trim();
    }

    static string FormatTime(TimeSpan ts)
    {
        if (ts.TotalSeconds < 0) ts = TimeSpan.Zero;
        if (ts.TotalHours >= 1)
            return string.Format("{0}:{1:D2}:{2:D2}", (int)ts.TotalHours, ts.Minutes, ts.Seconds);
        return string.Format("{0:D2}:{1:D2}", (int)ts.TotalMinutes, ts.Seconds);
    }

    // Same line format the NowPlaying skin has always parsed.
    static async Task<string> BuildMediaStatus(GlobalSystemMediaTransportControlsSessionManager mgr)
    {
        if (mgr == null) return NoTrack;
        var session = SelectBestSession(mgr);
        TrackMediaSession(session);
        if (session == null) return NoTrack;

        var props = await AsTask(session.TryGetMediaPropertiesAsync());
        var pbInfo = session.GetPlaybackInfo();
        var timeline = session.GetTimelineProperties();

        string title = Clean(props != null ? props.Title : null, "No Track Playing");
        string artist = Clean(props != null ? props.Artist : null, "Unknown Artist");
        string album = props != null && !string.IsNullOrWhiteSpace(props.AlbumTitle) ? props.AlbumTitle.Trim() : "";
        string player = session.SourceAppUserModelId ?? "";

        string trackKey = player + "\t" + title + "\t" + artist + "\t" + album;
        UpdateTrackIdentity(trackKey, title, artist, album);

        int state = 0;
        if (pbInfo != null)
        {
            if (pbInfo.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing) state = 1;
            else if (pbInfo.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused) state = 2;
        }

        TimeSpan pos = TimeSpan.Zero, dur = TimeSpan.Zero;
        int prog = 0;
        if (timeline != null)
        {
            dur = timeline.EndTime - timeline.StartTime;
            pos = timeline.Position - timeline.StartTime;

            if (state == 1 && timeline.LastUpdatedTime != DateTimeOffset.MinValue)
            {
                var elapsed = DateTimeOffset.UtcNow - timeline.LastUpdatedTime;
                if (elapsed.TotalSeconds > 0 && elapsed.TotalSeconds < 3600) pos = pos + elapsed;
                pos = pos + TimeSpan.FromMilliseconds(PositionLeadMs);   // helper poll + skin read delay
            }
            if (dur.TotalSeconds > 0)
            {
                if (pos > dur) pos = dur;
                if (pos < TimeSpan.Zero) pos = TimeSpan.Zero;
                prog = (int)Math.Round((pos.TotalSeconds / dur.TotalSeconds) * 100.0);
            }
        }

        string coverKey = session.SourceAppUserModelId + "\n" + title + "\n" + artist + "\n" +
            (props == null ? "" : props.AlbumTitle) + "\n" + dur.Ticks.ToString(CultureInfo.InvariantCulture);
        DateTime coverTime = DateTime.UtcNow;
        int generation = Interlocked.CompareExchange(ref artworkVersion, 0, 0);

        bool shouldCheckCover = false;
        bool needSmtcRead = false;
        int smtcRequestGen = 0;
        lock (artworkLock)
        {
            shouldCheckCover = coverSchedule.Due(coverKey, generation, coverTime);
            if (shouldCheckCover)
            {
                smtcRequestGen = artworkGeneration;
                if (props != null && title != "No Track Playing")
                {
                    needSmtcRead = trackKey != onlineArtworkTrack || string.IsNullOrEmpty(activeCoverPath);
                }
                else
                {
                    activeCoverPath = "";
                    coverSchedule.Attempted(coverTime);
                }
            }
        }

        if (shouldCheckCover && props != null && title != "No Track Playing")
        {
            byte[] smtcBytes = needSmtcRead ? await ReadCoverBytes(props.Thumbnail) : null;
            string publishedPath = null;
            string smtcHash = null;
            if (needSmtcRead && smtcBytes != null && smtcBytes.Length > 0)
            {
                smtcHash = HashBytes(smtcBytes);
                bool isStale;
                lock (artworkLock)
                {
                    isStale = !string.IsNullOrEmpty(staleCoverHash) &&
                              string.Equals(smtcHash, staleCoverHash, StringComparison.OrdinalIgnoreCase);
                }
                if (!isStale) publishedPath = PublishCover(CacheDir, smtcBytes);
            }

            lock (artworkLock)
            {
                if (smtcRequestGen == artworkGeneration && string.Equals(trackKey, lastTrackKey, StringComparison.Ordinal))
                {
                    if (needSmtcRead && (trackKey != onlineArtworkTrack || string.IsNullOrEmpty(activeCoverPath)))
                    {
                        if (smtcBytes != null && smtcBytes.Length > 0)
                        {
                            if (!string.IsNullOrEmpty(staleCoverHash) && string.Equals(smtcHash, staleCoverHash, StringComparison.OrdinalIgnoreCase))
                            {
                                // Stale SMTC thumbnail from previous track detected! Discard it.
                                activeCoverPath = "";
                            }
                            else
                            {
                                activeCoverPath = publishedPath ?? "";
                                lastCoverHash = smtcHash;
                                staleCoverHash = "";
                            }
                        }
                        else
                        {
                            activeCoverPath = "";
                        }
                    }
                    coverSchedule.Attempted(coverTime);
                }
            }
        }

        bool isBrowser = IsBrowser(session.SourceAppUserModelId);
        // If SMTC provides no cover, or cover is stale, or player is a browser with low-res/stale thumbnail:
        // Trigger background online artwork lookup to fetch official high-res album cover.
        bool triggerOnline = false;
        string coverResult;
        lock (artworkLock)
        {
            if (title != "No Track Playing" && (string.IsNullOrEmpty(activeCoverPath) || isBrowser) && trackKey != onlineLookupKey)
            {
                onlineLookupKey = trackKey;
                triggerOnline = true;
            }
            coverResult = activeCoverPath;
        }
        if (triggerOnline) TriggerOnlineArtworkLookup(title, artist, trackKey);

        var controls = pbInfo != null ? pbInfo.Controls : null;
        string caps = controls == null ? "0,0,0,0" : string.Format("{0},{1},{2},{3}",
            controls.IsPreviousEnabled ? 1 : 0, controls.IsPlayPauseToggleEnabled ? 1 : 0,
            controls.IsNextEnabled ? 1 : 0, controls.IsPlaybackPositionEnabled && dur.TotalSeconds > 0 ? 1 : 0);
        return string.Format("TITLE={0}||ARTIST={1}||STATE={2}||POS={3}||DUR={4}||PROG={5}||COVER={6}||PLAYER={7}||CAPS={8}",
            title, artist, state, FormatTime(pos), FormatTime(dur), prog, coverResult,
            Clean(session.SourceAppUserModelId, "Media player"), caps);
    }

    static async Task<string> Status()
    {
        Directory.CreateDirectory(CacheDir);
        var mgr = await AsTask(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
        return await BuildMediaStatus(mgr);
    }

    // ------------------------------------------------------------------ one-shot controls
    static long CalculateSeekPosition(TimeSpan start, TimeSpan end, double percent)
    {
        percent = Math.Max(0, Math.Min(100, percent));
        return start.Ticks + (long)((end.Ticks - start.Ticks) * (percent / 100.0));
    }

    internal static async Task<bool> PublishCommandSnapshot(Func<Task<string>> pollMedia, string mediaPath,
        string healthPath, string baseline, int timeoutMs, int intervalMs)
    {
        var sw = Stopwatch.StartNew();
        string latest = null;
        bool changed = false;
        while (true)
        {
            try { latest = await pollMedia(); }
            catch { latest = null; }
            if (!string.IsNullOrEmpty(latest) && latest != baseline)
            {
                changed = true;
                break;
            }
            if (sw.ElapsedMilliseconds >= timeoutMs) break;
            if (intervalMs > 0) await Task.Delay(intervalMs);
        }
        bool published = false;
        if (!string.IsNullOrEmpty(latest))
        {
            string dir = Path.GetDirectoryName(mediaPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            published = WriteFast(mediaPath, latest);
            if (!string.IsNullOrEmpty(healthPath))
                WriteFast(healthPath,
                    "UPDATED=" + UnixSeconds(DateTimeOffset.UtcNow).ToString(CultureInfo.InvariantCulture) +
                    "\nCONNECTED=" + (published ? "1" : "0"));
        }
        SignalMediaWake(MediaWakeName);
        return changed && published;
    }

    static readonly SemaphoreSlim pipeControlGate = new SemaphoreSlim(1, 1);

    internal struct ControlResult
    {
        public bool Ok;
        public string Message;
    }

    static async Task<ControlResult> ExecuteControlCoreAsync(string[] args)
    {
        if (args == null || args.Length == 0 || string.IsNullOrWhiteSpace(args[0]))
            return new ControlResult { Ok = true, Message = "OK" };

        string cmd = args[0].ToLowerInvariant();
        string mediaPath = Path.Combine(CacheDir, "media.txt");
        string healthPath = Path.Combine(CacheDir, "media-health.txt");
        string baseline = ReadTextSafe(mediaPath);

        if (cmd == "refetchcover")
        {
            if (!RequestCoverRefresh(CoverRefreshName, MediaWakeName))
                return new ControlResult { Ok = false, Message = "MEDIA:ERROR Media helper is unavailable for artwork refresh" };
            return new ControlResult { Ok = true, Message = "OK" };
        }
        if (cmd == "resetplayer")
        {
            if (!ResetPlayerPreference(CacheDir))
                return new ControlResult { Ok = false, Message = "MEDIA:ERROR Could not reset player preference" };
            try
            {
                var resetMgr = await AsTask(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
                if (resetMgr != null)
                    await PublishCommandSnapshot(() => BuildMediaStatus(resetMgr), mediaPath, healthPath, baseline, 600, 40);
                else SignalMediaWake(MediaWakeName);
            }
            catch { SignalMediaWake(MediaWakeName); }
            return new ControlResult { Ok = true, Message = "OK" };
        }

        var mgr = await AsTask(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
        if (mgr == null) return new ControlResult { Ok = true, Message = "OK" };
        var session = SelectBestSession(mgr);
        if (session == null) return new ControlResult { Ok = true, Message = "OK" };

        if (cmd == "nextplayer")
        {
            var sessions = mgr.GetSessions();
            PlayerPreference currentPref = ReadPlayerPreference(CacheDir);
            for (int i = 0; i < sessions.Count; i++)
                if (sessions[i].SourceAppUserModelId == session.SourceAppUserModelId)
                {
                    var target = sessions[(i + 1) % sessions.Count];
                    if (!WritePlayerPreference(CacheDir, target.SourceAppUserModelId, currentPref.Locked))
                        return new ControlResult { Ok = false, Message = "MEDIA:ERROR Could not switch player preference" };
                    break;
                }
        }
        else if (cmd == "lockplayer")
        {
            PlayerPreference currentPref = ReadPlayerPreference(CacheDir);
            bool nextLock = !(currentPref.Locked &&
                string.Equals(currentPref.Id, session.SourceAppUserModelId, StringComparison.OrdinalIgnoreCase));
            if (!WritePlayerPreference(CacheDir, session.SourceAppUserModelId, nextLock))
                return new ControlResult { Ok = false, Message = "MEDIA:ERROR Could not lock player preference" };
        }
        else if (cmd == "playpause") await AsTask(session.TryTogglePlayPauseAsync());
        else if (cmd == "next") await AsTask(session.TrySkipNextAsync());
        else if (cmd == "prev") await AsTask(session.TrySkipPreviousAsync());
        else if (cmd == "seek" && args.Length > 1)
        {
            double pct;
            if (double.TryParse(args[1], NumberStyles.Any, CultureInfo.InvariantCulture, out pct) && !double.IsNaN(pct))
            {
                var tl = session.GetTimelineProperties();
                if (tl != null && tl.EndTime > tl.StartTime)
                {
                    await AsTask(session.TryChangePlaybackPositionAsync(CalculateSeekPosition(tl.StartTime, tl.EndTime, pct)));
                }
            }
        }
        await PublishCommandSnapshot(() => BuildMediaStatus(mgr), mediaPath, healthPath, baseline, 600, 40);
        return new ControlResult { Ok = true, Message = "OK" };
    }

    internal static async Task<string> ExecutePipeCommandAsync(string line, string pipeName)
    {
        if (string.IsNullOrWhiteSpace(line)) return "MEDIA:ERROR Empty command";
        string[] tokens = line.Trim().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length == 0) return "MEDIA:ERROR Empty command";
        string cmd = tokens[0].ToLowerInvariant();
        if (cmd == "ping") return "OK";

        if (cmd != "playpause" && cmd != "next" && cmd != "prev" && cmd != "seek" &&
            cmd != "nextplayer" && cmd != "lockplayer" && cmd != "resetplayer" && cmd != "refetchcover")
            return "MEDIA:ERROR Unknown pipe command";

        await pipeControlGate.WaitAsync();
        try
        {
            ControlResult res = await ExecuteControlCoreAsync(tokens);
            return res.Ok ? "OK" : (!string.IsNullOrEmpty(res.Message) ? res.Message : "MEDIA:ERROR Command failed");
        }
        catch (Exception ex)
        {
            return "MEDIA:ERROR " + ex.Message;
        }
        finally
        {
            pipeControlGate.Release();
        }
    }

    const int PipeReadTimeoutMs = 2000;
    const int PipeMaxLineLength = 1024;

    static PipeSecurity CreateCurrentUserPipeSecurity()
    {
        try
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                if (identity == null || identity.User == null) return null;
                var security = new PipeSecurity();
                security.AddAccessRule(new PipeAccessRule(
                    identity.User,
                    PipeAccessRights.ReadWrite | PipeAccessRights.CreateNewInstance,
                    AccessControlType.Allow));
                return security;
            }
        }
        catch
        {
            return null;
        }
    }

    static async Task HandlePipeClientAsync(NamedPipeServerStream server, string pipeName)
    {
        using (server)
        {
            try
            {
                string line;
                using (var reader = new StreamReader(server, Encoding.UTF8, false, 512, true))
                using (var timer = new CancellationTokenSource())
                {
                    Task<string> readTask = reader.ReadLineAsync();
                    if (await Task.WhenAny(readTask, Task.Delay(PipeReadTimeoutMs, timer.Token)) != readTask)
                    {
                        ObserveFailure(readTask);
                        return;
                    }
                    timer.Cancel();
                    line = await readTask;
                }
                if (line != null && line.Length > PipeMaxLineLength) return;

                string reply = await ExecutePipeCommandAsync(line, pipeName);
                var utf8NoBom = new UTF8Encoding(false);
                using (var writer = new StreamWriter(server, utf8NoBom, 512, true))
                {
                    writer.NewLine = "\n";
                    writer.WriteLine(reply);
                    writer.Flush();
                }
            }
            catch { }
        }
    }

    static Task PipeServerLoop()
    {
        return PipeServerLoop(PipeName, CancellationToken.None);
    }

    internal static async Task PipeServerLoop(string pipeName, CancellationToken token)
    {
        PipeSecurity pipeSecurity = CreateCurrentUserPipeSecurity();
        while (!token.IsCancellationRequested)
        {
            NamedPipeServerStream server = null;
            CancellationTokenRegistration reg = default(CancellationTokenRegistration);
            bool retryDelay = false;
            try
            {
                server = new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous,
                    1024,
                    1024,
                    pipeSecurity);

                if (token.CanBeCanceled)
                {
                    NamedPipeServerStream closingServer = server;
                    reg = token.Register(() => { try { closingServer.Dispose(); } catch { } });
                }

                await Task.Factory.FromAsync(server.BeginWaitForConnection, server.EndWaitForConnection, null);
            }
            catch
            {
                reg.Dispose();
                if (server != null) { try { server.Dispose(); } catch { } }
                if (token.IsCancellationRequested) break;
                retryDelay = true;
            }

            if (retryDelay)
            {
                await Task.Delay(50);
                continue;
            }

            reg.Dispose();
            var accepted = server;
            var ignored = Task.Run(() => HandlePipeClientAsync(accepted, pipeName));
        }
    }

    internal static bool TrySendPipeCommand(string pipeName, string commandLine, int connectTimeoutMs, out string response)
    {
        response = null;
        if (string.IsNullOrWhiteSpace(pipeName) || string.IsNullOrWhiteSpace(commandLine)) return false;
        try
        {
            using (var client = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.None))
            {
                client.Connect(connectTimeoutMs);
                var utf8NoBom = new UTF8Encoding(false);
                using (var writer = new StreamWriter(client, utf8NoBom, 512, true))
                using (var reader = new StreamReader(client, Encoding.UTF8, false, 512, true))
                {
                    writer.NewLine = "\n";
                    writer.WriteLine(commandLine.Trim());
                    writer.Flush();
                    response = reader.ReadLine();
                    return response != null;
                }
            }
        }
        catch
        {
            response = null;
            return false;
        }
    }

    static async Task<int> Control(string[] args)
    {
        if (args == null || args.Length == 0 || string.IsNullOrWhiteSpace(args[0])) return 0;

        string commandLine = string.Join(" ", args);
        string pipeReply;
        if (!isDaemonProcess && TrySendPipeCommand(PipeName, commandLine, 150, out pipeReply))
        {
            if (string.Equals(pipeReply, "OK", StringComparison.Ordinal)) return 0;
            if (!string.IsNullOrEmpty(pipeReply)) Console.Write(pipeReply);
            return 1;
        }

        ControlResult res = await ExecuteControlCoreAsync(args);
        if (!res.Ok)
        {
            if (!string.IsNullOrEmpty(res.Message)) Console.Write(res.Message);
            return 1;
        }
        return 0;
    }
}
