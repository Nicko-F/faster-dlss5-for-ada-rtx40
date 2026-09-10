# Downloads and setup

[简体中文](downloads.zh-CN.md)

**Start with [RenoDX DLSS5](https://github.com/RankFTW/rhi-repo), then add the acceleration patch.**

1. Install the [community base](https://github.com/RankFTW/rhi-repo/releases) using its setup instructions, and check that DLSS5 works in your game.
2. Open [Faster DLSS5 Releases](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/releases/latest) for downloads.
3. With a complete acceleration package, extract it, run **Start.cmd**, select your game folder and click **Install / update**. Start the game through your usual launcher.

## Which package?

| Package | What it is for |
|---|---|
| **Complete acceleration package** | Playing with the optimization: includes the installer, addon and selected GPU kernels. |
| **Faster-DLSS5-Ada-Source.zip** | Addon source, kernel transformations, recipes, tests and reports. [Build a complete package](build.md) using your local community runtime. |
| **Source code (zip / tar.gz)** | GitHub's automatic snapshot of the repository at the release tag. |

**The current Release offers the source/tools archive. The complete acceleration package is currently kept locally and is not downloadable from Releases.** See [package contents](distribution.md) for distribution details.

The source manager shows a download link and keeps installation disabled when the acceleration payload is absent. You do not need to compile anything to use a complete package.

Developers can follow the [one-command build guide](build.md) to create that complete
package locally. The resulting ZIP includes the same player installer.

## Once you have the complete package

- No Python or CUDA Toolkit setup, command line, or resolution profile selection.
- **Install / update** handles both first installation and replacing an existing patch. Old files are saved in a backup folder shown by the manager.
- **Check status** shows whether acceleration was used in the last recorded run, with its timestamp.
- **Export diagnostics** creates a text-only ZIP for an [installation or game problem](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues/new?template=problem.yml).

[Step-by-step installation](install.md) · [Measured performance](benchmarks.md) · [Technical report](optimizations.md)
