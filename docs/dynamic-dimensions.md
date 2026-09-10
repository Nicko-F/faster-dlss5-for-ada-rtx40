# One installation, native runtime dimensions

[中文](dynamic-dimensions.zh-CN.md)

The automatic-dimension draft removes the manual 1080p / 1440p / 4K installation choice. The same addon and
GPU bundle follow the dimensions supplied by DLSS5. Aspect ratio is not an
optimization profile: 16:10 and ultrawide inputs use the same path.

DLSS5 continues to choose the network rectangle, padding, tiles, memory layout,
launch grid and scalar arguments. We keep those incoming values and replace only
the selected GPU function when its contract matches. We do not resize the image
or construct a second partitioning system in the installer.

Most retained kernels already used dynamic dimensions. Four call sites had
dimension constants folded by our earlier optimization. Their new general variants
keep height and width dynamic and fold only model-invariant choices. Previously
measured size-specific fast paths remain available automatically when both active
and internal dimensions match exactly. Users do not select them.

## Evidence and boundaries

Real RTX 4080 runs compare separate community and optimized processes. Static
input checks cover 1600×1000, 1920×1200, 2560×1600, 3440×1440, 1919×1199 and the
original 1920×1080, 2560×1440, 3840×2160 sizes. Motion checks cover 1920×1200,
2560×1600 and 3440×1440. Each case compares the final exported image after three
frames and checks the observed replacement/error counters. This is not an
exhaustive temporal-quality evaluation or an intermediate-tensor comparison.

The tested sizes are examples, not a list enforced by the installer. Unknown
dimensions can use the general path if the native model/launch contract matches.
Unsupported contracts retain the native call and appear in routing diagnostics;
they must not be reported as fully accelerated. Huge allocations can still exceed
the GPU/runtime limits. No finite test set proves every possible image size.

NR size and final display size are separate concepts. Upscaling remains the
runtime's job. A standalone NR+SR check also exercises 1280×800 input to
1920×1200 output; this does not establish every game or dynamic-resolution mode.
Changing resolution requires no reinstall, but long game sessions with resolution
switches and dynamic resolution still need validation.

145 interior calls can be replaced, with two additional Pre/Post calls when the
supported temporal surface contract is present. First/no-history frames retain
the native Pre/Post calls. The local bundle contains one addon and 47 GPU files
(45 interior variants and two Pre/Post kernels), shared across all sizes.

Hardware, runtime identity, preset and format checks remain in force. This change
generalizes dimensions, not the set of validated GPUs, drivers, games or modes.
The public-compatible source preview contains the manager and results only; the
private implementation and derived GPU files remain outside it.

The timing tables elsewhere retain their fixed-size draft provenance. This dimension work
does not establish a new percentage speedup at the newly checked sizes.
