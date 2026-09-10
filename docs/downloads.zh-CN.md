# 下载与安装

[English](downloads.md)

**先装好 [RenoDX DLSS5](https://github.com/RankFTW/rhi-repo)，再添加加速补丁。**

1. 按原作者说明安装[社区 base](https://github.com/RankFTW/rhi-repo/releases)，确认游戏中的 DLSS5 正常工作。
2. 打开 [Faster DLSS5 Releases](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/releases/latest) 查看下载文件。
3. 拿到完整加速包后，解压并双击 **Start.cmd**，选择游戏目录，点击**安装／更新**。之后照常从原启动器进入游戏。

## 应该下载哪一份？

| 文件 | 用途 |
|---|---|
| **完整加速包** | 用于游戏加速，包含安装器、加速插件和选定的 GPU 内核。 |
| **Faster-DLSS5-Ada-Source.zip** | 用于查看或开发工具、技术报告和性能数据；其中的管理器也能检查已有安装、导出诊断。 |
| **Source code (zip / tar.gz)** | GitHub 自动生成的、对应 Release 标签的仓库快照。 |

**当前 Release 提供源码工具包；完整加速包目前保存在本地，尚不能从 Releases 下载。** 分发详情见[包内容](distribution.zh-CN.md)。

源码管理器会显示下载入口，在缺少加速文件时禁用安装按钮。使用完整包无需自行编译。

## 拿到完整包后

- 不需要安装 Python、CUDA Toolkit，不需要命令行或分辨率配置。
- **安装／更新**同时处理首次安装和已有补丁更新；旧文件会保存到管理器显示的备份目录。
- **检查生效状态**显示最近记录的运行是否使用了加速，并标注记录时间。
- **导出诊断**生成文本 ZIP，可附到[安装或游戏问题](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues/new?template=problem.yml)中。

[完整安装说明](install.zh-CN.md) · [性能实测](benchmarks.zh-CN.md) · [技术报告](optimizations.zh-CN.md)
