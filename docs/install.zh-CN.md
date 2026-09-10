# 安装、启动与卸载

[English](install.md) · [中文主页](../README.zh-CN.md)

**源码预览没有加速内核。** 安装工具可以检查社区环境，但缺少 payload 时会明确停止，
不会假装已经加速。以下完整流程用于单独保存的本地测试包，该包尚不具备公开分发依据。

## 使用条件

- Windows / PowerShell 5.1；压缩包完整解压到可写目录。
- 当前验证范围：RTX 4080、驱动 616.56、《赛博朋克 2077》2.31。
- 已有可正常运行的社区环境：ReShade 6.8.0 addon support、RenoDX DLSS5 4.70、
  本次测试所用的社区 NR 310.8.0；工具会逐项检查文件哈希。
- 插件所需的 Microsoft Visual C++ x64 运行库。
- 原生 1920×1080、2560×1440 或 3840×2160，SDR；游戏内社区 NR 开启，
  使用测试时的 RenoDX style/preset 0、intensity 1。

工具不下载第三方运行库、不降级驱动、不修改全局配置。不要仅按文件名替换来源不明的运行库。

## 完整本地包操作

1. 关闭游戏，完整解压加速包并保留该目录。
2. 双击 `Start.cmd`，选择 **Check compatibility**，输入游戏安装目录。
3. 选择 **Install**，输入游戏目录，选择一个准确分辨率。
4. 选择 **Launch**；游戏内使用对应分辨率与设置。
5. 退出游戏后选择 **Verify latest run**，检查实际替换数量、hook 和错误计数。
6. 恢复社区原版时，关闭游戏并选择 **Remove**。

只向 `bin/x64` 添加我们的 `ada-nr.addon64` 和安装记录。内核与日志保存在解压目录中，
不会覆盖原有社区文件或游戏设置。若已存在未知插件，安装会停止。更换分辨率前先卸载。
菜单中的兼容性检查默认检查 4K payload；完整包同时提供三种分辨率。

请从管理工具启动游戏：它只向该游戏进程传递 `ADA_NR_BUNDLE`，不永久修改环境变量。
直接从 Steam 启动可能无法继承这一设置，不能因此认定优化已启用。

解压目录被移动或删除后，Launch / Status 不能继续使用旧配置；但可以从另一份完整的
本版本管理工具执行 Remove。卸载依据安装记录及锁定的已知插件哈希，不依赖原 payload。
如果有人替换了插件，普通卸载会保留未知文件并停止。明确指定
`-Action Remove -ForgetRecordOnly` 只删除安装记录，**不会删除或卸载那个未知插件**。

## 命令行

```powershell
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\Cyberpunk 2077' -Resolution 2560x1440
.\tools\Manage.ps1 -Action Launch -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\Cyberpunk 2077'
```

Status 只证明观测到的完整计算图按预期选择了路径，不证明画质或纯 GPU 耗时。
无历史帧时保留原 Pre/Post、仍替换 145 个 buffer 调用属于预期行为。

`compatibility/profiles.lock.json` 锁定完整 profile manifest 和插件身份，管理工具还检查
确切文件清单。这用于检测相对本版本的文件变动；与下载包一起提供的校验值不是独立的发布者
身份认证。应从项目维护者处获得完整包，不信任无关来源提供的替换校验值。
