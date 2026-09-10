# Automatic-dimension draft validation scope

September 10, 2026. Packaging and correctness checks are separate from performance
measurements and from permission to redistribute the local GPU files.

- Native synthetic route tests check automatic selection, negative guards and
  unchanged caller descriptors/parameter blocks. These tests use generated shapes
  and are plumbing coverage, not independent proof of native dimension semantics.
- 580 recorded native interior-call contracts across four sizes were checked
  against the generated dimension guards.
- Real community and optimized GPU processes check static, motion and NR+SR
  final images. See [dynamic dimension scope](dynamic-dimensions.md) and its exported
  validation receipt. Final-image equality does not mean every tensor was compared.
- The build checks the required Evaluate forwarding convention and runs legacy
  route regression tests. Vendor ABI and GPU code stay in the private workspace.
- Windows PowerShell 5.1 manager fixtures cover automatic installation, mixed-size
  status logs, pinned manifest/addon identities, exact file sets, missing payload,
  collisions, tampered files, stale/partial logs, state-only recovery, moved/lost
  packages, record-only recovery and removal of known fixed-size draft installations.
- Fixture tests mock hardware/process checks and use dummy files; they do not
  prove GPU execution. Production hardware and baseline guards remain enabled.
- The final local bundle also passed install/remove against an isolated copy of
  the real matching game/community files, with production GPU/driver checks enabled.
  Base hashes were preserved. This placement test did not launch the game.
- Original NR/game timing arithmetic is rechecked without relabeling its fixed-size draft
  measurements as automatic-dimension draft performance. No new game benchmark is reported here.
- Source packaging has an explicit allowlist and rejects vendor instruction/GPU
  files, generated ABI headers, private folders and personal-path/token patterns.
  It verifies archive membership, content hashes and ZIP integrity. This is an
  engineering review, not a general legal certification.

```powershell
powershell.exe -NoProfile -File tests/manager.Tests.ps1
python -m unittest discover -s tests -p test_*.py
python tools/report_results.py
python tools/package_preview.py
```

The manager needs no Python. Arithmetic and packaging tools require Python 3.9+.
The authored V1 API declaration is documentation, not an accelerator implementation.
