# Installation

[简体中文](install.zh-CN.md)

This is an acceleration patch for **[RenoDX DLSS5](https://github.com/RankFTW/rhi-repo)** on Ada / RTX 40.
Install the community base first and confirm that DLSS5 works in your game.
[Community downloads](https://github.com/RankFTW/rhi-repo/releases) · [ReShade with addon support](https://reshade.me/)

Check the [download guide](downloads.md) to identify the complete acceleration package.

## Install

1. Close your game and extract the acceleration package.
2. Double-click **Start.cmd**. Choose English or 简体中文 in the top-right corner.
3. Click **Browse** and select your game folder. You can also select the folder containing `renodx-dlss5.addon64` directly.
4. Click **Install / update**. The same button handles first installation and updates.
5. Start the game from Steam or your usual launcher and enable DLSS5 as you normally would.

The installer remembers the selected folder. You can move or delete the downloaded
package after installation. No Python, CUDA Toolkit, command-line setup or resolution
profile is needed. Resolution, aspect ratio and padding follow your community base.

## Check that it is working

Open **Start.cmd** and select **Check status**. An installed copy is also available at
`faster-dlss5/Start.cmd` beside your community addon.

- **Installed:** ready for you to start the game and enable DLSS5.
- **Waiting:** the last record shows the addon loaded, awaiting DLSS5 frames or checking native calls.
- **Acceleration worked:** the recorded game session used the optimized kernels.
- **Some work used the community path:** use **Export diagnostics**, then attach the ZIP through **Report a problem**.

The first native network evaluations establish the call contract automatically.
Acceleration starts after that check succeeds. Status shows the recorded session
time, so you can distinguish the last run from a game you have just opened.

## Update or remove

To update, close the game, open **Start.cmd** from the new complete package, select
the same folder and click **Install / update**. The manager prepares and verifies
new files before replacing the installation, and restores the old installation if
file replacement fails. The previous addon, bundle and additional files are saved
in the displayed `faster-dlss5-backup-…` folder. You can delete that backup after
checking the new installation.

To uninstall, close the game and click **Remove patch**. The community base stays
in place. Modified or added files inside the patch directory are preserved in a
nearby recovery folder, whose path is shown by the manager.

## Export diagnostics and report a problem

1. Select your game folder, click **Export diagnostics**, and save using a new ZIP filename.
2. Review its text files, then click **Report a problem**. Describe your game, GPU, actions and symptoms, and attach the ZIP.
3. No benchmark is required. Use the separate **Performance results** form if you want to share measurements.

The ZIP contains installation identifiers, OS/GPU information, status and up to
2,000 recent lines from each event/frame log. Absolute local paths are redacted.
Nothing is uploaded automatically. If export fails, copy the message or expanded
**Details** into your report instead.

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
| Acceleration already installed | Click **Install / update** directly. |
| Install disabled; source tools message | Check the [download guide](downloads.md); installation requires the complete package. |
| Package file damaged or missing | Extract the complete acceleration archive again. |
| Installed, but no recorded frames | Enable community DLSS5 in the game, exit normally, then check status. |
| An `ADA_NR_BUNDLE` override is shown | Remove that old experimental environment setting if you intend to use the installed bundle. |
| Some calls use the community path | Click **Export diagnostics**, then **Report a problem**. |
| Folder cannot be written | Check its write permissions; for an export, choose a writable location such as your Desktop. |

For scripted installation:

```powershell
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\YourGame'
```

[Package contents](distribution.md) · [Technical report](optimizations.md)
