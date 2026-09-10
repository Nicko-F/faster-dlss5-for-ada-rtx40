# Faster DLSS5 for Ada / RTX 40

**Faster neural rendering on RTX 40. / 让 RTX 40 的 DLSS5 神经渲染更快。**

<a id="chinese"></a>
<details name="language">
<summary><strong>简体中文</strong></summary>

基于 [RenoDX DLSS5](https://github.com/RankFTW/rhi-repo) 的 **Ada / RTX 40 加速补丁**。保留 NVIDIA 的数学运算与数据依赖，
针对 Ada 优化数据搬运、寄存器使用和融合内核调度。

### 下载与安装

**[社区 base 下载](https://github.com/RankFTW/rhi-repo/releases) · [补丁下载与安装指南](docs/downloads.zh-CN.md) · [Releases](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/releases/latest)**

装好并运行社区 base 后，解压完整加速包，双击 **Start.cmd** → 选择游戏目录 → **安装／更新**。
之后照常启动游戏，通过**检查生效状态**查看最近运行记录；遇到问题可直接**导出诊断**并**反馈问题**。

当前 Release 提供源码工具包，完整加速包尚未提供下载。文件区别见[下载指南](docs/downloads.zh-CN.md)。

### 源码与构建

[加速插件源码](src/integration/ada_nr_addon.cpp) · [内核优化代码](tools/optimizations) ·
[47 个内核配方](config/kernel-recipes.json) · **[本地构建指南](docs/build.zh-CN.md)**

使用本地社区运行库，一条构建命令即可生成完整加速包。已用仓库源码复现全部 47 个内核，
与保留的加速版本逐字节一致。

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
计时来自固定尺寸构建的实测，通用尺寸包的验证记录见[技术报告](docs/optimizations.zh-CN.md)。

| 分辨率 | 游戏新增帧成本：社区 → 优化 | 公开 RTX 5070 Ti 参考 |
|---|---:|---:|
| 1080p | 5.377 → 5.228 ms | — |
| 1440p | 7.558 → 6.968 ms | 7.8 ms |
| 4K | 16.714 → 15.416 ms | 17.0 ms |

新增帧成本按开启/关闭 DLSS5 的整帧时间差估算。
5070 Ti 参考来自 [TechSpot 的《NBA 2K27》测试](https://www.techspot.com/article/3170-real-dlss-5-performance/)，游戏与接入不同。

[优化方法](docs/optimizations.zh-CN.md) · [尺寸验证](docs/dynamic-dimensions.zh-CN.md) ·
[后续计划](docs/roadmap.md) · [完整文档](docs/README.md)

我们会持续更新优化和实测结果。欢迎在 [Discussions](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/discussions)
交流思路，在 [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) 提交测试或问题。

</details>

<details name="language" open>
<summary><strong>English</strong></summary>

An **Ada / RTX 40 acceleration patch** for [RenoDX DLSS5](https://github.com/RankFTW/rhi-repo). It preserves
NVIDIA's mathematics and data dependencies while tuning data movement, register
usage and fused-kernel scheduling for Ada.

### Download and install

**[Community base downloads](https://github.com/RankFTW/rhi-repo/releases) · [Patch downloads and setup](docs/downloads.md) · [Releases](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/releases/latest)**

Once the community base works in your game, extract the complete acceleration package,
run **Start.cmd**, select your game folder and click **Install / update**.
Launch your game as usual. **Check status** shows the last recorded run;
**Export diagnostics** and **Report a problem** help if something needs attention.

The current Release provides the source/tools archive; the complete acceleration package is not yet downloadable. See the [download guide](docs/downloads.md) for package details.

### Source and build

[Acceleration addon](src/integration/ada_nr_addon.cpp) · [Kernel transformations](tools/optimizations) ·
[47 kernel recipes](config/kernel-recipes.json) · **[Local build guide](docs/build.md)**

One build command produces a complete acceleration package using your local community
runtime. All 47 kernels have been reproduced from this source, byte for byte identical
to the retained acceleration bundle.

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
Timings were measured in fixed-shape builds; validation of the general-dimension
package is recorded in the [technical report](docs/optimizations.md).

| Resolution | Added game frame cost: community → optimized | Published RTX 5070 Ti reference |
|---|---:|---:|
| 1080p | 5.377 → 5.228 ms | — |
| 1440p | 7.558 → 6.968 ms | 7.8 ms |
| 4K | 16.714 → 15.416 ms | 17.0 ms |

Added cost is estimated from the whole-frame time difference with DLSS5 on/off.
The 5070 Ti reference comes from [TechSpot's NBA 2K27 test](https://www.techspot.com/article/3170-real-dlss-5-performance/),
using a different game and integration.

[Optimization methods](docs/optimizations.md) · [Dimension checks](docs/dynamic-dimensions.md) ·
[Roadmap](docs/roadmap.md) · [Documentation](docs/README.md)

We will keep sharing new optimizations and measurements. Join
[Discussions](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/discussions) for ideas,
or use [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) for reports.

</details>

---

[MIT License](LICENSE) · [Credits](docs/credits.md)
