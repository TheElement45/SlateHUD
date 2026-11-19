using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Windows.Media.Control;
using Windows.Storage.Streams;

partial class SlateHUDHelper
{
    // ------------------------------------------------------------------ Artwork & cover cache
    const int ArtworkHttpTimeoutMs = 4000;
    const int MaxHttpArtworkBytes = 16 * 1024 * 1024;
    static readonly object artworkLock = new object();

    static string activeCoverPath = "";
    static string lastTrackKey = "";
    static string lastTrackArtist = "";
    static string lastTrackAlbum = "";
    static string lastCoverHash = "";
    static string staleCoverHash = "";
    static string onlineLookupKey = "";
    static string onlineArtworkTrack = "";

    static CoverSchedule coverSchedule = new CoverSchedule();
    static GlobalSystemMediaTransportControlsSession coverSession;
    static bool coverSubscribed;
    static int artworkVersion;
    static int artworkGeneration;

    static void CleanupCovers(string folder, string activePath, DateTime now)
    {
        try
        {
            var files = new DirectoryInfo(folder).GetFiles("cover_*.png");
            Array.Sort(files, (a, b) => b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc));
            // Keep the current image, eight recent covers, and every image younger
            // than five minutes. Rainmeter may still be painting the previous track.
            for (int i = 8; i < files.Length; i++)
                if (!files[i].FullName.Equals(activePath, StringComparison.OrdinalIgnoreCase) &&
                    files[i].LastWriteTimeUtc < now.AddMinutes(-5))
                    try { files[i].Delete(); } catch { }
        }
        catch { }
    }

    static string HashBytes(byte[] bytes)
    {
        if (bytes == null || bytes.Length == 0) return "";
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
    }

    static string PublishCover(string folder, byte[] bytes)
    {
        if (bytes == null || bytes.Length == 0) return "";
        string hash = HashBytes(bytes);
        // A new picture needs a new path so Rainmeter also invalidates its image cache.
        // Content identity avoids title/artist collisions and poisoned track caches.
        string path = Path.Combine(folder, "cover_" + hash + ".png");
        return File.Exists(path) || WriteBytesFast(path, bytes) ? path : "";
    }

    static async Task<byte[]> ReadCoverBytes(IRandomAccessStreamReference thumbnail)
    {
        if (thumbnail == null) return null;
        try
        {
            using (var stream = await AsTask(thumbnail.OpenReadAsync()))
            {
                // Refuse empty or unreasonable thumbnails before allocating a buffer.
                if (stream.Size == 0 || stream.Size > 32 * 1024 * 1024) return null;
                uint size = (uint)stream.Size;
                using (var reader = new DataReader(stream.GetInputStreamAt(0)))
                {
                    if (await AsTask(reader.LoadAsync(size)) != size) return null;
                    byte[] bytes = new byte[size];
                    reader.ReadBytes(bytes);
                    return bytes;
                }
            }
        }
        catch { return null; }
    }

    static async Task<string> ReadCover(IRandomAccessStreamReference thumbnail)
    {
        byte[] bytes = await ReadCoverBytes(thumbnail);
        return bytes != null ? PublishCover(CacheDir, bytes) : "";
    }

    static bool IsBrowser(string id)
    {
        if (string.IsNullOrEmpty(id)) return false;
        string lower = id.ToLowerInvariant();
        return lower.Contains("brave") || lower.Contains("chrome") || lower.Contains("edge") ||
               lower.Contains("firefox") || lower.Contains("opera") || lower.Contains("vivaldi") ||
               lower.Contains("browser");
    }

    static string ArtworkIdentity(string value)
    {
        return Regex.Replace((value ?? "").Normalize().ToLowerInvariant(), @"[^\p{L}\p{N}]", "");
    }

    internal static string MatchingArtwork(string json, string title, string artist)
    {
        if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(artist) || artist == "Unknown Artist") return null;
        var data = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
        object raw;
        if (data == null || !data.TryGetValue("results", out raw)) return null;
        var results = raw as object[];
        if (results == null) return null;
        foreach (var result in results)
        {
            var item = result as Dictionary<string, object>;
            object track, performer, artwork;
            if (item == null || !item.TryGetValue("trackName", out track) ||
                !item.TryGetValue("artistName", out performer) || !item.TryGetValue("artworkUrl100", out artwork)) continue;
            if (ArtworkIdentity(track as string) != ArtworkIdentity(title) ||
                ArtworkIdentity(performer as string) != ArtworkIdentity(artist)) continue;
            Uri uri;
            if (Uri.TryCreate(artwork as string, UriKind.Absolute, out uri) && uri.Scheme == "https") return uri.AbsoluteUri;
        }
        return null;
    }

    internal static void ConfigureTls()
    {
        try { ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288; }
        catch { ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12; }
    }

    static async Task<byte[]> ReadResponseBytesAsync(HttpWebRequest req)
    {
        using (var resp = await req.GetResponseAsync())
        {
            if (req.RequestUri != null &&
                string.Equals(req.RequestUri.Scheme, "https", StringComparison.OrdinalIgnoreCase) &&
                (resp.ResponseUri == null || !string.Equals(resp.ResponseUri.Scheme, "https", StringComparison.OrdinalIgnoreCase)))
                return null;
            using (var stream = resp.GetResponseStream())
            using (var ms = new MemoryStream())
            {
                if (stream == null) return new byte[0];
                byte[] buffer = new byte[8192];
                int read;
                while ((read = await stream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                {
                    if (ms.Length + read > MaxHttpArtworkBytes) return null;
                    ms.Write(buffer, 0, read);
                }
                return ms.ToArray();
            }
        }
    }

    internal static Task<byte[]> FetchHttpBytesAsync(HttpWebRequest req, int timeoutMs = ArtworkHttpTimeoutMs,
        Func<HttpWebRequest, Task<byte[]>> transport = null)
    {
        return Bounded((transport ?? ReadResponseBytesAsync)(req), timeoutMs, () => req.Abort());
    }

    internal static void UpdateTrackIdentity(string trackKey, string title, string artist, string album)
    {
        lock (artworkLock)
        {
            if (trackKey == lastTrackKey) return;
            artworkGeneration++;
            if (title == "No Track Playing")
            {
                lastCoverHash = "";
                staleCoverHash = "";
                activeCoverPath = "";
            }
            else
            {
                bool sameSource = (!string.IsNullOrWhiteSpace(lastTrackArtist) && string.Equals(artist, lastTrackArtist, StringComparison.OrdinalIgnoreCase)) ||
                                  (!string.IsNullOrWhiteSpace(lastTrackAlbum) && string.Equals(album, lastTrackAlbum, StringComparison.OrdinalIgnoreCase));
                if (!sameSource && !string.IsNullOrEmpty(lastCoverHash))
                {
                    // Track changed to a different artist/album. Any thumbnail matching the previous track's
                    // cover hash is stale (lingering in Windows SMTC because Chromium never clears it).
                    staleCoverHash = lastCoverHash;
                }
                activeCoverPath = "";
                lastCoverHash = "";
            }
            lastTrackKey = trackKey;
            lastTrackArtist = artist;
            lastTrackAlbum = album;
            onlineArtworkTrack = "";
        }
    }

    internal static bool TryCommitOnlineArtwork(int requestGeneration, string trackKey, string path, string coverHash)
    {
        if (string.IsNullOrEmpty(path)) return false;
        lock (artworkLock)
        {
            if (requestGeneration != artworkGeneration || !string.Equals(lastTrackKey, trackKey, StringComparison.Ordinal))
                return false;
            activeCoverPath = path;
            onlineArtworkTrack = trackKey;
            lastCoverHash = coverHash ?? "";
            staleCoverHash = "";
            return true;
        }
    }

    static async Task<byte[]> FetchOnlineArtworkAsync(string title, string artist)
    {
        try
        {
            ConfigureTls();
            string cleanTitle = Regex.Replace(title, @"\s*[\(\[][^\)\]]*(?:official|video|audio|lyric|remaster|hd|4k|mv|prod\.|feat\.)[^\)\]]*[\)\]]", "", RegexOptions.IgnoreCase).Trim();

            string effectiveArtist = artist;
            string effectiveTitle = cleanTitle;
            int dashIdx = cleanTitle.IndexOf(" - ");
            if (dashIdx > 0)
            {
                string lead = cleanTitle.Substring(0, dashIdx).Trim();
                string trail = cleanTitle.Substring(dashIdx + 3).Trim();
                string aLow = (artist ?? "").ToLowerInvariant();
                if (aLow.Contains("rising") || aLow.Contains("records") || aLow.Contains("vevo") ||
                    aLow.Contains("topic") || aLow.Contains("youtube") || aLow.Contains("unknown") ||
                    aLow.Contains("music") || aLow.Contains("official") || string.IsNullOrWhiteSpace(artist))
                {
                    effectiveArtist = lead;
                    effectiveTitle = trail;
                }
            }

            var queries = new List<string>();
            if (!string.IsNullOrWhiteSpace(effectiveArtist) && !string.IsNullOrWhiteSpace(effectiveTitle))
                queries.Add(effectiveArtist + " " + effectiveTitle);
            if (!string.IsNullOrWhiteSpace(cleanTitle) && !queries.Contains(cleanTitle))
                queries.Add(cleanTitle);

            foreach (var q in queries)
            {
                string query = q.Trim();
                if (string.IsNullOrEmpty(query)) continue;
                string url = "https://itunes.apple.com/search?term=" + Uri.EscapeDataString(query) + "&media=music&entity=song&limit=5";

                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Timeout = ArtworkHttpTimeoutMs;
                req.ReadWriteTimeout = ArtworkHttpTimeoutMs;
                req.MaximumAutomaticRedirections = 3;
                req.UserAgent = "SlateHUD/2.4";

                byte[] jsonBytes = await FetchHttpBytesAsync(req, ArtworkHttpTimeoutMs);
                if (jsonBytes == null || jsonBytes.Length == 0) continue;
                string json = Encoding.UTF8.GetString(jsonBytes);

                string matchedUrl = MatchingArtwork(json, effectiveTitle, effectiveArtist);
                if (matchedUrl != null)
                {
                    string artUrl = matchedUrl;
                    artUrl = Regex.Replace(artUrl, @"100x100bb(\.[a-z]+)$", "512x512bb$1", RegexOptions.IgnoreCase);

                    var imgReq = (HttpWebRequest)WebRequest.Create(artUrl);
                    imgReq.Timeout = ArtworkHttpTimeoutMs;
                    imgReq.ReadWriteTimeout = ArtworkHttpTimeoutMs;
                    imgReq.MaximumAutomaticRedirections = 3;
                    imgReq.UserAgent = "SlateHUD/2.4";
                    byte[] bytes = await FetchHttpBytesAsync(imgReq, ArtworkHttpTimeoutMs);
                    if (bytes != null && bytes.Length > 0) return bytes;
                }
            }
            return null;
        }
        catch { return null; }
    }

    static void TriggerOnlineArtworkLookup(string title, string artist, string trackKey)
    {
        int requestGeneration;
        lock (artworkLock)
        {
            requestGeneration = artworkGeneration;
        }
        Task.Run(async () =>
        {
            try
            {
                byte[] bytes = await FetchOnlineArtworkAsync(title, artist);
                if (bytes == null || bytes.Length == 0) return;
                lock (artworkLock)
                {
                    if (requestGeneration != artworkGeneration || !string.Equals(lastTrackKey, trackKey, StringComparison.Ordinal))
                        return;
                }
                string path = PublishCover(CacheDir, bytes);
                string hash = HashBytes(bytes);
                if (TryCommitOnlineArtwork(requestGeneration, trackKey, path, hash))
                {
                    SignalMediaWake(MediaWakeName);
                }
            }
            catch { }
        });
    }

    // Keep short retries after track/events for players that publish their old
    // picture first, then use a slow fallback for players that omit events.
    internal sealed class CoverSchedule
    {
        string identity;
        int version;
        DateTime retryUntil, nextRead;
        internal bool Due(string key, int generation, DateTime now)
        {
            if (identity != key || version != generation)
            {
                identity = key;
                version = generation;
                retryUntil = now.AddSeconds(10);
                nextRead = DateTime.MinValue;
            }
            return now >= nextRead;
        }
        internal void Attempted(DateTime now)
        {
            nextRead = now.AddSeconds(now < retryUntil ? 2 : 30);
        }
    }

    internal static void InvalidateArtwork()
    {
        lock (artworkLock)
        {
            artworkGeneration++;
            coverSchedule = new CoverSchedule();
            onlineLookupKey = "";
            onlineArtworkTrack = "";
            staleCoverHash = "";
            lastCoverHash = "";
            activeCoverPath = "";
        }
    }

    static void MediaPropertiesChanged(GlobalSystemMediaTransportControlsSession sender, MediaPropertiesChangedEventArgs args)
    {
        Interlocked.Increment(ref artworkVersion);
    }

    static void TrackMediaSession(GlobalSystemMediaTransportControlsSession session)
    {
        if (object.Equals(coverSession, session)) return;
        if (coverSession != null && coverSubscribed)
            try { coverSession.MediaPropertiesChanged -= MediaPropertiesChanged; } catch { }
        coverSubscribed = false;
        coverSession = session;
        lock (artworkLock)
        {
            artworkGeneration++;
            coverSchedule = new CoverSchedule();
            activeCoverPath = "";
            lastCoverHash = "";
            staleCoverHash = "";
            lastTrackKey = "";
            lastTrackArtist = "";
            lastTrackAlbum = "";
            onlineLookupKey = "";
            onlineArtworkTrack = "";
        }
        if (session != null)
            try
            {
                session.MediaPropertiesChanged += MediaPropertiesChanged;
                coverSubscribed = true;
            }
            catch { }
    }
}
