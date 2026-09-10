#pragma once
#include <windows.h>
// Host-owned initialization, before NR feature creation; no game-name dependency.
// Keep this library and the selected runtime loaded for the process lifetime.
struct AdaNrConfigV1 {
    unsigned structBytes,version;
    const wchar_t *bundlePath,*runtimePath; // Absolute paths; locally built bundle images are integrity checked.
    unsigned mode; // 0 native diagnostics, 1 buffer, 2 buffer + Pre/Post.
};
using AdaNrInitializeV1Fn=BOOL (WINAPI *)(const AdaNrConfigV1*);
// Returned FARPROC has the official NVSDK_NGX_D3D12_EvaluateFeature signature.
// Invoke it from the original NR caller on the submitting thread, before each graph.
using AdaNrGetEvaluateV1Fn=FARPROC (WINAPI *)(HMODULE);
using AdaNrProfileV1Fn=const char* (WINAPI *)();
