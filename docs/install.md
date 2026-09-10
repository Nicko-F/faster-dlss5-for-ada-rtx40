# Install, launch and remove

[中文](install.zh-CN.md)

The **public source preview lacks the acceleration payload**. Its manager can
inspect your baseline, but reports a missing-payload error instead of pretending
to install acceleration. The following full workflow applies to the complete
local testing package, which is not cleared for public redistribution.

## Requirements

- Windows with PowerShell 5.1; a writable extracted package folder.
- RTX 4080, driver 616.56 and Cyberpunk 2077 2.31, as currently validated.
- An existing working community installation: ReShade 6.8.0 addon support,
  RenoDX DLSS5 addon 4.70 and the measured community NR 310.8.0 DLL.
- The matching Microsoft Visual C++ x64 runtime required by the existing addon.
- A matching native 1920×1080, 2560×1440 or 3840×2160 output; SDR, NR enabled,
  RenoDX style/preset 0 and intensity 1 as used in the game experiments.

The manager verifies exact binary identities; it does not fetch or install vendor
software, downgrade drivers or change global settings. Do not substitute random
runtime downloads merely to satisfy a filename.

## Complete local package

1. Close the game. Extract the entire archive to a writable folder and keep it there.
2. Double-click **Start.cmd**. Choose **Check compatibility** and the game folder.
3. Choose **Install**, give the game folder, and select one exact resolution.
4. Choose **Launch**. Use the same resolution and settings inside the game.
5. Exit the game and choose **Verify latest run**. It checks complete observed
   graphs, the active hook, substitution counts and error counters.
6. To return to your existing community version, close the game and choose **Remove**.

Only our `ada-nr.addon64` and its installation record are added to `bin/x64`.
The kernels and logs stay in the extracted profile folder. Existing community
files and game settings are not overwritten. An unknown existing addon or a
changed addon hash causes a stop, not deletion. Install another resolution only
after removing the current installation. The menu checks 4K payload availability
by default; all profiles are present in the complete local archive.

Launch through this manager: it gives the game `ADA_NR_BUNDLE` only in that child
process. A normal Steam launch may not inherit the setting and is not a verified
optimized run. There is no registry/environment persistence. Keep the extracted folder intact for Launch and Status. If it was moved or lost,
use another intact copy of this source/manager release to Remove: removal uses the
recorded, pinned addon identity and does not require the payload or old folder.
If an unknown addon replaced ours, normal removal stops. Explicit
`-Action Remove -ForgetRecordOnly` forgets only our record and keeps that file.
It does not uninstall the unknown addon.

## Direct commands

```powershell
.\tools\Manage.ps1 -Action Check -GamePath 'D:\Games\Cyberpunk 2077' -Resolution 2560x1440
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\Cyberpunk 2077' -Resolution 2560x1440
.\tools\Manage.ps1 -Action Launch -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\Cyberpunk 2077'
```

Status reports routing, not image correctness or inference time. No-history frames
may retain the two original Pre/Post calls while the 145 buffer calls are optimized.
A game that launches without clean routing evidence has not validated acceleration.
Share only sanitized text summaries when reporting a problem.

The manager pins each accepted profile manifest and addon identity in
compatibility/profiles.lock.json and requires the exact expected file set. These
checks detect drift against this release. Checksums shipped beside a download
are not independent publisher authentication; obtain the whole release from the
project owner and do not trust a replacement checksum from an unrelated source.
