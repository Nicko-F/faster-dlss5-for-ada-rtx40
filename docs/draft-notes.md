# Unreleased draft — first release pending

No first release has been made. The owner will decide when to publish and assign a version.

[中文发布说明](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/blob/main/docs/draft-notes.zh-CN.md)

Install once.

This is an incremental acceleration patch for a working community base; the base
retains runtime, model, game insertion and resolution responsibilities.

No 1080p / 1440p / 4K choice is needed. The local accelerator follows
DLSS5's incoming network dimensions, padding and launches, including checked 16:10
and ultrawide cases. Four previously size-folded call sites gain general variants;
known-size fast paths remain automatic. Status reports actual observed NR sizes.

Separate community/optimized process checks compare final images after three
frames, including static, motion and one NR+SR case. These are correctness checks;
the published timing tables remain the frozen fixed-size draft results. No new game benchmark
or general performance percentage is claimed. See the dynamic-dimension report.

This development draft stays **private**, with Issues and Discussions for
invited collaborators. The local SOURCE-PREVIEW archive contains bilingual docs,
manager source, checks and results, **no accelerator kernels or implementation**.
The full automatic-dimension draft bundle stays local; GPU redistribution permission is unresolved.

The manager preserves known-addon-only removal, including fixed-size draft recovery. Hardware,
runtime identity and supported-mode checks remain; dimension support does not
automatically validate other GPUs, drivers, games, HDR or dynamic-resolution modes.
