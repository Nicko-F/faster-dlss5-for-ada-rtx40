# Faster DLSS5 for Ada / RTX 40

**Faster neural rendering on RTX 40. / 让 RTX 40 的 DLSS5 神经渲染更快。**

<a id="chinese"></a>
<details name="language">
<summary><strong>简体中文</strong></summary>

基于社区 DLSS5 底座的轻量加速补丁。保留 NVIDIA 的数学运算与数据依赖，
针对 Ada 优化数据搬运、寄存器使用和融合内核调度。

### 优化内容

- **异步搬运**：恢复计算与拷贝的重叠，减少不必要的等待。
- **寄存器与 spill**：缩短变量活跃区间，将加载移近使用位置，减少栈访问。
- **Shared memory 与调度**：改善 attention、FFN 和上下采样的片上数据复用。

base 负责模型、运行库、游戏接入，以及分辨率、分区和 padding；补丁增加优化插件与选用的加速内核。

### 实测成绩

RTX 4080 · 驱动 616.56 · Ryzen 9 9950X。

| 分辨率 | 纯 NR 社区 → 优化 | NR 降耗时 | 游戏社区 → 优化 FPS | FPS 提升 |
|---|---:|---:|---:|---:|
| 1080p | 4.754 → 4.499 ms | 5.35% | 91.37 → 92.62 | 1.36% |
| 1440p | 7.508 → 6.825 ms | 9.11% | 66.77 → 69.50 | 4.10% |
| 4K | 17.682 → 15.861 ms | 10.30% | 31.08 → 32.38 | 4.20% |

纯 NR 表采用交替对照；4K 独立进程结果为 **18.281 → 16.789 ms（−8.16%）**。
游戏使用《赛博朋克 2077》内置 benchmark。完整设置、重复测量和 1080p 波动见[测试报告](docs/benchmarks.zh-CN.md)。
这些成绩来自此前固定尺寸构建；当前自动尺寸构建已通过 12 组正确性对照，性能待测。

| 分辨率 | 游戏新增帧成本：社区 → 优化 | 公开 RTX 5070 Ti 参考 |
|---|---:|---:|
| 1080p | 5.377 → 5.228 ms | — |
| 1440p | 7.558 → 6.968 ms | 7.8 ms |
| 4K | 16.714 → 15.416 ms | 17.0 ms |

新增帧成本按开启/关闭 DLSS5 的整帧时间差估算。
5070 Ti 参考来自 [TechSpot 的《NBA 2K27》测试](https://www.techspot.com/article/3170-real-dlss-5-performance/)，游戏与接入不同。

### 使用与进度

在已正常运行的 **ReShade 6.8.0 + RenoDX DLSS5 4.70 + 社区 NR 310.8.0** 上使用补丁。
完整本地包通过 `Start.cmd` 安装、启动和卸载，分辨率在游戏中正常选择。
仓库目前用于开发，首次发布待定；[安装与包内容](docs/install.zh-CN.md)。

[优化方法](docs/optimizations.zh-CN.md) · [尺寸验证](docs/dynamic-dimensions.zh-CN.md) ·
[后续计划](docs/roadmap.md) · [完整文档](docs/README.md)

我们会持续更新优化和实测结果。欢迎在 [Discussions](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/discussions)
交流思路，在 [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) 提交测试或问题。

</details>

<details name="language" open>
<summary><strong>English</strong></summary>

A lightweight acceleration patch for the community DLSS5 baseline. It preserves
NVIDIA's mathematics and data dependencies while tuning data movement, register
usage and fused-kernel scheduling for Ada.

### What we optimize

- **Asynchronous copies:** overlap transfers with computation and reduce unnecessary waits.
- **Registers and spills:** shorten live ranges and load fragments closer to use.
- **Shared memory and scheduling:** improve on-chip reuse in attention, FFN and sampling stages.

The base supplies the model, runtime, game integration, resolution handling,
partitioning and padding. The patch adds our optimizer addon and selected accelerated kernels.

### Measured results

RTX 4080 · driver 616.56 · Ryzen 9 9950X.

| Resolution | Pure NR: community → optimized | NR time reduction | Game: community → optimized FPS | FPS gain |
|---|---:|---:|---:|---:|
| 1080p | 4.754 → 4.499 ms | 5.35% | 91.37 → 92.62 | 1.36% |
| 1440p | 7.508 → 6.825 ms | 9.11% | 66.77 → 69.50 | 4.10% |
| 4K | 17.682 → 15.861 ms | 10.30% | 31.08 → 32.38 | 4.20% |

Pure NR rows use interleaved runs. Separate 4K processes measured
**18.281 → 16.789 ms (−8.16%)**. Game results use Cyberpunk 2077's built-in benchmark.
See [methods and repeats](docs/benchmarks.md), including the variable 1080p game gain.
These timings belong to earlier fixed-size builds; the automatic-dimension build
has passed 12 correctness pairs and awaits performance measurement.

| Resolution | Added game frame cost: community → optimized | Published RTX 5070 Ti reference |
|---|---:|---:|
| 1080p | 5.377 → 5.228 ms | — |
| 1440p | 7.558 → 6.968 ms | 7.8 ms |
| 4K | 16.714 → 15.416 ms | 17.0 ms |

Added cost is estimated from the whole-frame time difference with DLSS5 on/off.
The 5070 Ti reference comes from [TechSpot's NBA 2K27 test](https://www.techspot.com/article/3170-real-dlss-5-performance/),
using a different game and integration.

### Getting started

Start with a working **ReShade 6.8.0 + RenoDX DLSS5 4.70 + community NR 310.8.0** base.
The complete local patch uses `Start.cmd` to install, launch and remove it;
choose the resolution in the game as usual. Development is ongoing, with the
first release still to come. See [installation and package contents](docs/install.md).

[Optimization methods](docs/optimizations.md) · [Dimension checks](docs/dynamic-dimensions.md) ·
[Roadmap](docs/roadmap.md) · [Documentation](docs/README.md)

We will keep sharing new optimizations and measurements. Join
[Discussions](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/discussions) for ideas,
or use [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) for reports.

</details>

---

[MIT License](LICENSE) · [Credits](docs/credits.md)
