# Native dimensions and automatic dispatch

[简体中文](dynamic-dimensions.zh-CN.md)

DLSS5 supplies the network rectangle, padding, tiles and launch parameters. The
patch forwards those values and selects the optimized function for the observed
contract. One installation follows the game's resolution and aspect ratio.

Most selected kernels already consume dynamic dimensions. Four call sites with
folded dimensions have general variants; exact known active and internal shapes
can select their specialized fast path automatically.

## Correctness matrix

| Input | Output | Check |
|---|---|---|
| 1600×1000, 1920×1200, 2560×1600 | Same size | 16:10 static inputs |
| 3440×1440 | Same size | Ultrawide |
| 1919×1199 | Same size | Odd active dimensions |
| 1920×1080, 2560×1440, 3840×2160 | Same size | Standard static inputs |
| 1920×1200, 2560×1600, 3440×1440 | Same size | Motion inputs |
| 1280×800 | 1920×1200 | NR + SR |

The matrix has 12 independent community/optimized pairs with three frames per
process, totaling 72 frames. Final exported images are byte-identical in every
pair. Startup runs natively to qualify the network; the following qualified graph
replaces 145 interior and two temporal surface calls, with zero routing errors.
[Machine-readable receipt](../benchmarks/dynamic-validation-2026-09-10.json).

The tested sizes are samples, not installer presets. General dispatch derives
shape relations from the runtime; matching unlisted sizes can use the same path.
Input NR size and final display size remain separate, as demonstrated by NR + SR.

## Integration

The bundle contains 45 interior variants and two Pre/Post kernels. Runtime entry
points, model/format information and a complete native call sequence establish the
contract before acceleration begins. Later calls retain live shape and ABI checks.
A contract that changes uses the community function.

The evidence was collected on RTX 4080 / driver 616.56. Those values identify the
test machine and do not restrict installation. Longer temporal runs, live resolution
changes and dynamic-resolution game sessions are further test targets. The matrix
checks final images and routing, while [timing measurements](benchmarks.md) have
separate recorded configurations.
