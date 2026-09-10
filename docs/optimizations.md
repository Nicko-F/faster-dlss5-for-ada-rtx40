# Technical report: accelerating DLSS5 inference on Ada

[简体中文](optimizations.zh-CN.md)

## Abstract

This report describes improving the community DLSS5 compatibility path on Ada
while preserving numerical operations and data dependencies. The methods combine
asynchronous-copy completion protocols, shorter register live ranges, input-fragment
reuse inside fused FFNs, and joint selection of register budgets, shared spilling
and block compilation constraints. Paired RTX 4080 measurements reduced pure NR
time by **5.35% / 9.11% / 10.30%** at 1080p / 1440p / 4K; independent 4K processes
measured **8.16%**. Section 9 gives the setup and game results.

Sections 1–2 define scope and the cost model; Sections 3–7 develop the methods;
Section 8 covers integration; Sections 9–10 present validation, results and next
work. Hardware mechanisms cite NVIDIA documentation, model architecture cites
community research, and resource/performance figures come from this project's records.

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

For model architecture, we refer readers to the community project
[MLX-DLSS](https://github.com/iamwavecut/MLX-DLSS) and its
[model recovery notes](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/recovery-notes.md).
Those notes discuss downsampling and decoder connections, attention/FFN organization,
and a [temporal processing reference](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/recovery-notes.md#temporal-command-line-reference).
We use encoder, ViT, decoder and temporal Pre/Post as names for the corresponding
optimization regions below, focusing on how they execute on Ada.

The retained selection spans these regions.
One temporal graph can replace **145 interior calls plus two Pre/Post calls**.
There are **45 interior binary variants and two surface kernels** in the bundle;
variants and call sites are different counts because multiple calls reuse a
binary and some shapes select a specialized variant.

A CTA is a CUDA thread block; a warp contains 32 threads, each occupying a lane.
MMA means matrix multiply-accumulate and FFN means feed-forward network. In the
tiling discussion, N denotes output columns and K denotes the reduction dimension.

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

## 3. Asynchronous movement: Blackwell bulk copies to an Ada pipeline

### 3.1 Relevant architectural differences

The comparison here is GeForce RTX 50 Blackwell **compute capability 12.0 (sm_120)**
versus RTX 40 Ada **compute capability 8.9 (sm_89)**. Datacenter Blackwell 10.x should be analyzed against its own
capabilities. [NVIDIA GPU compute capability table](https://developer.nvidia.com/cuda/gpus)

| Mechanism | RTX 50 / Blackwell | RTX 40 / Ada | Porting consequence |
|---|---|---|---|
| Per-thread global-to-shared asynchronous copy | Supports `cp.async` | Supports `cp.async`: 4, 8 or 16 bytes per thread/instruction | Ada already has a hardware asynchronous path |
| TMA (Tensor Memory Accelerator) / bulk copy | Supports the corresponding bulk-transfer paths | No `cp.async.bulk` | Reassign copy participation and address calculation |
| Copy completion | Transaction barriers can track completed bytes | Ordinary `cp.async` completion can join a CTA-local barrier | Rebuild an equivalent completion protocol |

CUDA distinguishes the per-thread LDGSTS path, hardware-supported from compute
capability 8.0, from TMA, introduced with 9.0. The former moves global data directly
to shared memory. Linear TMA copies also differ from multidimensional tensor-map
copies: the 512-byte case below is linear.
[CUDA asynchronous data copies](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/async-copies.html)

**TMA, clusters and barriers serve different purposes.** A cluster organizes CTAs
and permits access to other member CTAs' shared memory; a barrier expresses
completion dependencies. A bulk copy need not involve multiple CTAs. Our example
uses CTA-local staging. Establishing cluster dependence elsewhere requires examining
launch configuration and destination ownership.
[NVIDIA Blackwell tuning guide](https://docs.nvidia.com/cuda/blackwell-tuning-guide/index.html)

### 3.2 Where compatibility lowering loses overlap

At the audited 512 FFN transfer sites, the original path elects one lane to issue a
512-byte bulk copy and records expected transaction bytes. The Ada implementation
distributes that region across a warp's 32 lanes. The data can remain identical
while three execution properties change:

1. **Per-lane addressing.** Each lane computes source and destination offsets.
   Those addresses and predicates compete with matrix fragments for registers.
   Direct asynchronous staging avoids payload registers, but addressing still costs work.
2. **Premature completion waits.** An immediate `commit_group; wait_group 0`
   makes issuing threads finish their copies before continuing otherwise independent
   arithmetic. This shortens the interval available to hide copy latency.
3. **Completion accounting.** Bytes transferred and arriving threads are different
   units. After splitting the transfer, consumers must observe completion of every
   contributing copy, not merely the arrival of the issuing threads.

Transaction barriers track both arrivals and asynchronous transaction quantities;
ordinary asynchronous barriers can defer phase completion through associated copy
completion. This distinction underlies the ported protocol.
[CUDA asynchronous barriers](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/async-barriers.html)

### 3.3 Mapping one 512-byte tile onto Ada

The retained 512 FFN implementation applies this mapping at two static bulk-copy
sites; four 512 pooling sites use the same approach. A static site can execute
repeatedly inside a loop.

| Component | Ada implementation |
|---|---|
| Participation | Copy-warp lane `i` handles bytes `[16i, 16i + 15]`, for `i = 0…31` |
| Coverage | `32 × 16 = 512` bytes, covering the original contiguous region |
| Transfer | Each lane issues `cp.async.cg.shared.global` into the original shared tile |
| Completion association | Each participating lane associates its preceding copies with the consumer's barrier |
| Consumption | Preserve consumer phase waits and tile layout before the original matrix operations |

We use `cp.async.mbarrier.arrive` without `.noinc`. Registration increments the
current phase's pending count; completion of preceding copies asynchronously
decrements it. Ordinary thread-arrival counts therefore remain intact while copy
completion is tracked separately. Consumers use successful `mbarrier.test_wait`
checks for the relevant phase. The association instruction is available from SM 8.0.
[PTX ISA: cp.async.mbarrier.arrive and mbarrier.test_wait](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html)

The port also uses Ada-supported wait forms and preserves ordinary arrival counts.
Copy registration must precede the last ordinary arrival in that phase, preventing
premature phase advancement. The transformation unit is therefore the complete
dependency chain: copy issue, completion registration, ordinary arrival and consumer wait.

Full 512-byte tiles have 16-byte-aligned sources and destinations. Other sites with
boundary branches must retain their valid-byte and zero-fill behavior: skipping an
out-of-range lane can otherwise leave stale shared data. The `cp.async.cg` cache
policy is also a choice to evaluate against reuse, not an automatic throughput gain.
[CUDA copy widths, alignment and cache paths](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/async-copies.html)

### 3.4 Wait at consumption and overlap the next transfer

**Ready to read** and **safe to overwrite** are separate dependencies. Double
buffering must enforce both, so a new writer cannot overtake the current readers.
[CUDA producer/consumer barrier pattern](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/async-barriers.html)

This conceptual schedule uses two shared tiles, `A` and `B`:

```text
Prologue: copy tile 0 → A; wait for A
Step 0: issue tile 1 → B; compute A; finish reading A; wait for B
Step 1: issue tile 2 → A; compute B; finish reading B; wait for A
…
Drain: compute the final ready tile; finish all reads and writes
```

For per-tile transfer time `L` and compute time `C`, a serial model costs
`N(L + C)`; ideal pipelining costs `L + (N − 1)max(L, C) + C`. This illustrates
the overlap ceiling. Actual execution adds issue/synchronization overhead,
bandwidth contention and resource costs. Less independent arithmetic leaves less
latency to hide, while deeper buffering consumes more shared memory.

In CUDA C++, a similar design can use `cuda::memcpy_async` with `cuda::pipeline`:
producers acquire free stages and commit copies; consumers wait before use and
release after reading. Keep participating warps converged for shared-pipeline
commit operations to avoid expanding batch counts and wait coverage through
divergence. In our fused kernels, the implementation connects directly to existing
barriers and staging buffers, preserving their mathematics and layout.
[CUDA pipeline lifecycle and warp entanglement](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/pipelines.html)

### 3.5 Evaluate overlap together with register allocation

Earlier copy issue can extend address, phase-state and pending-fragment lifetimes.
We therefore tune load placement and register allocation together, checking that
new spill costs do not consume the recovered overlap. Section 4 covers live ranges;
Section 5 covers fragment reuse inside fused FFNs.

A 12-entry async/resource bundle reduced full-NR time by **2.93–3.55%** across
paired and independent measurements. That figure belongs to the combined changes.
Module results appear below; current full-network results are in the
[benchmark report](benchmarks.md).

## 4. Uniform execution, register pressure and repeated spill/reload

### 4.1 Why the same register cap does not mean the same headroom

Reusing RTX 50-oriented PTX with the same per-thread register cap preserves the
mathematical workload, but Ada code generation can change register demand, load
ordering and staging costs. **The critical questions are which values occupy
ordinary thread registers after porting, and how long they remain live together.**

Both RTX 50 and RTX 40 have uniform registers and execution paths. Blackwell has
broader uniform arithmetic coverage, including the uniform floating-point add,
multiply and FMA operations in NVIDIA's instruction tables. Ada also supports
uniform integer, addressing and some conversion operations, with different coverage.
[NVIDIA Binary Utilities: Ada and Blackwell instruction sets](https://docs.nvidia.com/cuda/archive/13.0.2/cuda-binary-utilities/index.html)

For a warp-uniform scalar, the compiler can use the uniform path when the operation
and its consumers permit it. Moving such computation onto the ordinary thread path
can introduce ordinary-register temporaries, conversions and moves that compete
with A input fragments, B weight fragments and accumulators. Those matrix values
usually contain lane-varying data; uniform execution primarily relieves the
ordinary-register pressure from surrounding scalar computation.

The mechanism to consider is:

```text
Target uniform coverage, compatibility lowering and backend scheduling change
    → ordinary-register temporaries and live ranges change
    → the working set overlapping A/B fragments and accumulators grows
    → a fixed budget requires load rescheduling or spill/reload
    → fragments and accumulators repeatedly make room for each other
    → more memory operations and dependency waits
```

What grows is the ordinary-register working set required by the inherited load
schedule. With a fixed cap, final allocation can remain identical: the cost appears
as additional spill/reload rather than an increasing register count in the resource report.

### 4.2 Uniform-path changes observed in this model

The zero-value FP8 conversion audit found this static distribution across 24 entries:

| Compiled path | Ordinary F2FP zero conversions | Uniform UF2FP zero conversions | Total |
|---|---:|---:|---:|
| Official SM120 | 108 | 132 | 240 |
| Community SM89 | 240 | 0 | 240 |

**132 conversion positions move from the uniform to the ordinary path.** Unchanged
conversion counts therefore do not establish unchanged cost: execution paths and
register-use conditions differ. Ada's instruction table also lists `UF2FP`; actual
differences depend on formats, operand combinations and backend choices. This table
records the compiled behavior of these specific FP8 zero-conversion positions.

This audit establishes an architecture-related execution-path change. The QKV
controls below directly establish how register crowding and load scheduling produce
spills. Together they motivate revisiting register lifetimes when porting; the
controls have not separately attributed QKV's stack increase to uniform capability.

### 4.3 QKV: spilled accumulators also displace A/B fragments

After concentrated loading, the repeated 512 QKV matrix loop still needs these
values before its first MMA, counted in the original PTX order:

| 32-bit data values | Concentrated loading | Batched loading |
|---|---:|---:|
| Loop-carried accumulator values | 96 | 96 |
| B weight fragments | 48 | 48 |
| Loaded A input fragments | 32 (8 groups × 4) | 8 (2 groups × 4) |
| Total | **176** | **152** |

176 exceeds the 168-register budget before addresses and loop control are included.
This program-point count describes live data, rather than a whole-kernel
machine-code peak. The compiler can reduce this live set by changing load order.

In the community SM89 result, we traced this in-loop spill/reload chain:

```text
Physical registers hold a B fragment needed later
    → save that fragment to the thread-private local stack
    → reload an old accumulator into the freed registers
    → execute MMA and update the accumulator
    → store the updated accumulator back to its local slot
    → restore the B fragment for later matrix operations
```

A fragments undergo analogous displacement. Spilling an accumulator can therefore
require extra operand saves and restores, beyond storing a value once. These
accesses sit inside repeated computation and add memory instructions and dependency
chains. The sample's 184-byte per-thread stack comprises 88 bytes of accumulator
slots, 8 bytes of independent control slots, and 88 bytes of temporary/reused slots
holding A/B fragments and control values. This is capacity; executed traffic depends
on access frequency.

Two kinds of repeated loading matter: this section addresses **compiler-generated
local spill/reload to free registers**; Section 5's N64 reuse reduces **repeated
reads of shared A fragments in the original expansion loop**. Both depend on the
budget for retained fragments, but involve different memory paths and transformations.

### 4.4 Same-PTX, same-cap controls and the repair

With identical community-compatible PTX, compiler and optimization options, a
168-register cap produces:

| Compiled path | Actual registers/thread | Stack/thread | Static local loads/stores | 128-bit shared loads before the first loop MMA |
|---|---:|---:|---:|---:|
| Same compatible PTX → SM120 | 168 | 0 B | 0 / 0 | 2 |
| Same compatible PTX → SM89 | 168 | 184 B | 38 / 47 | 8 |
| SM89 with batched loading | 168 | 0 B | 0 / 0 | 2 |

The SM120 backend interleaves loading and computation automatically; concentrated
early loading on SM89 creates the fragment/accumulator competition above. Moving
SM89 loads closer to their consumers keeps actual registers at 168 and shared
memory at 8,208 bytes, preserves the mathematical order of all 256 matrix
multiply-accumulate instructions, and eliminates the local spill/reload chain.
The SM120 row is a local compilation control.

**The directly supported intervention is reducing simultaneously live data and
restoring interleaved loading and computation.** Uniform execution, copy adaptation
and backend scheduling are relevant factors in cross-architecture pressure; this
intervention demonstrates removing the sample's repeated displacement without
changing matrix mathematics or increasing the register cap.

The related 512 input/output projections replace early loading of eight fragments
with loading the two currently consumed fragments, preserving all 64 MMA operations'
order and the 128-register cap.

| Projection sample | Wait-based stack | Retained stack | Actual registers/thread | Shared/CTA |
|---|---:|---:|---:|---:|
| 512 input projection | 80 B | 0 B | 126 | 12,312 B |
| 512 output projection | 80 B | 0 B | 123 | 12,312 B |

Their local load/store instructions also disappear without additional shared
allocation. These changes remove the corresponding spill requirement; Section 6
addresses selecting storage for remaining spills.

### 4.5 Deliberately lower the register budget: accept spills for more CTA capacity

**Another adopted route lowers the per-thread register cap, accepting local spills
when the resulting execution organization is faster overall.** It can work with
no increase in shared-memory allocation.

An SM's register resources are allocated across resident blocks. High per-thread
allocation can let one CTA consume enough registers to exclude another. If that
CTA's warps wait together on texture, memory or matrix dependencies, the scheduler
has fewer ready alternatives. Lower allocation that crosses a CTA-capacity threshold
can supply more independent warps to fill those gaps. Additional spills cost work,
but the reduction in unhidden waiting can outweigh that cost.
[NVIDIA: register pressure, occupancy and latency hiding](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html)

**The 256 chained kernel is a concrete example.** It retains the original
`32 × 8 × 1`, 256-thread CTA while reducing the register budget from 168 to 128.
For 65,536 registers per SM:

| Registers/thread | Registers/CTA before allocation granularity | Register-only CTA/SM bound | Corresponding warps/SM |
|---|---:|---:|---:|
| 168 | 43,008 | 1 | 8 |
| 128 | 32,768 | 2 | 16 |

CUDA capacity queries for this sample also return **1 → 2 CTAs/SM and 8 → 16
warps/SM**. The selected implementation uses 128 registers and 16,384 bytes of
shared memory, retaining a **64-byte local stack** and reported spill stores/loads
of **100 / 76 bytes**. Shared allocation does not increase; local spills remain.
The N64 input-reuse plus 128-register combination reduces summed local replay time
across all 12 call sites by **17.85% / 18.92%** against community in two campaigns.
Those gains belong to the complete combination.

The increase is in **capacity for simultaneously resident CTAs**. Grid and runtime
threads per CTA remain unchanged; the GPU schedules their execution. Capacity
queries are not achieved-residency samples and do not attribute the entire gain
to the CTA count alone.

**Temporal Pre demonstrates accepting spills from a zero-stack starting point:**

| Compilation policy with original sampling order | Actual registers/thread | Local stack | Shared/CTA |
|---|---:|---:|---:|
| 168-register control | 168 | 0 B | 2,048 B |
| Retained 128-register implementation | 128 | 80 B | 2,048 B |

The retained implementation keeps the sampling order and 32-thread CTA while
accepting new local spills. Complete-Pre local time on history frames falls by
**6.60–9.82%** against community, without moving spills into shared memory. Resource
and timing results support this budget choice; dynamic residency and latency-hiding
contributions have not been measured separately.

Register optimization therefore involves three distinct interventions:

| Method | Target | Examples in this report |
|---|---|---|
| Shorten live ranges | Reduce spill/reload under the same budget | QKV and 512 projections |
| Lower the register budget | Accept some spill to improve CTA/warp capacity and scheduling | 256 chained, temporal Pre |
| Select spill storage | Reduce access costs for remaining spills | Section 6 shared spilling, temporal Post |

A register cap still differs from actual allocation: the selected 512 FFN has a
128-register cap but uses 118 registers with zero stack. Complete-kernel time decides
the selection, rather than uniformly maximizing registers or CTAs, or requiring zero stack.

## 5. Fused FFN, projection and boundary scheduling

### 5.1 Change reuse inside the fused operator

A fused kernel contains several internal computation phases. Its API boundary
does not need to change to improve one phase. We work on input-fragment reuse,
load placement and resource allocation while preserving the sequence of numerical
operations and the memory layout expected by the next phase.

In the selected 256 FFN expansion, two adjacent N32 output slices are paired into
an internal N64 group. Each K step loads input fragment A once and uses it with
the B fragments of both output slices:

```text
For adjacent output slices n and n+1:
    In the original K order:
        Load A[k]
        Update slice n with A[k] and B[n,k]
        Update slice n+1 with the same A[k] and B[n+1,k]
    Activate, convert and contract slice n in the original order
    Activate, convert and contract slice n+1 in the original order
```

This reduces A loads in the expansion loop, retaining B traffic and matrix work.
N64 is the internal output-tile width; model channels are unchanged. The second
slice needs separate accumulators, so the saved loads must outweigh the larger
live set. Each result retains its K accumulation order, contraction slice order,
FP8/FP16 conversions and output layout.

### 5.2 Apply related methods at scale boundaries

Boundary kernels also perform resampling or projection, whose surrounding work
and synchronization must remain intact. The final 256 input/output boundaries
retain N64 reuse plus deferred shared loads; 256 downsampling/upsampling retain
their execution tiles with revised register budgets. Even at one channel count,
the four boundaries use different final organizations.

Deferred loads cross only computation independent of the fragment, never writes
that modify the source, asynchronous copies or synchronization boundaries. The
selected Input128 defers 40 static shared loads; Down64 / Up64 defer 16 / 32;
Input256 / Output256 each defer 44 alongside N64 reuse. These counts describe
relocated instructions, not deleted loads.

The 512 FFN combines Section 3's asynchronous completion, a 128-register cap and
the `mma_throughput` compiler hint. Selected pooling combines asynchronous
completion with its own resource budget. The compiler chooses the concrete
schedule for a hint; measurements characterize the entire retained combination.

### 5.3 Module measurements

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

### 6.1 Let the compiler allocate spill storage

Local-memory spills are device-memory-backed and may hit cache. Moving them to
shared memory exchanges that access path for shared-memory capacity, addressing,
bank layout and possibly synchronization. Unused capacity alone does not determine
which path is faster.

CUDA 13's `enable_smem_spilling` lets PTXAS prefer shared spill storage and use
local memory for the remainder. The compiler manages slots and lifetimes instead
of requiring manual variable selection. It operates in the supported whole-program
compilation mode, excludes combinations such as dynamic shared memory, and uses
launch bounds in its allocation estimates.
[NVIDIA: shared-memory register spilling](https://developer.nvidia.com/blog/how-to-improve-cuda-kernel-performance-with-shared-memory-register-spilling/)

We select spill policy, register budget and legal block compilation constraints
together. A maximum compiled thread count is an upper bound, not necessarily the
runtime launch size; a required block size constrains the actual launch. Attention
and downsampling below retain their runtime thread counts while the compiler
generates spill layouts under the revised legal upper bounds.

### 6.2 Resource changes in retained implementations

| Selected family | Runtime threads/CTA | Compilation constraint | Shared/CTA before → after | Stack before → after | Capacity-bound CTAs/SM before → after |
|---|---:|---|---:|---:|---:|
| ViT attention | 128 | Maximum 256 threads, automatic shared spilling | 8,208 → 16,400 B | 32 → 16 B | 4 → 4 |
| 512 pooling | 128 | Require the original 128-thread block | 8,208 → 8,208 B | 88 → 56 B | 4 → 4 |
| 256 downsampling | 256 | Maximum 512 threads, automatic shared spilling | 16 → 30 KiB | 24 → 0 B | 2 → 2 |

These are compiled statistics and capacity queries against the preceding optimized
implementations in that campaign. CTA counts express resource capacity. All three
selections preserve that bound while changing staging or code generation.

The shared-memory convergence retained ten calls in three narrow families:

| Selected family | Incremental local reduction against the optimized selection | Interpretation |
|---|---:|---|
| Eight attention calls | 1.12–1.25% | Selected shared-memory/resource changes |
| 512 pooling | 2.05–2.42% | Fixed-block code generation; pragma on/off binaries were identical |
| 256 downsampling | 0.52–0.83% | Small repeatable local improvement |

The pooling control identifies its mechanism as fixed-block code generation.
Shared-memory changes are retained where they improve measured execution with the
surrounding register and synchronization costs included.

### 6.3 Account for access costs as well as capacity

Shared spill slots preserve thread-private value semantics; they are not a channel
for sharing values between threads. Cross-thread tile reuse separately requires
producer/consumer synchronization. These uses consume the same physical resource
but have different lifetimes and ownership.

Mechanism evidence here consists of resource changes, on/off comparisons under
the same compilation constraints and complete-kernel timing. No new bank-conflict
or dynamic spill-byte counts were collected, so stack reductions do not quantify
saved DRAM traffic. If shared allocation reduces CTA capacity or increases address
and access instructions, complete-kernel time decides the tradeoff.

## 7. Temporal Pre/Post and dimensions

### 7.1 Preserve sampling mathematics and tune resources

Pre/Post process surface inputs and outputs surrounding the interior network.
The selected Pre candidate keeps the texture schedule and uses a 128-register cap
with local spilling. Temporal-frame local repeats improved **6.60–9.82%**. The
selected Post uses a 128-register cap and shared spilling, with **2.84–4.19%** local
improvement. First/no-history paths remain native where the retained temporal
contract does not apply.

| Retained implementation | Runtime threads/CTA | Actual registers/thread | Stack | Reported spill stores/loads | Shared/CTA |
|---|---:|---:|---:|---:|---:|
| Temporal Pre | 32 | 128 | 80 B | 80 / 80 B | 2,048 B |
| Temporal Post | 32 | 128 | 0 B | 0 / 0 B | 2,560 B |

Both preserve sampling coordinates, texture access order, FMA and quantization.
Pre and Post select different spill policies from their complete-kernel results.
The table reports compiler statistics: Pre's 80 B is not 80 bytes of traffic per frame.

### 7.2 Validate real surfaces and history

Pre reads texture objects and Post writes a surface, so ordinary linear-pointer
replay is insufficient. Local validation retains actual textures, history and
other arguments while creating independent output buffers or matching-format
surfaces. Each arm restores full outputs and guard regions before execution, so
unwritten candidate regions cannot inherit reference data. Checks cover current
outputs and next-frame history, with static and moving inputs used to evaluate
the retained methods.

### 7.3 Pass dimensions as parameters

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

Evaluate forwarding preserves the original return address through a tail jump;
build-time assembly checks preserve caller identity and the integration contract.
Substitution occurs at network function selection, with presentation managed by
the community plugin.

## 9. Validation and final measured results

### 9.1 Experimental levels and statistics

| Level | Controlled setup | Recorded metrics |
|---|---|---|
| Compilation/resources | Fixed target SM, options, block and candidate identity | Actual registers, stack, spill instructions, shared size and capacity bounds |
| Local replay | Identical captured inputs, restored scratch/state, alternating arms | Complete-kernel time; module sums of call medians |
| Full NR | RTX 4080 / driver 616.56; fixed synthetic model1/sRGB input | 100 warmup frames and 400 measured frames per run; paired and independent processes |
| Game | Cyberpunk 2077 2.31 official benchmark; identical settings within each resolution | Two runs each of the original game, community and optimized paths; FPS and added frame cost |

Full-NR ABBA orders community, optimized, optimized, community; BAAB reverses it.
Paired NR figures average each arm's mean across two runs; independent-process
figures average two run P50s. Local replay uses its own statistics and is not mixed
with whole-network means. Game settings use High raster, native DLAA and SDR, with
RT, PT, RR, FG, dynamic resolution, Reflex, VSync and frame caps disabled.
[Full protocol and per-run summaries](benchmarks.md)

### 9.2 Correctness validation

Validation progresses from compiled resource inspection and operator replay to
output comparison, full inference and game measurements. The **200 captured tensors/outputs** from the integrated interior selection,
totaling **2.171 GB**, were byte-identical in its recorded validation. Surface candidates were checked separately. The
cross-size adapter matrix compares final images from independent native and
optimized processes with static, moving and NR+SR inputs: 12 pairs, three frames
per process, 72 frames total, with byte-identical final images.

Operator checks cover numerical outputs, read/write scratch, synchronization state
and guard regions; Pre/Post checks cover texture/surface outputs and history.
Cross-size final-image comparisons add integration coverage to the local
numerical checks.

### 9.3 Pure inference and game results

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

Game added cost is estimated as `mean(1000/FPS_on) − mean(1000/FPS_off)`, converting
each run to milliseconds before averaging. It includes the
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
