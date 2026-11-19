using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

partial class SlateHUDHelper
{
    // ------------------------------------------------------------------ NVML (GPU), LHM & PageFile
    [StructLayout(LayoutKind.Sequential)] struct NvUtil { public uint gpu; public uint memory; }
    [StructLayout(LayoutKind.Sequential)] struct NvMem { public ulong total; public ulong free; public ulong used; }
    [DllImport("nvml.dll")] static extern int nvmlInit_v2();
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetHandleByIndex_v2(uint index, out IntPtr dev);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetUtilizationRates(IntPtr dev, out NvUtil u);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetMemoryInfo(IntPtr dev, out NvMem m);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetTemperature(IntPtr dev, int sensor, out uint t);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetPowerUsage(IntPtr dev, out uint milliwatts);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetFanSpeed(IntPtr dev, out uint percent);
    [DllImport("nvml.dll")] static extern int nvmlShutdown();

    static IntPtr gpuDev = IntPtr.Zero;
    static bool nvmlInitialized;
    const string UnavailableGpu = "-1, -1, -1, -1, -1, -1";
    const string DefaultLhmEndpoint = "http://127.0.0.1:8085/data.json";
    const int LhmHttpTimeoutMs = 500;

    internal struct TelemetryConfig
    {
        public string Provider;    // "auto", "nvml", "lhm"
        public bool LhmEnabled;    // true when SysLhmEnabled=1 or Provider=="lhm"
        public string LhmSource;   // "auto", "wmi", "http"
        public string LhmEndpoint; // validated loopback HTTP URL
    }

    internal struct LhmSensorSample
    {
        public string HardwareType; // "Cpu", "GpuAmd", "GpuIntel", "GpuNvidia"
        public string SensorType;   // "Temperature", "Load", "SmallData", "Data", "Power", "Control", "Fan"
        public string Name;
        public double Value;
        public string Unit;         // "C", "F", "%", "MiB", "W", "RPM"
    }

    internal struct LhmTelemetryResult
    {
        public bool Reachable;
        public bool HasCpuTemp;
        public double CpuTempC;
        public string CpuTempName;
        public bool HasGpu;
        public int GpuUsage;
        public int GpuVramUsedMiB;
        public int GpuVramTotalMiB;
        public int GpuTempC;
        public int GpuPowerW;
        public int GpuFan;
        public string GpuFanUnit;
    }

    static bool hasCachedConfig;
    static DateTime lastVariablesWriteUtc = DateTime.MinValue;
    static DateTime lastUserSettingsWriteUtc = DateTime.MinValue;
    static TelemetryConfig cachedTelemetryConfig;

    static string GpuSnapshot(string values, DateTimeOffset now, string pageFile)
    {
        return GpuSnapshot(values, now, pageFile, null, null);
    }

    internal static string GpuSnapshot(string values, DateTimeOffset now, string pageFile, string cpuTempLine, string lhmGpuLine)
    {
        var sb = new StringBuilder(GpuSnapshot(values, now));
        if (!string.IsNullOrEmpty(pageFile)) sb.Append("\nPAGEFILE=").Append(pageFile);
        if (!string.IsNullOrEmpty(cpuTempLine)) sb.Append("\nCPUTEMP=").Append(cpuTempLine);
        if (!string.IsNullOrEmpty(lhmGpuLine)) sb.Append("\nLHMGPU=").Append(lhmGpuLine);
        return sb.ToString();
    }

    static string GpuSnapshot(string values, DateTimeOffset now)
    {
        return values + "\nUPDATED=" + UnixSeconds(now).ToString(CultureInfo.InvariantCulture);
    }

    internal static bool IsLoopbackEndpoint(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        Uri uri;
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out uri)) return false;
        if (!string.Equals(uri.Scheme, "http", StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.IsNullOrEmpty(uri.UserInfo)) return false;
        if (uri.Port < 1 || uri.Port > 65535) return false;
        return string.Equals(uri.Host, "127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase);
    }

    static void ApplyIniVariables(string text, Dictionary<string, string> values)
    {
        if (string.IsNullOrEmpty(text)) return;
        bool inVariables = true;
        bool seenSection = false;
        using (var reader = new StringReader(text))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                string trimmed = line.Trim();
                if (trimmed.Length == 0 || trimmed[0] == ';') continue;
                if (trimmed[0] == '[' && trimmed[trimmed.Length - 1] == ']')
                {
                    seenSection = true;
                    inVariables = string.Equals(trimmed, "[Variables]", StringComparison.OrdinalIgnoreCase);
                    continue;
                }
                if (seenSection && !inVariables) continue;
                int eq = trimmed.IndexOf('=');
                if (eq <= 0) continue;
                string key = trimmed.Substring(0, eq).Trim();
                string val = trimmed.Substring(eq + 1).Trim();
                values[key] = val;
            }
        }
    }

    internal static TelemetryConfig ParseTelemetryConfig(string variablesText, string userSettingsText)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        ApplyIniVariables(variablesText, map);
        ApplyIniVariables(userSettingsText, map);

        string provider = "auto";
        string rawProvider;
        if (map.TryGetValue("SysSensorProvider", out rawProvider))
        {
            string norm = rawProvider.Trim().ToLowerInvariant();
            if (norm == "auto" || norm == "nvml" || norm == "lhm") provider = norm;
        }

        string rawEnabled;
        bool enabled = map.TryGetValue("SysLhmEnabled", out rawEnabled) && rawEnabled.Trim() == "1";
        if (provider == "lhm") enabled = true;

        string source = "auto";
        string rawSource;
        if (map.TryGetValue("LhmSource", out rawSource))
        {
            string norm = rawSource.Trim().ToLowerInvariant();
            if (norm == "auto" || norm == "wmi" || norm == "http") source = norm;
        }

        string endpoint = DefaultLhmEndpoint;
        string rawEndpoint;
        if (map.TryGetValue("LhmEndpoint", out rawEndpoint) && IsLoopbackEndpoint(rawEndpoint))
            endpoint = rawEndpoint.Trim();

        return new TelemetryConfig
        {
            Provider = provider,
            LhmEnabled = enabled,
            LhmSource = source,
            LhmEndpoint = endpoint
        };
    }

    static TelemetryConfig GetTelemetryConfig(string baseDir, out bool changed)
    {
        string varPath = Path.Combine(baseDir, "Variables.inc");
        string userPath = Path.Combine(baseDir, "UserSettings.inc");
        DateTime varTime = DateTime.MinValue;
        DateTime userTime = DateTime.MinValue;
        try { if (File.Exists(varPath)) varTime = File.GetLastWriteTimeUtc(varPath); } catch { }
        try { if (File.Exists(userPath)) userTime = File.GetLastWriteTimeUtc(userPath); } catch { }

        if (!hasCachedConfig || varTime != lastVariablesWriteUtc || userTime != lastUserSettingsWriteUtc)
        {
            changed = hasCachedConfig;
            string varText = File.Exists(varPath) ? ReadTextSafe(varPath) : "";
            string userText = File.Exists(userPath) ? ReadTextSafe(userPath) : "";
            cachedTelemetryConfig = ParseTelemetryConfig(varText, userText);
            lastVariablesWriteUtc = varTime;
            lastUserSettingsWriteUtc = userTime;
            hasCachedConfig = true;
            return cachedTelemetryConfig;
        }

        changed = false;
        return cachedTelemetryConfig;
    }

    static bool IsFiniteDouble(double value)
    {
        return !double.IsNaN(value) && !double.IsInfinity(value);
    }

    static string SanitizeLhmName(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return "";
        return name.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
    }

    static double NormalizeTempCelsius(double value, string unit)
    {
        if (!string.IsNullOrEmpty(unit))
        {
            string u = unit.Trim().ToLowerInvariant();
            if (u == "f" || u.EndsWith("f") || u.Contains("fahr"))
                return (value - 32.0) * 5.0 / 9.0;
        }
        return value;
    }

    static double NormalizeMemoryMiB(double value, string unit, string sensorType)
    {
        if (!string.IsNullOrEmpty(unit))
        {
            string u = unit.Trim().ToLowerInvariant();
            if (u.Contains("gb") || u.Contains("gib") || u.Contains("gbyte")) return value * 1024.0;
            if (u.Contains("mb") || u.Contains("mib") || u.Contains("mbyte")) return value;
            if (u.Contains("kb") || u.Contains("kib") || u.Contains("kbyte")) return value / 1024.0;
            if (u == "b" || u.Contains("byte")) return value / 1048576.0;
        }
        if (string.Equals(sensorType, "Data", StringComparison.OrdinalIgnoreCase)) return value * 1024.0;
        return value;
    }

    static int ScoreCpuTempName(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return -1;
        string lower = name.Trim().ToLowerInvariant();
        if (lower.Contains("distance to tjmax")) return -1;
        if (lower == "cpu package") return 4;
        if (lower.Contains("tctl/tdie") || lower.Contains("tdie")) return 3;
        if (lower == "core max" || lower == "package" || lower.Contains("core max")) return 2;
        if (lower == "core average") return 1;
        return 0;
    }

    static int ScoreGpuLoadName(string name)
    {
        string lower = (name ?? "").Trim().ToLowerInvariant();
        if (lower == "gpu core") return 3;
        if (lower == "d3d 3d") return 2;
        if (lower.Contains("memory") || lower.Contains("copy") || lower.Contains("video") || lower.Contains("bus")) return 0;
        return 1;
    }

    static int ScoreGpuTempName(string name)
    {
        string lower = (name ?? "").Trim().ToLowerInvariant();
        if (lower == "gpu core") return 4;
        if (lower == "gpu package" || lower == "gpu vr soc") return 3;
        if (lower == "gpu hot spot" || lower == "gpu hotspot") return 2;
        return 1;
    }

    static int ScoreGpuVramUsedName(string name)
    {
        string lower = (name ?? "").Trim().ToLowerInvariant();
        if (lower == "gpu memory used") return 3;
        if (lower == "d3d dedicated memory used") return 2;
        if (lower.Contains("memory used") && !lower.Contains("shared")) return 1;
        return -1;
    }

    static int ScoreGpuVramTotalName(string name)
    {
        string lower = (name ?? "").Trim().ToLowerInvariant();
        if (lower == "gpu memory total") return 3;
        if (lower == "d3d dedicated memory total") return 2;
        if (lower.Contains("memory total") && !lower.Contains("shared")) return 1;
        return -1;
    }

    static int ScoreGpuPowerName(string name)
    {
        string lower = (name ?? "").Trim().ToLowerInvariant();
        if (lower == "gpu package") return 3;
        if (lower == "gpu power") return 2;
        if (lower == "gpu core") return 1;
        return 0;
    }

    struct GpuCandidate
    {
        public string HardwareType;
        public bool HasUsage;
        public int UsageScore;
        public int Usage;
        public int TempScore;
        public int TempC;
        public int VramUsedScore;
        public int VramUsedMiB;
        public int VramTotalScore;
        public int VramTotalMiB;
        public int PowerScore;
        public int PowerW;
        public int FanPctScore;
        public int FanPct;
        public int FanRpmScore;
        public int FanRpm;
    }

    static GpuCandidate CreateGpuCandidate(string hwType)
    {
        return new GpuCandidate
        {
            HardwareType = hwType,
            UsageScore = -1,
            TempScore = -1,
            TempC = -1,
            VramUsedScore = -1,
            VramUsedMiB = -1,
            VramTotalScore = -1,
            VramTotalMiB = -1,
            PowerScore = -1,
            PowerW = -1,
            FanPctScore = -1,
            FanPct = -1,
            FanRpmScore = -1,
            FanRpm = -1
        };
    }

    internal static LhmTelemetryResult SelectLhmTelemetry(IList<LhmSensorSample> samples)
    {
        var result = new LhmTelemetryResult
        {
            GpuTempC = -1,
            GpuVramUsedMiB = -1,
            GpuVramTotalMiB = -1,
            GpuPowerW = -1,
            GpuFan = -1,
            GpuFanUnit = "%"
        };
        if (samples == null || samples.Count == 0) return result;
        result.Reachable = true;

        int bestCpuScore = -1;
        var gpuBuckets = new Dictionary<string, GpuCandidate>(StringComparer.OrdinalIgnoreCase);
        var gpuOrder = new List<string>();

        for (int i = 0; i < samples.Count; i++)
        {
            LhmSensorSample s = samples[i];
            if (!IsFiniteDouble(s.Value)) continue;

            if (string.Equals(s.HardwareType, "Cpu", StringComparison.OrdinalIgnoreCase))
            {
                if (string.Equals(s.SensorType, "Temperature", StringComparison.OrdinalIgnoreCase))
                {
                    double tempC = NormalizeTempCelsius(s.Value, s.Unit);
                    if (tempC >= -40.0 && tempC <= 150.0)
                    {
                        int score = ScoreCpuTempName(s.Name);
                        if (score > bestCpuScore)
                        {
                            bestCpuScore = score;
                            result.HasCpuTemp = true;
                            result.CpuTempC = tempC;
                            result.CpuTempName = SanitizeLhmName(s.Name);
                        }
                    }
                }
                continue;
            }

            if (!string.Equals(s.HardwareType, "GpuAmd", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(s.HardwareType, "GpuIntel", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(s.HardwareType, "GpuNvidia", StringComparison.OrdinalIgnoreCase))
                continue;

            string hwKey = s.HardwareType;
            GpuCandidate cand;
            if (!gpuBuckets.TryGetValue(hwKey, out cand))
            {
                cand = CreateGpuCandidate(hwKey);
                gpuOrder.Add(hwKey);
            }

            if (string.Equals(s.SensorType, "Load", StringComparison.OrdinalIgnoreCase))
            {
                if (s.Value >= 0.0 && s.Value <= 100.0)
                {
                    int score = ScoreGpuLoadName(s.Name);
                    if (score > cand.UsageScore)
                    {
                        cand.UsageScore = score;
                        cand.HasUsage = true;
                        cand.Usage = (int)Math.Round(s.Value);
                    }
                }
            }
            else if (string.Equals(s.SensorType, "Temperature", StringComparison.OrdinalIgnoreCase))
            {
                double tempC = NormalizeTempCelsius(s.Value, s.Unit);
                if (tempC >= -40.0 && tempC <= 150.0)
                {
                    int score = ScoreGpuTempName(s.Name);
                    if (score > cand.TempScore)
                    {
                        cand.TempScore = score;
                        cand.TempC = (int)Math.Round(tempC);
                    }
                }
            }
            else if (string.Equals(s.SensorType, "SmallData", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(s.SensorType, "Data", StringComparison.OrdinalIgnoreCase))
            {
                double mib = NormalizeMemoryMiB(s.Value, s.Unit, s.SensorType);
                int usedScore = ScoreGpuVramUsedName(s.Name);
                if (usedScore >= 0 && mib >= 0.0 && usedScore > cand.VramUsedScore)
                {
                    cand.VramUsedScore = usedScore;
                    cand.VramUsedMiB = (int)Math.Round(mib);
                }
                int totalScore = ScoreGpuVramTotalName(s.Name);
                if (totalScore >= 0 && mib > 0.0 && totalScore > cand.VramTotalScore)
                {
                    cand.VramTotalScore = totalScore;
                    cand.VramTotalMiB = (int)Math.Round(mib);
                }
            }
            else if (string.Equals(s.SensorType, "Power", StringComparison.OrdinalIgnoreCase))
            {
                double watts = s.Value;
                if (!string.IsNullOrEmpty(s.Unit) && string.Equals(s.Unit.Trim(), "mW", StringComparison.OrdinalIgnoreCase))
                    watts = watts / 1000.0;
                if (watts >= 0.0 && watts <= 2000.0)
                {
                    int score = ScoreGpuPowerName(s.Name);
                    if (score > cand.PowerScore)
                    {
                        cand.PowerScore = score;
                        cand.PowerW = (int)Math.Round(watts);
                    }
                }
            }
            else if (string.Equals(s.SensorType, "Control", StringComparison.OrdinalIgnoreCase))
            {
                if (s.Value >= 0.0 && s.Value <= 100.0)
                {
                    string lower = (s.Name ?? "").Trim().ToLowerInvariant();
                    int score = lower == "gpu fan" ? 2 : (lower.Contains("fan") ? 1 : -1);
                    if (score > cand.FanPctScore)
                    {
                        cand.FanPctScore = score;
                        cand.FanPct = (int)Math.Round(s.Value);
                    }
                }
            }
            else if (string.Equals(s.SensorType, "Fan", StringComparison.OrdinalIgnoreCase))
            {
                if (s.Value >= 0.0)
                {
                    string lower = (s.Name ?? "").Trim().ToLowerInvariant();
                    int score = lower == "gpu fan" ? 2 : 1;
                    if (score > cand.FanRpmScore)
                    {
                        cand.FanRpmScore = score;
                        cand.FanRpm = (int)Math.Round(s.Value);
                    }
                }
            }

            gpuBuckets[hwKey] = cand;
        }

        // Prefer discrete/non-Intel GPUs when multiple GPU hardware nodes exist with load metrics.
        GpuCandidate chosen = CreateGpuCandidate("");
        int chosenRank = -1;
        for (int i = 0; i < gpuOrder.Count; i++)
        {
            GpuCandidate cand = gpuBuckets[gpuOrder[i]];
            if (!cand.HasUsage) continue;
            int rank = string.Equals(cand.HardwareType, "GpuIntel", StringComparison.OrdinalIgnoreCase) ? 1 : 2;
            if (rank > chosenRank)
            {
                chosen = cand;
                chosenRank = rank;
            }
        }

        if (chosen.HasUsage)
        {
            result.HasGpu = true;
            result.GpuUsage = chosen.Usage;
            result.GpuVramUsedMiB = chosen.VramUsedMiB;
            result.GpuVramTotalMiB = chosen.VramTotalMiB;
            result.GpuTempC = chosen.TempC;
            result.GpuPowerW = chosen.PowerW;
            if (chosen.FanPct >= 0)
            {
                result.GpuFan = chosen.FanPct;
                result.GpuFanUnit = "%";
            }
            else if (chosen.FanRpm >= 0)
            {
                result.GpuFan = chosen.FanRpm;
                result.GpuFanUnit = "RPM";
            }
        }

        return result;
    }

    internal static string CpuTempLine(LhmTelemetryResult r)
    {
        if (!r.HasCpuTemp || string.IsNullOrEmpty(r.CpuTempName)) return null;
        return string.Format(CultureInfo.InvariantCulture, "{0:0.#}|{1}", r.CpuTempC, SanitizeLhmName(r.CpuTempName));
    }

    internal static string LhmGpuLine(LhmTelemetryResult r)
    {
        if (!r.HasGpu) return null;
        string fanUnit = string.IsNullOrEmpty(r.GpuFanUnit) ? "%" : r.GpuFanUnit;
        return string.Format(CultureInfo.InvariantCulture, "{0}, {1}, {2}, {3}, {4}, {5}, {6}",
            r.GpuUsage, r.GpuVramUsedMiB, r.GpuVramTotalMiB, r.GpuTempC, r.GpuPowerW, r.GpuFan, fanUnit);
    }

    static string InferHardwareTypeFromId(string id)
    {
        if (string.IsNullOrEmpty(id)) return "";
        string lower = id.ToLowerInvariant();
        if (lower.Contains("/amdcpu") || lower.Contains("/intelcpu") || lower.StartsWith("/cpu")) return "Cpu";
        if (lower.Contains("/gpu-amd")) return "GpuAmd";
        if (lower.Contains("/gpu-intel")) return "GpuIntel";
        if (lower.Contains("/gpu-nvidia")) return "GpuNvidia";
        return "";
    }

    static string InferHardwareTypeFromNode(string hardwareId, string sensorId, string imageUrl, string text, string inherited)
    {
        string byId = InferHardwareTypeFromId(hardwareId);
        if (!string.IsNullOrEmpty(byId)) return byId;
        byId = InferHardwareTypeFromId(sensorId);
        if (!string.IsNullOrEmpty(byId)) return byId;

        if (!string.IsNullOrEmpty(imageUrl))
        {
            string img = imageUrl.ToLowerInvariant();
            if (img.Contains("cpu.png")) return "Cpu";
            if (img.Contains("ati.png") || img.Contains("amd.png")) return "GpuAmd";
            if (img.Contains("nvidia.png")) return "GpuNvidia";
            if (img.Contains("intel.png"))
            {
                string t = (text ?? "").ToLowerInvariant();
                if (t.Contains("graphics") || t.Contains("arc") || t.Contains("uhd") || t.Contains("iris") || t.Contains("gpu"))
                    return "GpuIntel";
                return "Cpu";
            }
        }

        if (string.IsNullOrEmpty(inherited) && !string.IsNullOrEmpty(text))
        {
            string t = text.ToLowerInvariant();
            if (t.Contains("radeon")) return "GpuAmd";
            if (t.Contains("geforce") || t.Contains("rtx") || t.Contains("gtx") || t.Contains("quadro")) return "GpuNvidia";
            if (t.Contains("intel arc") || t.Contains("uhd graphics") || t.Contains("iris")) return "GpuIntel";
            if (t.Contains("ryzen") || t.Contains("epyc") || t.Contains("threadripper") ||
                t.Contains("core i") || t.Contains("core ultra") || t.Contains("xeon")) return "Cpu";
        }

        return inherited;
    }

    static string InferSensorCategory(string nodeType, string text, string sensorId, string inherited)
    {
        string sid = (sensorId ?? "").ToLowerInvariant();
        if (sid.Contains("/temperature/")) return "Temperature";
        if (sid.Contains("/load/")) return "Load";
        if (sid.Contains("/smalldata/")) return "SmallData";
        if (sid.Contains("/data/")) return "Data";
        if (sid.Contains("/power/")) return "Power";
        if (sid.Contains("/control/")) return "Control";
        if (sid.Contains("/fan/")) return "Fan";

        string candidate = !string.IsNullOrWhiteSpace(nodeType) ? nodeType.Trim() : (text ?? "").Trim();
        string lower = candidate.ToLowerInvariant();
        if (lower == "temperatures" || lower == "temperature") return "Temperature";
        if (lower == "loads" || lower == "load") return "Load";
        if (lower == "smalldata") return "SmallData";
        if (lower == "data") return "Data";
        if (lower == "powers" || lower == "power") return "Power";
        if (lower == "controls" || lower == "control") return "Control";
        if (lower == "fans" || lower == "fan") return "Fan";
        if (lower == "clocks" || lower == "clock" || lower == "voltages" || lower == "voltage" ||
            lower == "factors" || lower == "factor" || lower == "levels" || lower == "level" ||
            lower == "throughputs" || lower == "throughput") return "Other";
        return inherited;
    }

    static bool TryParseLhmValueText(string raw, out double value, out string unit)
    {
        value = 0;
        unit = "";
        if (string.IsNullOrWhiteSpace(raw)) return false;
        Match m = Regex.Match(raw.Trim(), @"^([+-]?\d+(?:[.,]\d+)?)\s*(.*)$");
        if (!m.Success) return false;
        string numText = m.Groups[1].Value.Replace(',', '.');
        if (!double.TryParse(numText, NumberStyles.Float, CultureInfo.InvariantCulture, out value)) return false;
        if (!IsFiniteDouble(value)) return false;
        unit = m.Groups[2].Value.Trim();
        return true;
    }

    static string GetDictString(Dictionary<string, object> dict, string key)
    {
        object obj;
        if (dict != null && dict.TryGetValue(key, out obj) && obj != null)
            return obj as string ?? obj.ToString();
        return "";
    }

    static void WalkLhmJson(Dictionary<string, object> node, string hwType, string sensorCategory, List<LhmSensorSample> samples)
    {
        if (node == null) return;
        string text = GetDictString(node, "Text");
        string hwId = GetDictString(node, "HardwareId");
        string sensorId = GetDictString(node, "SensorId");
        string imageUrl = GetDictString(node, "ImageURL");
        string nodeType = GetDictString(node, "Type");
        string rawValue = GetDictString(node, "Value");

        string nextHw = InferHardwareTypeFromNode(hwId, sensorId, imageUrl, text, hwType);
        string nextCat = InferSensorCategory(nodeType, text, sensorId, sensorCategory);

        object rawChildren;
        object[] children = node.TryGetValue("Children", out rawChildren) ? rawChildren as object[] : null;
        if (children != null && children.Length > 0)
        {
            for (int i = 0; i < children.Length; i++)
                WalkLhmJson(children[i] as Dictionary<string, object>, nextHw, nextCat, samples);
            return;
        }

        if (string.IsNullOrEmpty(nextHw) || string.IsNullOrEmpty(nextCat) || nextCat == "Other") return;
        if (string.IsNullOrWhiteSpace(text) || string.IsNullOrWhiteSpace(rawValue)) return;

        double val;
        string rawUnit;
        if (!TryParseLhmValueText(rawValue, out val, out rawUnit)) return;

        string normUnit = rawUnit;
        if (nextCat == "Temperature")
        {
            val = NormalizeTempCelsius(val, rawUnit);
            normUnit = "C";
        }
        else if (nextCat == "SmallData" || nextCat == "Data")
        {
            val = NormalizeMemoryMiB(val, rawUnit, nextCat);
            normUnit = "MiB";
        }
        else if (nextCat == "Power")
        {
            if (string.Equals(rawUnit, "mW", StringComparison.OrdinalIgnoreCase)) val = val / 1000.0;
            normUnit = "W";
        }
        else if (nextCat == "Load" || nextCat == "Control")
        {
            normUnit = "%";
        }
        else if (nextCat == "Fan")
        {
            normUnit = "RPM";
        }

        samples.Add(new LhmSensorSample
        {
            HardwareType = nextHw,
            SensorType = nextCat,
            Name = text.Trim(),
            Value = val,
            Unit = normUnit
        });
    }

    internal static List<LhmSensorSample> ParseLhmJson(string json)
    {
        var samples = new List<LhmSensorSample>();
        if (string.IsNullOrWhiteSpace(json)) return samples;
        var root = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
        if (root == null) return samples;
        WalkLhmJson(root, "", "", samples);
        return samples;
    }

    static List<LhmSensorSample> ReadLhmWmi()
    {
        var samples = new List<LhmSensorSample>();
        try
        {
            var scope = new ManagementScope(@"\\.\root\LibreHardwareMonitor");
            scope.Connect();

            var hwTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            using (var hwSearcher = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT Identifier, HardwareType FROM Hardware")))
            using (var hwResults = hwSearcher.Get())
            {
                foreach (ManagementBaseObject hw in hwResults)
                {
                    using (hw)
                    {
                        string id = hw["Identifier"] as string;
                        string hType = hw["HardwareType"] as string;
                        if (!string.IsNullOrEmpty(id) && !string.IsNullOrEmpty(hType))
                            hwTypes[id] = hType;
                    }
                }
            }

            using (var searcher = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT Name, SensorType, Value, Parent, Identifier FROM Sensor")))
            using (var results = searcher.Get())
            {
                foreach (ManagementBaseObject obj in results)
                {
                    using (obj)
                    {
                        string name = obj["Name"] as string;
                        string sensorType = obj["SensorType"] as string;
                        object rawVal = obj["Value"];
                        string parent = obj["Parent"] as string;
                        string identifier = obj["Identifier"] as string;
                        if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(sensorType) || rawVal == null) continue;

                        string hwType = "";
                        if (!string.IsNullOrEmpty(parent)) hwTypes.TryGetValue(parent, out hwType);
                        if (string.IsNullOrEmpty(hwType)) hwType = InferHardwareTypeFromId(parent);
                        if (string.IsNullOrEmpty(hwType)) hwType = InferHardwareTypeFromId(identifier);
                        if (string.IsNullOrEmpty(hwType)) continue;

                        double val = Convert.ToDouble(rawVal, CultureInfo.InvariantCulture);
                        if (!IsFiniteDouble(val)) continue;

                        string unit = "";
                        if (string.Equals(sensorType, "Temperature", StringComparison.OrdinalIgnoreCase)) unit = "C";
                        else if (string.Equals(sensorType, "Load", StringComparison.OrdinalIgnoreCase) ||
                                 string.Equals(sensorType, "Control", StringComparison.OrdinalIgnoreCase)) unit = "%";
                        else if (string.Equals(sensorType, "Data", StringComparison.OrdinalIgnoreCase))
                        {
                            val = val * 1024.0;
                            unit = "MiB";
                        }
                        else if (string.Equals(sensorType, "SmallData", StringComparison.OrdinalIgnoreCase)) unit = "MiB";
                        else if (string.Equals(sensorType, "Power", StringComparison.OrdinalIgnoreCase)) unit = "W";
                        else if (string.Equals(sensorType, "Fan", StringComparison.OrdinalIgnoreCase)) unit = "RPM";
                        else continue;

                        samples.Add(new LhmSensorSample
                        {
                            HardwareType = hwType,
                            SensorType = sensorType,
                            Name = name.Trim(),
                            Value = val,
                            Unit = unit
                        });
                    }
                }
            }
        }
        catch
        {
            return new List<LhmSensorSample>();
        }
        return samples;
    }

    static async Task<List<LhmSensorSample>> ReadLhmHttpAsync(string endpoint)
    {
        if (!IsLoopbackEndpoint(endpoint)) return new List<LhmSensorSample>();
        try
        {
            var req = (HttpWebRequest)WebRequest.Create(endpoint);
            req.Method = "GET";
            req.Timeout = LhmHttpTimeoutMs;
            req.ReadWriteTimeout = LhmHttpTimeoutMs;
            req.AllowAutoRedirect = false;
            req.Proxy = null;
            req.UserAgent = "SlateHUD/2.4";
            byte[] bytes = await FetchHttpBytesAsync(req, LhmHttpTimeoutMs);
            if (bytes == null || bytes.Length == 0) return new List<LhmSensorSample>();
            return ParseLhmJson(Encoding.UTF8.GetString(bytes));
        }
        catch
        {
            return new List<LhmSensorSample>();
        }
    }

    static async Task<LhmTelemetryResult> ReadLhmTelemetryAsync(TelemetryConfig cfg)
    {
        List<LhmSensorSample> samples = null;
        if (cfg.LhmSource == "auto" || cfg.LhmSource == "wmi")
            samples = await Task.Run(() => ReadLhmWmi());
        if ((samples == null || samples.Count == 0) && (cfg.LhmSource == "auto" || cfg.LhmSource == "http"))
            samples = await ReadLhmHttpAsync(cfg.LhmEndpoint);
        return SelectLhmTelemetry(samples);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PerformanceInformation
    {
        public uint cb;
        public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable, SystemCache, KernelTotal, KernelPaged, KernelNonpaged, PageSize;
        public uint HandleCount, ProcessCount, ThreadCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct EnumPageFileInformation
    {
        public uint cb;
        public uint Reserved;
        public UIntPtr TotalSize;
        public UIntPtr TotalInUse;
        public UIntPtr PeakUsage;
    }

    delegate bool EnumPageFilesProc(IntPtr context, ref EnumPageFileInformation info, [MarshalAs(UnmanagedType.LPWStr)] string file);
    [DllImport("psapi.dll", SetLastError = true)] static extern bool GetPerformanceInfo(out PerformanceInformation info, uint size);
    [DllImport("psapi.dll", EntryPoint = "EnumPageFilesW", SetLastError = true)] static extern bool EnumPageFiles(EnumPageFilesProc callback, IntPtr context);

    static string ReadPageFile()
    {
        try
        {
            PerformanceInformation perf = new PerformanceInformation();
            perf.cb = (uint)Marshal.SizeOf(typeof(PerformanceInformation));
            if (!GetPerformanceInfo(out perf, perf.cb)) return null;
            ulong pageSize = perf.PageSize.ToUInt64();
            if (pageSize == 0) return null;
            ulong usedBytes = 0, totalBytes = 0;
            bool ok = EnumPageFiles((IntPtr context, ref EnumPageFileInformation info, string file) =>
            {
                usedBytes += info.TotalInUse.ToUInt64() * pageSize;
                totalBytes += info.TotalSize.ToUInt64() * pageSize;
                return true;
            }, IntPtr.Zero);
            if (!ok) return null;
            return usedBytes.ToString(CultureInfo.InvariantCulture) + "," + totalBytes.ToString(CultureInfo.InvariantCulture);
        }
        catch { return null; }
    }

    static bool NvmlInit()
    {
        try
        {
            if (!nvmlInitialized)
            {
                if (nvmlInit_v2() != 0) return false;
                nvmlInitialized = true;
            }
            if (nvmlDeviceGetHandleByIndex_v2(0, out gpuDev) == 0) return true;
            GpuFailed();
            return false;
        }
        catch { GpuFailed(); return false; }
    }

    // Same column order the old nvidia-smi query used, plus power (W) and fan (%):
    // "usage, vramUsedMiB, vramTotalMiB, tempC, powerW, fanPercent"   (fan = -1 when unsupported)
    static string ReadGpu()
    {
        try
        {
            NvUtil u; NvMem m; uint temp = 0, mw = 0, fan = 0;
            if (nvmlDeviceGetUtilizationRates(gpuDev, out u) != 0 ||
                nvmlDeviceGetMemoryInfo(gpuDev, out m) != 0 || m.total == 0)
                return GpuFailed();
            bool hasTemp = nvmlDeviceGetTemperature(gpuDev, 0, out temp) == 0;
            bool hasPower = nvmlDeviceGetPowerUsage(gpuDev, out mw) == 0;
            bool hasFan = nvmlDeviceGetFanSpeed(gpuDev, out fan) == 0;
            return string.Format(CultureInfo.InvariantCulture, "{0}, {1}, {2}, {3}, {4}, {5}",
                u.gpu, m.used / 1048576UL, m.total / 1048576UL, hasTemp ? (int)temp : -1,
                hasPower ? (int)Math.Round(mw / 1000.0) : -1, hasFan ? (int)fan : -1);
        }
        catch { return GpuFailed(); }
    }

    static string GpuFailed()
    {
        if (nvmlInitialized) { try { nvmlShutdown(); } catch { } }
        nvmlInitialized = false;
        gpuDev = IntPtr.Zero;
        return UnavailableGpu;
    }
}
