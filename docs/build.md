# Build the accelerator

[简体中文](build.zh-CN.md)

The main repository contains the acceleration addon and the transformations used
to build its 47 selected Ada kernels. Supply the NR runtime from your local
[RenoDX DLSS5 installation](https://github.com/RankFTW/rhi-repo); the build extracts
the needed PTX locally, applies the recipes, compiles the addon, tests its routing,
and produces an installable ZIP.

## Requirements

- Windows x64, Python 3.11 or later (standard library only).
- Visual Studio C++ desktop build tools with a Windows SDK.
- CUDA Toolkit with `ptxas.exe` and `cuobjdump.exe`. The reproduction below used
  **CUDA 13.3**; generated PTX uses ISA version 9.3 and targets `sm_89`.
- NGX SDK headers: point `-NgxInclude` to the directory containing
  `nvsdk_ngx_params.h` and `nvsdk_ngx_defs.h`, available with the
  [NVIDIA DLSS SDK](https://github.com/NVIDIA/DLSS).
- The local community `nvngx_dlssnr.dll` containing the supported NR kernels.

## One build command

Open PowerShell in the repository or extracted source archive:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_local.ps1 `
  -RuntimePath 'D:\Games\YourGame\nvngx_dlssnr.dll' `
  -NgxInclude 'D:\SDK\ngx\include' `
  -CudaBin 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin'
```

Use the actual runtime and SDK locations on your machine. `-CudaBin` can be omitted
when `CUDA_PATH` points to the toolkit. MSVC is discovered automatically; an x64
Native Tools shell also works.

The final line prints the location of `build/local-<timestamp>/Faster-DLSS5-Ada.zip`.
Extract that ZIP and run **Start.cmd** to install over the working community base.
Compilation itself does not install anything or modify the runtime supplied as input.
Players receiving a complete ZIP only need the [normal installer](install.md).

Each build uses a new directory. It contains extracted inputs, transformed PTX,
47 cubins, compiler logs, generated dispatch headers, the compiled addon, test
results and the final ZIP. These are local build outputs.

## Where the acceleration code lives

| Source | Responsibility |
|---|---|
| [src/integration/ada_nr_addon.cpp](../src/integration/ada_nr_addon.cpp) | Runtime integration, loading the local images, replacement dispatch and Evaluate forwarding. |
| [src/optimization/dynamic_contract.h](../src/optimization/dynamic_contract.h) | Native qualification, parameter and launch checks, dynamic dimensions, Pre/Post guards and fallback. |
| [config/network.json](../config/network.json) | Scalar ABI facts, 156-call sequence, 145 interior routes and selected shape specializations. |
| [config/kernel-recipes.json](../config/kernel-recipes.json) | The 47 selected recipes: pairing, register limits, block bounds, shared spilling and scalar folds. |
| [kernel_pipeline.py](../tools/optimizations/kernel_pipeline.py) | Applies each recipe and validates its input contract. |
| [ptx_ada_semantic.py](../tools/optimizations/ptx_ada_semantic.py) | Ada asynchronous-copy and completion adaptation; component reduction and fence lowering. |
| [ptx_qkv512.py](../tools/optimizations/ptx_qkv512.py), [ptx_projection_pairs.py](../tools/optimizations/ptx_projection_pairs.py) | Move proven fragment loads closer to their consumers in QKV and projection kernels. |
| [ptx_ffn256_n64.py](../tools/optimizations/ptx_ffn256_n64.py), [ptx_boundary_n64.py](../tools/optimizations/ptx_boundary_n64.py) | Pair N64 computation groups for selected FFN and boundary kernels. |
| [ptx_defer_shared.py](../tools/optimizations/ptx_defer_shared.py) | Shorten shared-load live ranges across independently verified instructions. |
| [ptx_shape_specialize.py](../tools/optimizations/ptx_shape_specialize.py) | Fold selected scalar parameters while retaining the declared dynamic dimensions. |

The [technical report](optimizations.md) explains the resource tradeoffs and timing
evidence. The recipe table contains the settings selected for the acceleration bundle.

## Build individual components

For development, use separate output directories:

```powershell
python tools/extract_local_ptx.py --runtime 'D:\Games\YourGame\nvngx_dlssnr.dll' --output build/input --cuobjdump "$env:CUDA_PATH/bin/cuobjdump.exe"
python tools/build_kernels.py --ptx-dir build/input --output build/kernels --ptxas "$env:CUDA_PATH/bin/ptxas.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_addon.ps1 -NgxInclude 'D:\SDK\ngx\include' -Bundle build/kernels -Output build/addon
python tools/package_accelerator.py --addon build/addon/ada-nr.addon64 --bundle build/kernels --output build/Faster-DLSS5-Ada.zip
```

`build_kernels.py --only integrated-12.cubin` builds one recipe for inspection;
repeat `--only` to select more. Packaging needs all 47 images. `--jobs` controls
parallel compilation (default 4).

Recipe matching checks entry parameters, copy sizes, instruction dependencies and
the regions being transformed. It does not require a whole-runtime hash match.
A change to those contracts produces a specific build error so the corresponding
recipe can be updated. Build receipts record input/output identities for traceability;
the addon is compiled against the images produced by that build.

## Reproduction and checks

The source build extracted **15 PTX modules** from the tested community runtime and
rebuilt **47/47 cubins byte for byte identically** to the retained acceleration bundle
with CUDA 13.3. This establishes reproduction of the selected GPU code. The addon
compiled from this repository passed synthetic native-route tests and the assembly
audit that checks Evaluate forwarding remains a tail jump.

See the [reproduction receipt](../benchmarks/source-reproduction-2026-09-10.json)
and [verification record](verification.md). Existing GPU correctness and timing
measurements remain documented separately in the benchmark and technical reports.

```powershell
python -m unittest discover -s tests -p test_*.py
powershell.exe -NoProfile -File tests/manager.Tests.ps1
python tools/package_preview.py
```

The source archive includes our addon, transforms, metadata and tests. Vendor runtime,
PTX, SASS, weights and generated GPU binaries are obtained or produced locally;
see [package contents](distribution.md).
