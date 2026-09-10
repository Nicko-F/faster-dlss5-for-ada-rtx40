# 安装使用

[English](install.md)

这是基于 **[RenoDX DLSS5](https://github.com/RankFTW/rhi-repo)** 的 Ada / RTX 40 加速补丁。
先安装社区 base，确认游戏中的 DLSS5 正常运行。
[社区下载入口](https://github.com/RankFTW/rhi-repo/releases) · [支持 addon 的 ReShade](https://reshade.me/)

## 安装

1. 关闭游戏，解压加速包。
2. 双击 **Start.cmd**，右上角可切换 English / 简体中文。
3. 点击**浏览**，选择游戏目录；也可以直接选择包含 `renodx-dlss5.addon64` 的目录。
4. 点击**安装加速补丁**。
5. 照常从 Steam 或原启动器进入游戏，按原来的方式开启 DLSS5。

安装器会记住所选目录。安装完成后，下载的解压目录可以移动或删除。
无需安装 Python、CUDA Toolkit，无需配置命令行或选择分辨率配置。
分辨率、宽高比和 padding 沿用社区 base 的处理。

## 查看是否生效

打开 **Start.cmd**，点击**检查生效状态**。社区插件旁也会保留一份
`faster-dlss5/Start.cmd`，可随时用于管理补丁。

- **已安装**：进入游戏并开启 DLSS5 即可。
- **等待中**：插件正在加载或核对原生网络调用。
- **加速已生效**：记录的游戏运行已使用优化内核。
- **部分计算走社区路径**：点击**打开诊断目录**查看详情。

启动时先用原生网络调用自动核对契约，成功后启用加速。
状态页会显示记录时间，便于区分上一次运行和刚刚启动的游戏。

## 更新或卸载

关闭游戏，点击**卸载补丁**；需要更新时，再安装新的加速包。
社区 base 会保留。如果你修改或添加了补丁目录中的文件，管理器会将它们
保存到旁边的恢复目录，并显示位置。

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
| 已存在加速补丁 | 先点击**卸载补丁**，再安装新的包。 |
| 加速包文件损坏或缺失 | 重新完整解压加速包。 |
| 已安装，但没有运行记录 | 在游戏中开启社区 DLSS5，正常退出后再检查。 |
| 显示 `ADA_NR_BUNDLE` 环境覆盖 | 如果要使用刚安装的包，请删除以前实验留下的该环境设置。 |
| 部分调用走社区路径 | 在 [Issues](https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues) 附上诊断日志、显卡及 base 版本。 |

脚本安装方式：

```powershell
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\YourGame'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\YourGame'
```

[包内容](distribution.zh-CN.md) · [技术报告](optimizations.zh-CN.md)
