# Credits and dependency boundaries

- NVIDIA supplies the proprietary DLSS model/runtime. None is relicensed or bundled
  here. [DLSS SDK and license](https://github.com/NVIDIA/DLSS).
- [ReShade](https://reshade.me/) provides the game's addon host. The measured version
  was 6.8.0 with addon support. Its binary is not bundled.
- RenoDX DLSS5 addon 4.70 supplies the measured community game's DLSS5 insertion.
  The research installation used the artifact mirrored at
  [RankFTW/rhi-repo release 4.70](https://github.com/RankFTW/rhi-repo/releases/tag/renodx-dlss5-4.70).
  A mirror is not a redistribution grant. Do not assume an open license for RenoDX
  core also licenses this separate closed-source addon. It is not bundled.
- The measured NR 310.8.0 DLL is a community-modified binary, not represented as an
  official NVIDIA Ada release. Its identity is recorded in compatibility/baseline.json.
  It is not bundled or downloaded by our tools.
- [kibblerz/DLSS5-Reshade-AIO](https://github.com/kibblerz/DLSS5-Reshade-AIO), pinned at
  `74b9a2d4b32dcf958833ef11e712c153accada9d`, and its pinned DLSS5-Feeder dependency
  `75754b2278914d4b4bfb0accc4fd3d6333369b42` supplied the laboratory foundation.
  No AIO or Feeder source is copied into this preview. Current AIO licensing is
  not assumed to retroactively license every file of the earlier checkout.
- [TechSpot's original test](https://www.techspot.com/article/3170-real-dlss-5-performance/)
  supplies the attributed 5070 Ti reference values. We include the few reported
  numerical facts and attribution, not its article, charts or screenshots.

Names and compatibility hashes identify dependencies; they do not convey rights
to distribute them. MIT applies to the original files in this preview only.
