# Verification record

## Installer and interface

- Windows PowerShell 5.1 fixture tests cover game-folder discovery, updated base
  files, copied bundle placement, moving the download, normal-launch status,
  native qualification, incomplete/modified files, interrupted-install recovery,
  uninstall and reinstall. Community files are checked for preservation.
- The English/Chinese Windows form is constructed and its labels checked using
  the built-in Windows Forms runtime. This is a construction check, not a visual
  click-through test.
- Runtime loading negotiates the selected entry points. Native route tests verify
  initial qualification, live negative guards, unchanged caller argument blocks
  and descriptors, and invalid-sequence recovery. The build audits Evaluate's
  tail-jump forwarding convention.

## GPU and numerical checks

- 580 recorded native interior-call contracts across four sizes were checked
  against generated dimension guards.
- 12 independent native/optimized pairs cover static, motion and NR + SR inputs.
  Three frames per process give 72 frames total. Final images match byte for byte;
  startup qualification is native and subsequent qualified calls are accelerated.
  [Receipt](../benchmarks/dynamic-validation-2026-09-10.json).
- The interior optimization campaign compared 200 captured tensors/outputs,
  totaling 2.171 GB. These earlier intermediate-output checks and the current
  final-image matrix cover different validation scopes.
- Install/remove placement is tested using isolated copies of real community
  files. This does not launch the game. Historical game measurements and their
  settings are reported in [Benchmarks](benchmarks.md).

## Reproduce tool checks

```powershell
powershell.exe -NoProfile -File tests/manager.Tests.ps1
powershell.exe -NoProfile -STA -File tools/Setup.ps1 -ValidateOnly
python -m unittest discover -s tests -p test_*.py
python tools/report_results.py
python tools/package_preview.py
```

Only developer arithmetic and packaging tools need Python. The player installer
uses Windows PowerShell and Windows Forms. Source packaging checks an explicit
file list, archive contents and absence of vendor GPU files or private data.
