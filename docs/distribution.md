# Package contents

[简体中文](distribution.zh-CN.md)

The acceleration package contains the addon, selected GPU kernels and the bilingual
installer. The community base supplies the NR runtime, model and game integration.

This repository contains our acceleration addon, 47 kernel recipes, PTX transformation
tools, dispatch metadata, installer, tests, technical reports and measured results.
The [local build flow](build.md) uses your community runtime to produce an installable
acceleration package. The source archive contains no vendor PTX/SASS, runtime DLLs,
model weights or compiled GPU payload.

Original project files use the MIT license. Third-party components retain their own
licenses; see [Credits](credits.md). Distribution of the current derived GPU binaries
requires permission under the applicable NVIDIA terms. Those binaries remain in the
local acceleration package until that permission is established.
