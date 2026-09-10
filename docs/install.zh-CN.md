# 安装使用

[English](install.md)

这是基于 **[RenoDX DLSS5](https://github.com/RankFTW/rhi-repo)** 的 Ada / RTX 40 加速补丁。
先安装社区 base，确认游戏中的 DLSS5 正常运行。
[社区下载入口](https://github.com/RankFTW/rhi-repo/releases) · [支持 addon 的 ReShade](https://reshade.me/)

先查看[下载指南](downloads.zh-CN.md)，确认拿到的是完整加速包。

## 安装

1. 关闭游戏，解压加速包。
2. 双击 **Start.cmd**，右上角可切换 English / 简体中文。
3. 点击**浏览**，选择游戏目录；也可以直接选择包含 `renodx-dlss5.addon64` 的目录。
4. 点击**安装／更新**，首次安装和更新使用同一个按钮。
5. 照常从 Steam 或原启动器进入游戏，按原来的方式开启 DLSS5。

安装器会记住所选目录。安装完成后，下载的解压目录可以移动或删除。
无需安装 Python、CUDA Toolkit，无需配置命令行或选择分辨率配置。
分辨率、宽高比和 padding 沿用社区 base 的处理。

## 查看是否生效

打开 **Start.cmd**，点击**检查生效状态**。社区插件旁也会保留一份
`faster-dlss5/Start.cmd`，可随时用于管理补丁。

- **已安装**：进入游戏并开启 DLSS5 即可。
- **等待中**：最近记录显示插件已加载，正在等待 DLSS5 画面或核对原生调用。
- **加速已生效**：记录的游戏运行已使用优化内核。
- **部分计算走社区路径**：点击**导出诊断**，通过**反馈问题**附上诊断包。

启动时先用原生网络调用自动核对契约，成功后启用加速。
状态页会显示记录时间，便于区分上一次运行和刚刚启动的游戏。

## 更新或卸载

更新时关闭游戏，打开新完整包的 **Start.cmd**，选择原目录并点击**安装／更新**。
安装器先准备并校验新文件，再替换旧安装；文件替换失败时恢复旧安装。
旧插件、内核包和附加文件保存在显示的 `faster-dlss5-backup-…` 目录中，确认新安装正常后可自行删除该备份。

卸载时关闭游戏，点击**卸载补丁**。社区 base 会保留。
你修改或添加的补丁目录文件会保存到旁边的恢复目录，管理器会显示位置。

## 导出诊断与反馈

1. 选择游戏目录，点击**导出诊断**，选择一个新的 ZIP 文件名保存。
2. 查看 ZIP 中的文本内容，然后点击**反馈问题**，填写游戏、显卡、操作与现象并附上 ZIP。
3. 不需要跑 benchmark；愿意分享帧率时，可另选 **Performance results / 性能分享** 模板。

诊断包包含安装标识、系统与显卡信息、状态摘要和最近最多 2,000 行事件／帧记录，自动隐去绝对本地路径。
安装器不自动上传文件。导出失败时，直接复制提示或展开的**详细信息**反馈即可。

## 安装位置

```text
社区插件目录/
  renodx-dlss5.addon64         社区 base
  nvngx_dlssnr.dll            社区 NR 运行库
  ada-nr.addon64              加速插件
  faster-dlss5-install.json   安装记录
  faster-dlss5/               管理工具与加速内核包
    Start.cmd
    tools/
    profiles/automatic/
```

安装器通过社区插件文件定位目录，不限定游戏名。
运行时通过接口和实际网络调用契约判断适配性；更新游戏、驱动或社区插件，
不会触发整文件哈希白名单。测试配置和性能数据见[性能报告](benchmarks.zh-CN.md)。

## 遇到问题时

| 提示或现象 | 处理方法 |
|---|---|
| 找不到社区插件 | 选择包含 `renodx-dlss5.addon64` 的目录；尚未安装 base 时，使用上方社区链接。 |
| 已存在加速补丁 | 直接点击**安装／更新**。 |
| 安装按钮不可用，显示源码工具 | 打开[下载指南](downloads.zh-CN.md)核对包类型；安装需要完整加速包。 |
| 加速包文件损坏或缺失 | 重新完整解压加速包。 |
| 已安装，但没有运行记录 | 在游戏中开启社区 DLSS5，正常退出后再检查。 |
| 显示 `ADA_NR_BUNDLE` 环境覆盖 | 如果要使用刚安装的包，请删除以前实验留下的该环境设置。 |
| 部分调用走社区路径 | 点击**导出诊断**，通过**反馈问题**提交。 |
| 文件夹无法写入 | 查看该文件夹的写入权限；导出时可另选桌面等可写位置。 |

脚本安装方式：

```powershell
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\YourGame'
```

[包内容](distribution.zh-CN.md) · [技术报告](optimizations.zh-CN.md)
