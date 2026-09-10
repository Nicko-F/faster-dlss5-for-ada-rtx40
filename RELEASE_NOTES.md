# v0.1.0 — private source and results preview

[中文发布说明](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/blob/main/RELEASE_NOTES.zh-CN.md)

This repository and release are **private for review**, following the owner's
latest instruction. Issues and Discussions are enabled for invited collaborators.
No public announcement or public accelerator release is being made.

Included: English/Chinese overview, detailed optimization explanation, exact
community base identities, per-run benchmark summaries, table calculator, original
Windows package manager, API declaration, tests and source-package audit.

Current RTX 4080 measurements:

- 4K pure NR: 18.2810 → 16.7892 ms independently (−8.16%); interleaved
  17.6821 → 15.8614 ms (−10.30%).
- Cyberpunk 2077 4K: community 31.08 → optimized 32.38 FPS (+4.20%).
- 4K DLSS5 added whole-frame cost: 16.714 → 15.416 ms (−7.77%).

The 5070 Ti's externally reported 17.0 ms comes from NBA 2K27 official integration.
It is a contextual reference, not a matched cross-GPU comparison. 1080p and 1440p
results and measurement limitations are in the README and dataset.

**The attached SOURCE-PREVIEW ZIP contains no acceleration kernels.** Install and
Launch need a complete payload, currently kept local because redistribution
permission for the vendor-derived GPU code has not been established. Do not
describe this download as a working standalone accelerator.

The complete local package has three exact tested resolution profiles and a
reversible manager. It is not uploaded to this repository or attached here, so
this repository remains suitable for later public-source review.
