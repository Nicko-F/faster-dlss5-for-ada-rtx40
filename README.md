# Faster DLSS5 for Ada / RTX 40

**Making community DLSS5 neural rendering faster on Ada, with measured results.**

[中文](README.zh-CN.md) · [How it works](docs/optimizations.md) · [Measurements](docs/benchmarks.md) · [Install guide](docs/install.md) · [Roadmap](ROADMAP.md)

On our RTX 4080, the current experimental build reduces **4K neural-network GPU time by 8.16% in independent runs and 10.30% in interleaved runs**. In Cyberpunk 2077, the same optimization line improves **4K average FPS by 4.20%** over our pinned community baseline.

**Release status: private review repository; source and tooling preview.** The complete accelerator has been assembled for local testing. Its optimized GPU binaries are derived from NVIDIA-origin code; redistribution permission has not been established, so they are **not included in this public source tree**. Downloading this preview alone does not enable acceleration. See [release contents and permission status](docs/distribution.md). There is no public ready-to-use accelerator release yet.

## What we improve

- **Asynchronous data movement:** preserve useful producer/consumer overlap when adapting bulk-copy paths to Ada, instead of introducing unnecessary waits at each copy. Synchronization still protects every dependency.
- **Register pressure and spills:** schedule fragment loads near their use, shorten live ranges, and tune register budgets in fused projections, attention and FFN stages. Some audited projections eliminate their local stack traffic.
- **Uniform/scalar lowering differences:** adaptation can move work into general registers and increase pressure. This is one observed contributor, not proof that RTX 40 lacks uniform registers or that every spill comes from this difference.
- **Shared memory and stage scheduling:** retain measured shared-memory spill/staging improvements and resolution-specific execution choices. We do not move all spills into shared memory indiscriminately.
- **Guarded Pre/Post integration:** add preprocessing and postprocessing improvements where the exact shape, format and temporal-history requirements match.

The objective is to preserve NVIDIA's mathematics and data dependencies while organizing execution for Ada. Reported timings concern the measured experimental builds; they do not promise a fixed gain on every card, scene or game. [Technical explanation](docs/optimizations.md).

## Results

RTX 4080, driver 616.56, Ryzen 9 9950X. Lower is better for milliseconds. Pure NR uses fixed synthetic model1/sRGB inputs, 100 warmup + 400 measured frames. Each row aggregates two runs; methods remain separate.

| Resolution | Pure NR method | Community ms | Optimized ms | Time reduction |
|---|---|---:|---:|---:|
| 1080p | Independent | 4.8164 | 4.5786 | 4.94% |
| 1080p | Interleaved | 4.7539 | 4.4994 | 5.35% |
| 1440p | Interleaved | 7.5083 | 6.8246 | 9.11% |
| 4K | Independent | 18.2810 | 16.7892 | 8.16% |
| 4K | Interleaved | 17.6821 | 15.8614 | 10.30% |

Cyberpunk 2077 2.31 built-in benchmark, High raster, native DLAA, SDR, RT/PT/RR/FG/DRS/Reflex/VSync and frame cap off. Two runs per version. Original game means the experimental NR/ReShade stack is absent.

| Resolution | Original game FPS | Community DLSS5 FPS | Optimized DLSS5 FPS | FPS gain over community |
|---|---:|---:|---:|---:|
| 1080p | 179.57 | 91.37 | 92.62 | 1.36% |
| 1440p | 134.78 | 66.77 | 69.50 | 4.10% |
| 4K | 64.66 | 31.08 | 32.38 | 4.20% |

1080p game gains vary: the two latest paired gains are 0.42% / 2.33%; an earlier complete cohort produced 0.40% overall. GPU clocks were not locked. 1440p lacks an independent-process NR timing pair. Interleaved runs share temporal history and do not replace separate correctness checks. These are experimental results, not a universal performance guarantee.

### In-game added frame cost and the RTX 5070 Ti reference

We average each run's `1000 / FPS`, then subtract the same cohort's original-game average frame time. This estimates the **whole-frame cost added by enabling DLSS5**, including integration and synchronization; it is not isolated neural-network GPU time.

| Resolution | 4080 community added ms | 4080 optimized added ms | Saved ms | Cost reduction vs community | 5070 Ti external reference ms |
|---|---:|---:|---:|---:|---:|
| 1080p | 5.377 | 5.228 | 0.148 | 2.76% | — |
| 1440p | 7.558 | 6.968 | 0.590 | 7.80% | 7.8 |
| 4K | 16.714 | 15.416 | 1.298 | 7.77% | 17.0 |

The 5070 Ti numbers are from [TechSpot / Tim Schiesser, September 4, 2026](https://www.techspot.com/article/3170-real-dlss-5-performance/), testing **NBA 2K27's official integration**. Our 1440p/4K estimates are numerically 10.66%/9.32% lower than those published reference values. Different games, integrations and software/platform conditions mean this **does not establish that our 4080 is faster than a 5070 Ti under matched conditions**. The source's render-time table does not provide 1080p.

[Per-run measurements and calculation tool](docs/benchmarks.md) are included. Anyone can reproduce the table arithmetic without a GPU; reproducing the inference experiments also requires the currently withheld runtime/kernel dependencies.

## Which community baseline?

The measured game base is **ReShade 6.8.0 with addon support + RenoDX DLSS5 addon 4.70 + community-modified NR runtime 310.8.0**. We add our optimization layer to that installation. This is not a comparison against an unspecified “latest community version.” Exact file identities are in [baseline.json](compatibility/baseline.json).

The laboratory work used [kibblerz/DLSS5-Reshade-AIO](https://github.com/kibblerz/DLSS5-Reshade-AIO) at `74b9a2d4b32dcf958833ef11e712c153accada9d` and [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) at `75754b2278914d4b4bfb0accc4fd3d6333369b42`. The game's ReShade/RenoDX insertion path is separate from that laboratory host. [Credits and dependency notices](THIRD_PARTY_NOTICES.md).

## Use and compatibility

The public tools require Windows PowerShell 5.1, already present on the tested Windows system. Run `Start.cmd` to open the manager. It can inspect a matching installation; **Install and Launch require a complete acceleration payload**, which this source preview does not provide.

The local complete package offers three profiles: 1920×1080, 2560×1440 and 3840×2160. It checks hashes, refuses unknown existing addon files, launches with process-local settings, verifies routing logs and removes only its own installation. [Step-by-step guide](docs/install.md).

Validated target: RTX 4080 / driver 616.56 / Cyberpunk 2077 2.31. Other RTX 40 cards, newer drivers, HDR, RT/PT/FG combinations and other games are future validation targets. The manager intentionally stops on unvalidated hardware or binary identities. Keep a working community installation; no runtime, model weights or proprietary addon is bundled or automatically fetched.

## Discussion and continuing development

We intend to continue publishing new optimizations, measured results, compatibility profiles and release notes. We welcome benchmark reports, questions, reproducibility checks and contributions. The [roadmap](ROADMAP.md) records what is measured and what remains open; we do not promise a fixed release cadence or universal percentage gain.

The repository is private. [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) and [Discussions](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/discussions) are enabled for collaborators with repository access. Public publication remains a future decision. Please do not attach proprietary kernels, runtime DLLs, model weights, game resources or logs containing personal paths. Use the included [benchmark report template](.github/ISSUE_TEMPLATE/benchmark.yml).

## License

Original source, documentation and the exported measurements in this preview are provided under the [MIT License](LICENSE). This license grants no rights to NVIDIA, ReShade, RenoDX or other third-party software. NVIDIA, DLSS and GeForce RTX are trademarks of their respective owners. This is an independent project, not an NVIDIA release or endorsement.
