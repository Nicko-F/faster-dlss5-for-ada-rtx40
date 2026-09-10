# 构建加速包

[English](build.md)

主仓库包含加速插件源码，以及生成 47 个选定 Ada 内核的转换代码。
提供本地 [RenoDX DLSS5](https://github.com/RankFTW/rhi-repo) 使用的 NR 运行库后，
构建工具会在本地提取所需 PTX、应用优化配方、编译插件并测试路由，最后生成可安装的 ZIP。

## 准备环境

- Windows x64，Python 3.11 或更新版本，仅使用标准库。
- Visual Studio C++ 桌面生成工具及 Windows SDK。
- 带有 `ptxas.exe` 和 `cuobjdump.exe` 的 CUDA Toolkit。本轮复现使用
  **CUDA 13.3**；生成的 PTX 使用 ISA 9.3，编译目标为 `sm_89`。
- NGX SDK 头文件：`-NgxInclude` 指向包含 `nvsdk_ngx_params.h` 和
  `nvsdk_ngx_defs.h` 的目录，可从 [NVIDIA DLSS SDK](https://github.com/NVIDIA/DLSS) 获取。
- 本地社区版本的 `nvngx_dlssnr.dll`，其中包含本项目适配的 NR 内核。

## 一条命令完成构建

在仓库或解压后的源码目录中打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_local.ps1 `
  -RuntimePath 'D:\Games\YourGame\nvngx_dlssnr.dll' `
  -NgxInclude 'D:\SDK\ngx\include' `
  -CudaBin 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin'
```

将运行库和 SDK 路径替换为自己的实际位置。设置了 `CUDA_PATH` 时可以省略
`-CudaBin`。工具会自动寻找 MSVC，也可以在 x64 Native Tools 环境中执行。

最后一行会显示 `build/local-<时间>/Faster-DLSS5-Ada.zip` 的位置。
解压该 ZIP，双击 **Start.cmd**，安装到已正常运行社区 base 的游戏中。
构建过程本身只生成文件，不执行安装，也不修改输入运行库。
拿到完整 ZIP 的玩家直接使用[普通安装流程](install.zh-CN.md)。

每次构建使用新目录，保留提取的输入、转换后 PTX、47 个 cubin、编译日志、
自动生成的调度头文件、插件、测试结果和最终 ZIP。这些文件留在本地构建目录中。

## 加速代码在哪里

| 源码 | 作用 |
|---|---|
| [src/integration/ada_nr_addon.cpp](../src/integration/ada_nr_addon.cpp) | 运行库接入、本地内核加载、替换调度与 Evaluate 转发。 |
| [src/optimization/dynamic_contract.h](../src/optimization/dynamic_contract.h) | 原生调用资格验证、参数与启动检查、动态尺寸、Pre/Post 条件及回退。 |
| [config/network.json](../config/network.json) | 标量 ABI 信息、156 次调用序列、145 个内部路由及选定的尺寸特化。 |
| [config/kernel-recipes.json](../config/kernel-recipes.json) | 47 个选定配方：计算配对、寄存器上限、线程块约束、shared spilling 与标量折叠。 |
| [kernel_pipeline.py](../tools/optimizations/kernel_pipeline.py) | 按配方执行转换并校验输入契约。 |
| [ptx_ada_semantic.py](../tools/optimizations/ptx_ada_semantic.py) | Ada 异步搬运及完成通知适配、分量归约和 fence 转换。 |
| [ptx_qkv512.py](../tools/optimizations/ptx_qkv512.py)、[ptx_projection_pairs.py](../tools/optimizations/ptx_projection_pairs.py) | 将已验证的 QKV、投影 fragment 加载移近使用位置。 |
| [ptx_ffn256_n64.py](../tools/optimizations/ptx_ffn256_n64.py)、[ptx_boundary_n64.py](../tools/optimizations/ptx_boundary_n64.py) | 对选定的 FFN、边界内核进行 N64 计算组配对。 |
| [ptx_defer_shared.py](../tools/optimizations/ptx_defer_shared.py) | 在已验证独立的指令之间移动 shared 加载，缩短活跃区间。 |
| [ptx_shape_specialize.py](../tools/optimizations/ptx_shape_specialize.py) | 折叠选定标量参数，同时保留声明为动态的尺寸。 |

[技术报告](optimizations.zh-CN.md)说明资源取舍和测量依据；配方表保存加速包实际选用的设置。

## 分别构建各部分

开发时可以拆开执行，每次指定新的输出目录：

```powershell
python tools/extract_local_ptx.py --runtime 'D:\Games\YourGame\nvngx_dlssnr.dll' --output build/input --cuobjdump "$env:CUDA_PATH/bin/cuobjdump.exe"
python tools/build_kernels.py --ptx-dir build/input --output build/kernels --ptxas "$env:CUDA_PATH/bin/ptxas.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_addon.ps1 -NgxInclude 'D:\SDK\ngx\include' -Bundle build/kernels -Output build/addon
python tools/package_accelerator.py --addon build/addon/ada-nr.addon64 --bundle build/kernels --output build/Faster-DLSS5-Ada.zip
```

`build_kernels.py --only integrated-12.cubin` 可单独构建一个配方，重复 `--only`
可选择多个。组装完整包需要全部 47 个内核；`--jobs` 控制并行编译数量，默认为 4。

转换检查入口参数、搬运长度、指令依赖和待修改区域，不要求整个运行库的哈希一致。
这些契约发生变化时，工具会给出具体错误，便于更新对应配方。
构建记录中的输入输出摘要用于追溯；插件使用本次构建实际生成的内核身份信息。

## 复现结果与检查

本轮从已测试的社区运行库提取 **15 个 PTX 模块**，使用 CUDA 13.3 重新构建，
**47/47 个 cubin 与保留的加速包逐字节一致**，确认主仓库代码能复现选定的 GPU 实现。
从仓库编译的插件也通过了模拟原生路由测试，以及检查 Evaluate 保持尾跳转的汇编审计。

详见[复现记录](../benchmarks/source-reproduction-2026-09-10.json)与[验证说明](verification.md)。
已有 GPU 正确性检查和性能测量分别记录在测试报告与技术报告中。

```powershell
python -m unittest discover -s tests -p test_*.py
powershell.exe -NoProfile -File tests/manager.Tests.ps1
python tools/package_preview.py
```

源码包包含我们编写的插件、转换工具、元数据和测试。第三方运行库、PTX、SASS、权重及
生成的 GPU 二进制在本地获取或生成，包内容说明见[这里](distribution.zh-CN.md)。
