# Continuing development

We will continue sharing new optimizations, measurements and compatibility work.
Performance targets are research goals, not promised results or delivery dates.

1. Establish a distributable acceleration payload and complete a public installation
   test from a fresh matching community setup.
2. Validate additional RTX 40 cards and newer drivers separately. Keep precise
   profiles and avoid advertising an untested universal driver workaround.
3. Improve small-resolution execution, especially the gap between 1080p NR timing
   and the game's variable FPS gain.
4. Continue profiling data movement, register lifetimes, attention/FFN scheduling,
   and Pre/Post processing. Retain local wins, then evaluate integrated builds.
5. Expand independent temporal/visual checks and longer game sessions.
6. Collect matched-game, matched-settings RTX 5070 Ti comparisons.

## Contribution policy

Questions, reproducible benchmark reports and independently authored code are welcome.
Please give GPU, driver, resolution, game/settings, base identity, timing method and
all repeats, including regressions. Do not submit proprietary runtime files,
extracted vendor code, weights, game assets or personal information.

Issues and Discussions are enabled inside the private review repository. Public
publication will be a separate decision after review.
