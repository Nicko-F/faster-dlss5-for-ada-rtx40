# Installation

[简体中文](install.zh-CN.md)

This is an acceleration patch for **[RenoDX DLSS5](https://github.com/RankFTW/rhi-repo)** on Ada / RTX 40.
Install the community base first and confirm that DLSS5 works in your game.
[Community downloads](https://github.com/RankFTW/rhi-repo/releases) · [ReShade with addon support](https://reshade.me/)

## Install

1. Close your game and extract the acceleration package.
2. Double-click **Start.cmd**. Choose English or 简体中文 in the top-right corner.
3. Click **Browse** and select your game folder. You can also select the folder containing `renodx-dlss5.addon64` directly.
4. Click **Install acceleration**.
5. Start the game from Steam or your usual launcher and enable DLSS5 as you normally would.

The installer remembers the selected folder. You can move or delete the downloaded
package after installation. No Python, CUDA Toolkit, command-line setup or resolution
profile is needed. Resolution, aspect ratio and padding follow your community base.

## Check that it is working

Open **Start.cmd** and select **Check status**. An installed copy is also available at
`faster-dlss5/Start.cmd` beside your community addon.

- **Installed:** ready for you to start the game and enable DLSS5.
- **Waiting:** the addon is loading or checking the native network calls.
- **Acceleration worked:** the recorded game session used the optimized kernels.
- **Some work used the community path:** select **Open diagnostics** for details.

The first native network evaluations establish the call contract automatically.
Acceleration starts after that check succeeds. Status shows the recorded session
time, so you can distinguish the last run from a game you have just opened.

## Update or remove

Close the game, select **Remove patch**, then install the replacement package if
updating. The community base stays in place. If files inside the patch directory
were modified or added, the manager preserves them in a nearby recovery folder
and shows its path.

## Folder layout

```text
community addon folder/
  renodx-dlss5.addon64         community base
  nvngx_dlssnr.dll            community NR runtime
  ada-nr.addon64              acceleration addon
  faster-dlss5-install.json   installation record
  faster-dlss5/               installed tools and acceleration bundle
    Start.cmd
    tools/
    profiles/automatic/
```

The installer discovers the base by its files, not by a game name. Runtime support
is checked through the loaded interface and actual network call contracts. Updating
a game, driver or community plugin does not trigger a whole-file hash whitelist.
The tested configuration and performance measurements are in [Benchmarks](benchmarks.md).

## If a step needs attention

| Message or symptom | What to do |
|---|---|
| Community addon not found | Select the directory containing `renodx-dlss5.addon64`; if the base is not installed, use the community links above. |
| Acceleration already installed | Use **Remove patch**, then install the new package. |
| Package file damaged or missing | Extract the complete acceleration archive again. |
| Installed, but no recorded frames | Enable community DLSS5 in the game, exit normally, then check status. |
| An `ADA_NR_BUNDLE` override is shown | Remove that old experimental environment setting if you intend to use the installed bundle. |
| Some calls use the community path | Attach the diagnostic logs to an [issue](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues), including your GPU and base version. |

For scripted installation:

```powershell
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\YourGame'
```

[Package contents](distribution.md) · [Technical report](optimizations.md)
