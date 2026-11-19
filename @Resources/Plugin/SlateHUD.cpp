// SlateHUD.dll - thin native x64 Rainmeter plugin bridge for SlateHUDHelper.
// Reads lock-free snapshots from Local\SlateHUDHelper.SharedState (with disk cache fallback)
// and dispatches non-blocking commands over \\.\pipe\SlateHUDHelper.Pipe (with CLI fallback).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <cwctype>
#include <memory>
#include <string>

namespace {

const wchar_t* kSharedMemoryName = L"Local\\SlateHUDHelper.SharedState";
const wchar_t* kPipeName = L"\\\\.\\pipe\\SlateHUDHelper.Pipe";
const wchar_t* kMediaWakeName = L"Local\\SlateHUDHelper.MediaWake";

const uint32_t kSharedMagic = 0x53485544u; // "SHUD"
const uint32_t kSharedVersion = 1u;
const int32_t kSharedSlotCount = 5;
const size_t kSharedHeaderBytes = 64;
const size_t kSharedSlotStride = 12288;
const int32_t kSharedMaxPayloadBytes = 12272;
const size_t kSharedTotalBytes = 65536;

enum RmGetType {
    RMG_MEASURENAME = 0,
    RMG_SKIN = 1
};

typedef LPCWSTR(__stdcall* FnRmReadString)(void* rm, LPCWSTR option, LPCWSTR defValue, BOOL replaceMeasures);
typedef LPCWSTR(__stdcall* FnRmReplaceVariables)(void* rm, LPCWSTR str);
typedef LPCWSTR(__stdcall* FnRmPathToAbsolute)(void* rm, LPCWSTR relativePath);
typedef void(__stdcall* FnRmExecute)(void* skin, LPCWSTR command);
typedef void*(__stdcall* FnRmGet)(void* rm, int type);

FnRmReadString g_RmReadString = nullptr;
FnRmReplaceVariables g_RmReplaceVariables = nullptr;
FnRmPathToAbsolute g_RmPathToAbsolute = nullptr;
FnRmExecute g_RmExecute = nullptr;
FnRmGet g_RmGet = nullptr;
INIT_ONCE g_ApiInitOnce = INIT_ONCE_STATIC_INIT;

BOOL CALLBACK InitRainmeterApi(PINIT_ONCE, PVOID, PVOID*) {
    HMODULE rmDll = GetModuleHandleW(L"Rainmeter.dll");
    if (rmDll) {
        g_RmReadString = reinterpret_cast<FnRmReadString>(GetProcAddress(rmDll, "RmReadString"));
        g_RmReplaceVariables = reinterpret_cast<FnRmReplaceVariables>(GetProcAddress(rmDll, "RmReplaceVariables"));
        g_RmPathToAbsolute = reinterpret_cast<FnRmPathToAbsolute>(GetProcAddress(rmDll, "RmPathToAbsolute"));
        g_RmExecute = reinterpret_cast<FnRmExecute>(GetProcAddress(rmDll, "RmExecute"));
        g_RmGet = reinterpret_cast<FnRmGet>(GetProcAddress(rmDll, "RmGet"));
    }
    return TRUE;
}

void EnsureApiResolved() {
    InitOnceExecuteOnce(&g_ApiInitOnce, InitRainmeterApi, nullptr, nullptr);
}

struct MeasureHandle {
    void* skin = nullptr;
    std::atomic<bool> alive{true};
    SRWLOCK cfgLock = SRWLOCK_INIT;
    SRWLOCK lifeLock = SRWLOCK_INIT;
    std::wstring helperPath;
    std::wstring finishAction;
};

struct MeasureData {
    void* rm = nullptr;
    int slotIndex = -1;
    bool hasUpdated = false;
    HANDLE hMap = nullptr;
    const uint8_t* pView = nullptr;
    std::wstring fallbackPath;
    std::wstring cachedText;
    std::shared_ptr<MeasureHandle> handle;

    ~MeasureData() {
        if (pView) {
            UnmapViewOfFile(pView);
            pView = nullptr;
        }
        if (hMap) {
            CloseHandle(hMap);
            hMap = nullptr;
        }
    }
};

std::wstring TrimWide(const std::wstring& s) {
    size_t start = 0;
    while (start < s.size() && std::iswspace(s[start])) start++;
    size_t end = s.size();
    while (end > start && std::iswspace(s[end - 1])) end--;
    return s.substr(start, end - start);
}

std::string TrimAscii(const std::string& s) {
    size_t start = 0;
    while (start < s.size() && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r' || s[start] == '\n')) start++;
    size_t end = s.size();
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r' || s[end - 1] == '\n')) end--;
    return s.substr(start, end - start);
}

int ParseSlotIndex(const std::wstring& streamName) {
    std::wstring s = TrimWide(streamName);
    for (size_t i = 0; i < s.size(); i++) s[i] = static_cast<wchar_t>(std::towlower(s[i]));
    if (s == L"media" || s == L"media.txt") return 0;
    if (s == L"mediahealth" || s == L"media-health" || s == L"media-health.txt") return 1;
    if (s == L"gpu" || s == L"gpu.txt") return 2;
    if (s == L"monitors" || s == L"monitors.txt") return 3;
    if (s == L"helperhealth" || s == L"helper-health" || s == L"helper-health.txt") return 4;
    return -1;
}

std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    if (len <= 0) return std::wstring();
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &out[0], len);
    return out;
}

std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    int len = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    if (len <= 0) return std::string();
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), &out[0], len, nullptr, nullptr);
    return out;
}

bool TryReadSharedMemory(MeasureData* m, std::string& outUtf8) {
    if (!m || m->slotIndex < 0 || m->slotIndex >= kSharedSlotCount) return false;

    if (!m->pView) {
        if (!m->hMap) {
            m->hMap = OpenFileMappingW(FILE_MAP_READ, FALSE, kSharedMemoryName);
            if (!m->hMap) return false;
        }
        m->pView = reinterpret_cast<const uint8_t*>(
            MapViewOfFile(m->hMap, FILE_MAP_READ, 0, 0, kSharedTotalBytes));
        if (!m->pView) {
            CloseHandle(m->hMap);
            m->hMap = nullptr;
            return false;
        }
    }

    const volatile uint32_t* header = reinterpret_cast<const volatile uint32_t*>(m->pView);
    if (header[0] != kSharedMagic || header[1] != kSharedVersion ||
        static_cast<int32_t>(header[2]) < kSharedSlotCount ||
        static_cast<size_t>(header[3]) != kSharedSlotStride) {
        return false;
    }

    const size_t slotOffset = kSharedHeaderBytes + static_cast<size_t>(m->slotIndex) * kSharedSlotStride;
    const volatile uint32_t* pSeq = reinterpret_cast<const volatile uint32_t*>(m->pView + slotOffset);
    const volatile int32_t* pLen = reinterpret_cast<const volatile int32_t*>(m->pView + slotOffset + 4);
    const char* pPayload = reinterpret_cast<const char*>(m->pView + slotOffset + 8);

    for (int attempt = 0; attempt < 8; attempt++) {
        uint32_t seq1 = *pSeq;
        MemoryBarrier();
        if (seq1 == 0u) return false;
        if ((seq1 & 1u) != 0u) {
            Sleep(0);
            continue;
        }
        int32_t len = *pLen;
        if (len < 0 || len > kSharedMaxPayloadBytes) {
            Sleep(0);
            continue;
        }
        std::string buf(static_cast<size_t>(len), '\0');
        if (len > 0) std::memcpy(&buf[0], pPayload, static_cast<size_t>(len));
        MemoryBarrier();
        uint32_t seq2 = *pSeq;
        if (seq1 == seq2) {
            outUtf8.swap(buf);
            return true;
        }
    }
    return false;
}

bool TryReadDiskFallback(const std::wstring& path, std::string& outUtf8) {
    if (path.empty()) return false;
    HANDLE hFile = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER fileSize{};
    if (!GetFileSizeEx(hFile, &fileSize) || fileSize.QuadPart < 0 || fileSize.QuadPart > 262144) {
        CloseHandle(hFile);
        return false;
    }

    size_t toRead = static_cast<size_t>(fileSize.QuadPart);
    std::string data(toRead, '\0');
    size_t totalRead = 0;
    while (totalRead < toRead) {
        DWORD chunk = 0;
        if (!ReadFile(hFile, &data[totalRead], static_cast<DWORD>(toRead - totalRead), &chunk, nullptr) || chunk == 0) {
            break;
        }
        totalRead += chunk;
    }
    CloseHandle(hFile);
    data.resize(totalRead);
    if (data.size() >= 3 &&
        static_cast<unsigned char>(data[0]) == 0xEF &&
        static_cast<unsigned char>(data[1]) == 0xBB &&
        static_cast<unsigned char>(data[2]) == 0xBF) {
        data.erase(0, 3);
    }
    outUtf8.swap(data);
    return true;
}

bool TrySendPipeCommand(const std::string& cmdUtf8, std::string& replyUtf8) {
    replyUtf8.clear();
    if (!WaitNamedPipeW(kPipeName, 150)) return false;

    HANDLE hPipe = CreateFileW(
        kPipeName,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);
    if (hPipe == INVALID_HANDLE_VALUE) return false;

    std::string line = cmdUtf8 + "\n";
    DWORD written = 0;
    BOOL writeOk = WriteFile(hPipe, line.data(), static_cast<DWORD>(line.size()), &written, nullptr);
    if (!writeOk || written != line.size()) {
        CloseHandle(hPipe);
        return false;
    }

    char buf[512];
    DWORD read = 0;
    std::string reply;
    while (ReadFile(hPipe, buf, sizeof(buf), &read, nullptr) && read > 0) {
        reply.append(buf, read);
        if (reply.find('\n') != std::string::npos || reply.size() > 2048) break;
    }
    CloseHandle(hPipe);
    replyUtf8 = TrimAscii(reply);
    return !replyUtf8.empty();
}

void RunCliFallback(const std::wstring& helperPath, const std::wstring& args, bool waitForExit) {
    if (helperPath.empty()) return;
    std::wstring cmdLine = L"\"" + helperPath + L"\" " + args;
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    if (CreateProcessW(nullptr, &cmdLine[0], nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        if (waitForExit) WaitForSingleObject(pi.hProcess, 8000);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

void SignalMediaWake() {
    HANDLE hEvent = OpenEventW(EVENT_MODIFY_STATE, FALSE, kMediaWakeName);
    if (hEvent) {
        SetEvent(hEvent);
        CloseHandle(hEvent);
    }
}

std::wstring EscapeLuaSingleQuoted(const std::wstring& s) {
    std::wstring out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); i++) {
        wchar_t ch = s[i];
        if (ch == L'\r' || ch == L'\n') {
            out.push_back(L' ');
        } else if (ch == L'\\' || ch == L'\'') {
            out.push_back(L'\\');
            out.push_back(ch);
        } else if (ch == L'[') {
            out.push_back(L'\xFF3B');
        } else if (ch == L']') {
            out.push_back(L'\xFF3D');
        } else {
            out.push_back(ch);
        }
    }
    return out;
}

struct BangJob {
    std::shared_ptr<MeasureHandle> handle;
    std::wstring args;
};

DWORD WINAPI BangWorkerProc(LPVOID param) {
    std::unique_ptr<BangJob> job(static_cast<BangJob*>(param));
    if (!job || !job->handle || !job->handle->alive.load()) return 0;

    std::wstring trimmed = TrimWide(job->args);
    if (trimmed.empty()) return 0;

    std::wstring firstToken;
    for (size_t i = 0; i < trimmed.size(); i++) {
        if (std::iswspace(trimmed[i])) break;
        firstToken.push_back(static_cast<wchar_t>(std::towlower(trimmed[i])));
    }

    std::wstring helperPath;
    std::wstring finishAction;
    AcquireSRWLockShared(&job->handle->cfgLock);
    helperPath = job->handle->helperPath;
    finishAction = job->handle->finishAction;
    ReleaseSRWLockShared(&job->handle->cfgLock);

    bool forceCli = (firstToken == L"ensure" || firstToken == L"initnotes" ||
                     firstToken == L"launchgame" || firstToken == L"daemon");

    std::string replyUtf8;
    bool dispatched = false;
    if (!forceCli) {
        dispatched = TrySendPipeCommand(WideToUtf8(trimmed), replyUtf8);
    }
    if (!dispatched) {
        RunCliFallback(helperPath, trimmed, firstToken != L"daemon");
        if (!forceCli) SignalMediaWake();
    }

    if (!finishAction.empty() && job->handle->alive.load() && g_RmExecute) {
        std::wstring command = finishAction;
        if (replyUtf8.compare(0, 11, "MEDIA:ERROR") == 0) {
            std::wstring errWide = EscapeLuaSingleQuoted(Utf8ToWide(replyUtf8));
            size_t pos = command.find(L"FinishControl()");
            if (pos != std::wstring::npos) {
                command.replace(pos, 15, L"FinishControl('" + errWide + L"')");
            }
        }
        AcquireSRWLockShared(&job->handle->lifeLock);
        if (job->handle->alive.load() && job->handle->skin) {
            g_RmExecute(job->handle->skin, command.c_str());
        }
        ReleaseSRWLockShared(&job->handle->lifeLock);
    }
    return 0;
}

} // namespace

extern "C" {

__declspec(dllexport) void Initialize(void** data, void* rm) {
    EnsureApiResolved();
    auto* measure = new MeasureData();
    measure->rm = rm;
    measure->handle = std::make_shared<MeasureHandle>();
    if (g_RmGet) {
        measure->handle->skin = g_RmGet(rm, RMG_SKIN);
    }
    *data = measure;
}

__declspec(dllexport) void Reload(void* data, void* rm, double* /*maxValue*/) {
    auto* measure = static_cast<MeasureData*>(data);
    if (!measure) return;
    measure->rm = rm;

    std::wstring streamName;
    if (g_RmReadString) {
        LPCWSTR s = g_RmReadString(rm, L"Stream", L"", FALSE);
        if (s) streamName = s;
        LPCWSTR fb = g_RmReadString(rm, L"FallbackPath", L"", TRUE);
        if (fb && *fb) {
            LPCWSTR absFb = g_RmPathToAbsolute ? g_RmPathToAbsolute(rm, fb) : fb;
            measure->fallbackPath = absFb ? absFb : L"";
        } else {
            measure->fallbackPath.clear();
        }

        LPCWSTR hp = g_RmReadString(rm, L"HelperPath", L"#@#SlateHUDHelper.exe", TRUE);
        std::wstring hpResolved = hp ? hp : L"";
        if (!hpResolved.empty() && g_RmPathToAbsolute) {
            LPCWSTR absHp = g_RmPathToAbsolute(rm, hpResolved.c_str());
            if (absHp) hpResolved = absHp;
        }

        LPCWSTR fa = g_RmReadString(rm, L"FinishAction", L"", FALSE);
        std::wstring finish = fa ? fa : L"";

        if (measure->handle) {
            AcquireSRWLockExclusive(&measure->handle->cfgLock);
            measure->handle->helperPath = hpResolved;
            measure->handle->finishAction = finish;
            ReleaseSRWLockExclusive(&measure->handle->cfgLock);
        }
    }
    measure->slotIndex = ParseSlotIndex(streamName);
}

__declspec(dllexport) double Update(void* data) {
    auto* measure = static_cast<MeasureData*>(data);
    if (!measure) return 0.0;
    measure->hasUpdated = true;

    std::string utf8;
    if (!TryReadSharedMemory(measure, utf8)) {
        if (!TryReadDiskFallback(measure->fallbackPath, utf8)) {
            measure->cachedText.clear();
            return 0.0;
        }
    }
    measure->cachedText = Utf8ToWide(utf8);
    return measure->cachedText.empty() ? 0.0 : 1.0;
}

__declspec(dllexport) LPCWSTR GetString(void* data) {
    auto* measure = static_cast<MeasureData*>(data);
    if (!measure) return L"";
    if (!measure->hasUpdated) {
        Update(data);
    }
    return measure->cachedText.c_str();
}

__declspec(dllexport) void ExecuteBang(void* data, LPCWSTR args) {
    auto* measure = static_cast<MeasureData*>(data);
    if (!measure || !measure->handle || !args || !*args) return;

    auto* job = new BangJob();
    job->handle = measure->handle;
    job->args = args;
    if (g_RmReplaceVariables && measure->rm) {
        LPCWSTR expanded = g_RmReplaceVariables(measure->rm, args);
        if (expanded) job->args = expanded;
    }

    if (!QueueUserWorkItem(BangWorkerProc, job, WT_EXECUTEDEFAULT)) {
        BangWorkerProc(job);
    }
}

__declspec(dllexport) void Finalize(void* data) {
    auto* measure = static_cast<MeasureData*>(data);
    if (!measure) return;
    if (measure->handle) {
        AcquireSRWLockExclusive(&measure->handle->lifeLock);
        measure->handle->alive.store(false);
        measure->handle->skin = nullptr;
        ReleaseSRWLockExclusive(&measure->handle->lifeLock);
    }
    delete measure;
}

} // extern "C"
