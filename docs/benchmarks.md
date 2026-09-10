# Measurement protocol and reproducible arithmetic

These measurements belong to the frozen fixed-size draft builds. Correctness checks for the automatic-dimension draft are recorded separately; these tables are not a new benchmark of automatic-dimension draft.

[中文](benchmarks.zh-CN.md)

The [JSON dataset](../benchmarks/results-2026-09-10.json) includes every per-run
summary used in the current tables, including both orders. It contains no captured
tensors, GPU code or personal machine paths. Source-report SHA-256 values document
the export provenance; the full research reports remain private.

Run with Python 3.9 or later (standard library only):

```powershell
python tools/report_results.py
```

This recomputes the displayed tables from the exported measurements. It does not
launch the game or reproduce the neural network without its missing dependencies.

## Pure NR

RTX 4080, driver 616.56, model1/sRGB with fixed synthetic inputs. 100 warmup frames,
400 measured frames per run. Independent-process rows average each run's P50;
interleaved rows average the two runs' arm means. For each displayed row:

`time reduction = 100 * (1 - mean(optimized) / mean(community))`.

ABBA means community, optimized, optimized, community; BAAB reverses those labels.
Both orders are retained to reduce ordering bias. Interleaved arms share history,
so separate independent output checks are required. The two 4K interleaved runs
have substantial absolute-time drift; neither is discarded. Independent 4K timing
supports 8.16%, while interleaved timing gives 10.30%. Do not report a guaranteed
10% reduction from these observations.

1440p independent-process timing is missing, not zero. The previous 4K 10.20%
summary used a median of within-run group percentages; 10.30% uses the current
table's aggregate-ratio formula and is not a newly obtained speedup.

## Game

Cyberpunk 2077 2.31's built-in benchmark, High raster, native DLAA and SDR. Disable
RT, PT, RR, frame generation, dynamic resolution, Reflex, VSync and the frame cap.
Use the same settings for original game, community and optimized within a cohort.
Original game has no experimental NR/ReShade stack. Each role has two runs.
The three resolutions are separate complete cohorts, not one continuous session.

`FPS gain = 100 * (mean(optimized FPS) / mean(community FPS) - 1)`.

`added frame ms = mean(1000 / enabled FPS per run) - mean(1000 / original FPS per run)`.

Do not replace `mean(1000/FPS)` with `1000/mean(FPS)` or interpret added frame cost
as a timer around the neural network. The delta includes game insertion, waits and
resource competition. GPU clocks were not locked, and two repeats cannot establish
robust confidence intervals. The latest 1080p paired FPS gains are 0.42%/2.33%;
the earlier complete cohort's 0.40% remains an effective warning about variability.

A failed original-game 1440p attempt was excluded before a complete 1440p cohort
was rerun. Failed runs and old anomalous output controls are not performance
samples. Package identities are checked against accepted game routing evidence.
Completed short benchmarks are not proof of long-session stability or universal
visual equivalence.

## External 5070 Ti

[Tim Schiesser's TechSpot test](https://www.techspot.com/article/3170-real-dlss-5-performance/)
published on September 4, 2026 reports 7.8 ms at 1440p and 17.0 ms at 4K in its
“Measured DLSS 5 Render Times” table. Its game is NBA 2K27 with official DLSS5
integration. It estimates cost from on/off frame rates and adjusts some GPU
settings to DLAA to avoid bottlenecks. Its render-time table has no 1080p row.

`numerical difference from reference = 100 * (1 - our added ms / external ms)`.

This is 10.66% at 1440p and 9.32% at 4K. It is a comparison of published estimates
under different conditions, not a controlled GPU ranking, FPS gain, or pure NR
inference speedup. A matched-game/platform comparison remains on the roadmap.
