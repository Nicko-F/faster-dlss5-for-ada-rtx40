# Adapting the execution plan for Ada

[中文](optimizations.zh-CN.md)

The measured accelerator builds on the community compatibility path. The goal is
to preserve numerical operations, MMA ordering and data dependencies while reducing
the overhead introduced by an execution plan that does not fit Ada as well.
This document describes the methods and observed results; it does not include
extracted vendor instructions, launch-parameter dumps or reconstruction recipes.

## Asynchronous movement and dependency placement

Bulk-copy adaptation can lose useful overlap if each smaller copy is immediately
followed by a wait. The retained experiments use per-lane 16-byte asynchronous
copies with barrier completion accounting. The consumer waits where the data is
needed; the producer can issue independent work beforehand. Buffer reuse still
requires the original dependency to complete.

Conceptual schedule, independent of any vendor implementation:

```
issue copies for next tile
compute using the already-ready tile
wait until the next tile is complete
switch buffers only after readers of the old tile finish
```

This is not a promise to remove all waits, emulate every Blackwell facility, or
keep all data permanently on chip. The amount of overlap depends on tile sizes,
available shared memory, occupancy and the surrounding fused work.

## Register lifetimes, uniform lowering and spills

Loading fragments too early keeps many values alive through unrelated work.
That raises general-register pressure and can produce local-memory stack traffic.
We move fragment loads closer to their use, preserve the arithmetic order, and
compare register allocations and resulting execution before retaining a candidate.

In the audited 512-channel input and output projection examples, the earlier
wait-based adaptation used 80 bytes of stack, a first asynchronous variant used
88 bytes, and the refined variants used zero. The refined variants retained
12,312 bytes of shared memory, with 126 / 123 registers respectively; their
inspected local load/store instructions were eliminated. These are **specific
projection examples**, not a claim that the whole model is spill-free.

The port also changes some uniform/scalar lowering. In the audit, 132 uniform FP8
zero-conversion positions across 24 entries changed representation. Total FP8
conversion counts remained consistent when uniform instructions were counted.
An instruction moving into ordinary registers is not evidence of a 32-fold cost
increase. Ada has uniform-register facilities; it is wrong to describe RTX 40 as
having none. We have not isolated uniform lowering as the sole cause of spills.

Increasing a register limit alone can reduce occupancy. Eliminating a stack alone
can also lose overall performance if it introduces extra instructions or staging.
We retain measured local improvements and then evaluate an integrated selection.

## Shared memory and fused stages

The retained shared-memory round selects ten calls: eight attention calls, a
512-channel pooling call and a 256-channel downsampling call. It adds a modest
increment to the already optimized build. A blanket local-to-shared rewrite was
not retained: bank layout, synchronization, instruction count and occupancy all
matter. Free shared-memory capacity is not by itself proof that using it is faster.

The wider work also adjusts fragment reuse and scheduling within fused encoder,
ViT and decoder stages. We avoid claiming that every fused stage now has its best
possible Ada implementation. The smaller 128/64/32 stages and lower resolutions
have different work-to-overhead ratios; they remain active optimization targets.

## Pre/Post and resolution profiles

The current integrated selection replaces 145 buffer calls in a matching observed
graph, plus two Pre/Post calls when temporal inputs are available. Startup or
no-history graphs keep the original Pre/Post path. The two smaller resolutions
use dedicated compiled profiles, including shape-specific choices; passing a
different resolution into an arbitrary 4K replacement is not sufficient.

Runtime, shape, launch and output-format guards restrict substitution. The public
manager additionally checks the exact measured community binaries and the tested
GPU/driver before installing. Routing evidence shows which path ran; it does not
establish temporal image quality or measure isolated GPU time.

## What is not claimed

We did not redesign the community plugin's game insertion in the published timing
comparison. The game delta therefore includes its synchronization and resource
competition. Pure NR and game results use different inputs and environments;
subtracting one from the other does not isolate plugin overhead.

The integration source and optimized vendor-derived payload are not included in
this public preview. The V1 API header documents our authored interface, but it
does not provide a public implementation. [Distribution status](distribution.md).
