# Release preparation checks

Date: September 10, 2026. This records packaging validation, not a new performance
benchmark and not permission to redistribute the local GPU binaries.

- The measured two-run NR and game results were exported through an explicit
  field selection. The calculation tool reproduces every displayed table.
- Windows PowerShell 5.1 fixture tests cover installation, duplicate-install
  refusal, preservation of an unknown modified addon, normal removal, recovery
  with damaged payload files, baseline preservation, missing payloads, path
  traversal refusal, clean/partial routing logs and stale launch evidence.
- Tests also reject unpinned manifests and missing/extra/non-contiguous file sets,
  require the expected refusal reason, and cover state-only interrupted installs,
  a moved/lost package, invalid state identities, and explicit record-only recovery
  that preserves unknown files. The shipped compatibility lock binds profiles to
  the exact identities checked against accepted game runs.
- Fixture tests use dummy files and mocked hardware/process checks; they do not
  demonstrate a game run or GPU correctness. Production hardware guards remain
  enabled in the manager.
- Each full local profile's addon and every compiled GPU file were checked
  against both its selection/build manifest and two accepted game runs from the
  earlier benchmark cohorts. Those cohorts have zero bad observed graphs.
- All three profiles passed installation and removal against an isolated copy
  of the real matching game/community files, with the production RTX 4080 /
  driver 616.56 checks enabled. Original file hashes were preserved. This checks
  real binary placement and recovery; no new game was launched in this test.
- The local package contains 45 / 45 / 41 GPU files for 1080p / 1440p / 4K,
  including two Pre/Post files per profile. They remain outside the public tree.
- Public source packaging uses public-files.json; extracted instructions,
  executable binaries, generated vendor ABI headers and private repository
  directories are forbidden. It checks private-path/token patterns, archive
  membership, per-file hashes and ZIP integrity. This is an engineering audit,
  not a general legal certification.

Re-run the public checks:

```powershell
powershell.exe -NoProfile -File tests/manager.Tests.ps1
python -m unittest discover -s tests -p test_*.py
python tools/report_results.py
python tools/package_preview.py
```

Use Python 3.9+ for the arithmetic tool and Python 3.9+ for packaging. The package
manager itself does not require Python. The V1 header in include/ documents the
authored host interface only; no accelerator implementation is included here.
