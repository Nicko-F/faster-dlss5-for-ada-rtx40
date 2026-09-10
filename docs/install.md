# Install once, launch at your chosen resolution

[中文](install.zh-CN.md)

The source preview contains no acceleration payload. Check can inspect the base;
Install and Launch need the complete local package, which remains local-only.

## Requirements

Install the community base and confirm it works first. This is an incremental
acceleration patch, not an all-in-one compatibility package. The patch does not
install or repair the base; its checks identify the tested base and whether our
specific substitutions can be used.

- Windows PowerShell 5.1 and a writable extracted package folder.
- Validated RTX 4080, driver 616.56, Cyberpunk 2077 2.31.
- An existing matching ReShade 6.8.0 addon / RenoDX DLSS5 4.70 / community NR
  310.8.0 installation, including its normal Visual C++ runtime dependencies.
- SDR, NR enabled, RenoDX style/preset 0 and intensity 1 as used in the measured
  game setup. Other modes still require validation.

Dimensions follow the native runtime automatically. There is no resolution
argument, aspect-ratio selector or requirement to reinstall after a size change.
See [scope and validation](dynamic-dimensions.md).

## Complete local package

1. Close the game. If an earlier fixed-size draft is installed, use **Remove** first; this draft can recognize
   and remove its recorded addon. Do not overwrite an existing installation.
2. Extract the entire automatic-dimension draft archive to a writable folder and keep it there.
3. Double-click **Start.cmd**, choose **Check compatibility**, and enter the game folder.
4. Choose **Install**, then **Launch**. Choose your resolution in the game normally.
5. After exiting, choose **Verify latest run**. It reports observed NR dimensions
   and checks all complete graph records for substitution counts and errors.
6. To restore the existing community path, close the game and choose **Remove**.

Only our addon and installation record are added to `bin/x64`. Kernels and logs
remain in `profiles/automatic/bundle`. The manager does not replace community
binaries, download a runtime, edit game settings or persist environment variables.
It passes the bundle location to the launched game process. A normal Steam launch
is not a verified optimized launch; use this manager.

```powershell
.\tools\Manage.ps1 -Action Check -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Launch -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\Cyberpunk 2077'
```

Status validates routing, not image quality or GPU time. No-history frames may
keep two native Pre/Post calls while the 145 interior calls are replaced. Different
dimensions can appear in one launch; incomplete or failed routing causes a refusal.

Keep the package in place for Launch/Status. If it was lost or moved, an intact
copy of this manager can remove its recorded known addon without the old payload.
Changed or unknown addon files are never overwritten or silently deleted.
`-Action Remove -ForgetRecordOnly` explicitly forgets only our record and keeps
any addon file; it does not uninstall that file.

`compatibility/automatic.lock.json` pins the automatic-dimension draft manifest and addon; the legacy
lock is retained only for fixed-size draft removal. Hashes detect drift, not independent
publisher authentication. Obtain the entire package from the project owner.
