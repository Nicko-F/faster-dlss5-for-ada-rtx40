# Technical report: accelerating DLSS5 inference on Ada

[简体中文](optimizations.zh-CN.md)

## 1. Objective and system boundary

Faster DLSS5 is an Ada / RTX 40 acceleration patch for
[RenoDX DLSS5](https://github.com/RankFTW/rhi-repo). The optimization target is
neural-rendering execution: preserve the model's numerical operations, MMA
accumulation order and data dependencies while adapting data movement, register
lifetimes and scheduling to Ada.

The community base supplies game integration, the NR runtime, model parameters,
image partitioning and padding. Our adapter selects optimized functions at existing
network call sites. Original resource bindings, argument buffers and launch
descriptors are forwarded. This lets a fused operator keep its external contract
while changing how it stages and consumes values internally.

The retained selection spans encoder, ViT, decoder and temporal Pre/Post work.
One temporal graph can replace **145 interior calls plus two Pre/Post calls**.
There are **45 interior binary variants and two surface kernels** in the bundle;
variants and call sites are different counts because multiple calls reuse a
binary and some shapes select a specialized variant.

## 2. Cost model: why a compatible implementation can still be slower

A useful diagnostic model is:

`Tkernel ≈ max(Ttensor, Ttransfer) + Tunhidden-dependency + Tspill + Tissue`

This is a reasoning model, not a set of independently measurable counters. Copy,
compute and memory service can overlap; changing a tile can change every term.
We therefore inspect generated resources and validate a hypothesis with execution
measurements, rather than ranking variants by instruction count alone.

Ada's resource limits constrain the available choices. NVIDIA documents 48 resident
warps, 64K 32-bit registers and 100 KB shared memory per SM for compute capability
8.9. Register or shared-memory allocation can limit active CTAs before arithmetic
throughput is exhausted. [NVIDIA Ada tuning guide](https://docs.nvidia.com/cuda/ada-tuning-guide/index.html)

For a CTA with `B` threads and approximately `R` allocated registers per thread,
`floor(65536 / (B × R))` is a first register-capacity bound on resident CTAs.
Allocation granularity, warp/block limits and shared memory impose further bounds.
Thus, more registers can remove spills while reducing the number of available
warps. Our occupancy discussion uses this capacity model and compiled metadata;
it is not a measurement of D3D command-list residency.

## 3. Asynchronous copies and completion scheduling

A bulk transfer adapted into smaller per-lane copies can lose overlap when a wait
is placed directly after each copy group. The resulting execution is logically
asynchronous but effectively serial along the critical path.

We preserve producer/consumer dependencies while moving completion waits to the
actual consumption boundary. The retained experiments use per-lane 16-byte
asynchronous copies and completion accounting. Independent arithmetic can execute
between issuing a transfer and consuming its destination. Buffer reuse still waits
for all readers and outstanding writes.

Conceptual schedule:

```text
issue next tile's transfers
compute with the tile that is already ready
complete the transfer group before consuming the next tile
reuse a staging buffer only after its previous readers finish
```

CUDA's asynchronous-copy and barrier primitives explain the separation between
issuing work and establishing completion. [CUDA programming guide](https://docs.nvidia.com/cuda/cuda-programming-guide/index.html)

We compare wait placement, staging lifetime and resulting register allocation
together. An early 12-entry async/resource bundle reduced full-NR time by about
**2.93–3.55%** across the recorded paired and independent measurements. This is a
combined result; it does not assign that percentage to asynchronous copies alone.
The native-copy control was approximately neutral.

## 4. Register pressure, uniform lowering and local-memory spills

The important quantity is the maximum number of simultaneously live values.
An input fragment loaded early can stay live across address construction,
synchronization and unrelated matrix operations. Delaying immutable loads until
closer to their use reduces this overlap without changing arithmetic order.

Our register work combines three choices:

1. Move fragment loads toward their consumers.
2. Retain useful reuse across MMA operations where it avoids redundant loads.
3. Compare register caps and compiler allocation in the surrounding fused kernel.

A representative 512-channel input/output projection audit showed **80 bytes of
stack** in a wait-based adaptation, **88 bytes** in an initial asynchronous form,
and **zero** in the refined forms. The refined examples used **126 / 123 registers**
and **12,312 bytes of shared memory**; inspected local load/store instructions were
eliminated. These are projection resource measurements, not a whole-model claim.

Uniform lowering is part of this problem, but should be described precisely.
The audit found **132 uniform FP8 zero-conversion positions across 24 entries**
whose representation changed in the Ada path. Total conversion counts remained
consistent when uniform instructions were included. Ada has uniform-register
facilities; the evidence is about different lowering and pressure on ordinary
registers, not an absence of uniform registers on RTX 40 or a proven 32× cost.

The objective is lower execution time. Register caps, load placement and reuse
are selected together to balance spill traffic and active warp capacity.

## 5. Fused FFN, projection and boundary scheduling

A fused kernel contains several internal computation phases. Its API boundary
does not need to change to improve one phase. We work on input-fragment reuse,
load placement and resource allocation while preserving the sequence of numerical
operations and the memory layout expected by the next phase.

For selected 256-channel boundaries, a wider output grouping allowed an input
fragment to serve more work before reloading. This trades reduced input traffic
against a larger live set. Deferred shared-memory loads and simple register
allocation changes were also retained where they beat more elaborate tiling.

The largest local improvements were concentrated in the deeper stages:

| Measured group | Local summed-replay time reduction | Measurement scope |
|---|---:|---|
| 512 FFN, 15 calls | 39.11% / 39.74% | Two orderings against community |
| 512 pooling | 16.29% / 16.45% | Same local campaign |
| Full 512 group, 66 calls | 22.31% / 22.18% | Sum of local call medians |
| ViT compute, 40 calls | 12.29% / 12.40% | Module campaign |
| Selected 256 boundaries | 19.02% / 18.89% | Boundary campaign |

These groups overlap and the campaigns use their own comparison selections.
They are not additive contributions to the final NR result. Hot replay repeatedly
uses the same operator and resources; full inference includes dependencies,
neighboring work and changing cache residency.

Smaller 128/64/32 stages offer less work per scheduling/staging overhead, so they
need channel- and shape-aware execution choices.

## 6. Shared memory: select profitable uses

Local-memory spills are device-memory-backed and may hit cache. Moving them to
shared memory exchanges that access path for shared-memory capacity, addressing,
bank layout and possibly synchronization. Unused capacity alone does not determine
which path is faster.

The shared-memory convergence retained ten calls in three narrow families:

| Selected family | Incremental local reduction against the optimized selection | Interpretation |
|---|---:|---|
| Eight attention calls | 1.12–1.25% | Selected shared-memory/resource changes |
| 512 pooling | 2.05–2.42% | Fixed-block code generation; pragma on/off binaries were identical |
| 256 downsampling | 0.52–0.83% | Small repeatable local improvement |

The pooling control identifies its mechanism as fixed-block code generation.
Shared-memory changes are retained where they improve measured execution with the
surrounding register and synchronization costs included.

## 7. Temporal Pre/Post and dimensions

Pre/Post process surface inputs and outputs surrounding the interior network.
The selected Pre candidate keeps the texture schedule and uses a 128-register cap
with local spilling. Temporal-frame local repeats improved **6.60–9.82%**. The
selected Post uses a 128-register cap and shared spilling, with **2.84–4.19%** local
improvement. First/no-history paths remain native where the retained temporal
contract does not apply.

The adapter consumes native dimensions and padding. Four previously
constant-folded sites have general variants, and exact known shapes can still
select their faster specialization. There is no player-selected resolution profile.
[Dimension design and test matrix](dynamic-dimensions.md).

## 8. Runtime integration and compatibility

The player installs one bundle beside the community addon. The adapter discovers
it relative to its own location, so normal game startup needs no custom launch
environment. It negotiates the ReShade addon API and the loaded NR/NVAPI entry
points. The installer does not gate on a game name, exact GPU model, driver string
or whole-file hashes of the community base.

Before substitutions begin, complete native evaluations qualify the observed
complete network sequence and each candidate route’s argument layout, dimensions,
launch geometry and resource contracts. The no-history initialization graph stays native; a qualifying temporal
graph enables subsequent substitutions. Each later call is still checked against
its live contract. A changed contract uses its community function.

Matching interfaces and call contracts allow compatible packaging/plugin updates;
they do not establish the mathematics of an unknown model that changes operations
under an identical interface. That is the meaningful boundary for compatibility
work. Package checksums serve integrity and experiment provenance, not an upstream
version whitelist.

The Evaluate forwarding path preserves the original return address through a tail
jump. Its assembly is checked during the build because ordinary wrapper calls
previously broke the game integration. The patch changes function selection rather
than the community plugin's presentation pipeline.

## 9. Validation and final measured results

Validation progresses from compiled resource inspection and operator replay to
output comparison, full inference and game measurements. The **200 captured tensors/outputs** from the integrated interior selection,
totaling **2.171 GB**, were byte-identical in its recorded validation. Surface candidates were checked separately. The
cross-size adapter matrix compares final images from independent native and
optimized processes with static, moving and NR+SR inputs: 12 pairs, three frames
per process, 72 frames total, with byte-identical final images.

| Resolution | Community NR → optimized NR | NR time reduction | Community game → optimized game FPS |
|---|---:|---:|---:|
| 1920×1080 | 4.7539 → 4.4994 ms | 5.35% | 91.37 → 92.62 |
| 2560×1440 | 7.5083 → 6.8246 ms | 9.11% | 66.77 → 69.50 |
| 3840×2160 | 17.6821 → 15.8614 ms | 10.30% | 31.08 → 32.38 |

NR values above use paired ordering. At 4K, independent processes measured
**18.2810 → 16.7892 ms, −8.16%**. The recorded GPU is RTX 4080, driver 616.56;
game results use Cyberpunk 2077's benchmark. Timing runs measured the selected
optimizations in fixed-shape builds. The current installation/contract changes
have their own correctness records and do not create new timing samples.

For total inference, Amdahl's law explains dilution. If a region occupies fraction
`f` of baseline time and its time falls by fraction `r`, the ideal total reduction
is `f × r`, before accounting for changed overlap and contention. A 20% reduction
in a region taking 25% of the total gives a 5% total reduction. Local percentages
also cannot be added across overlapping regions or different baselines.

Game added cost is estimated as `1000/FPS_on − 1000/FPS_off`. It includes the
integration path and interactions with rendering. At 4K it measured
**16.714 → 15.416 ms**. The public RTX 5070 Ti reference is **17 ms** from a different
game, NBA 2K27; it provides context rather than a controlled GPU speed ratio.
[Benchmark protocol and raw summaries](benchmarks.md) ·
[TechSpot reference](https://www.techspot.com/article/3170-real-dlss-5-performance/).

## 10. Interpretation and next work

Independent and paired measurements are both retained because cache/history,
clock behavior and run ordering can affect a small delta. GPU clocks were not
locked; paired arms share history. The 1080p game uplift was small and variable.
Final-image agreement covers the recorded inputs and does not replace long
motion-sequence evaluation.

The next useful work is to improve low-channel execution where staging overhead
is proportionally larger, measure the dimension-general selection at additional
shapes, and test contract-compatible community updates. Each retained change should
have a local mechanism, a correctness result and a clearly identified comparison
baseline. [Evidence tables](../benchmarks/optimization-evidence.json) ·
[Verification](verification.md) · [Roadmap](roadmap.md).
