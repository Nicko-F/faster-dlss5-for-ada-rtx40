# 一次安装，按需选择游戏分辨率

[English](install.md)

先安装社区 base 并确认它可以正常运行。本包是增量加速补丁，不是完整兼容整合包。
补丁不安装或修复底座；检查用于识别已测底座及本补丁可使用的替换条件。

源码预览不含加速内核。Check 可检查社区底座；Install、Launch 需要仍仅供本地使用的完整包。

要求 Windows PowerShell 5.1、可写解压目录，以及已验证的 RTX 4080、616.56 驱动、
Cyberpunk 2077 2.31。保留已正常工作的 ReShade 6.8.0 addon、RenoDX DLSS5 4.70、
社区 NR 310.8.0 及其 Visual C++ 运行依赖。当前实测游戏设置为 SDR、NR 开启、
RenoDX style/preset 0、intensity 1，其他模式仍需验证。

分辨率、分区与 padding 是 base 的既有能力，补丁沿用这些参数。安装时无需选择分辨率，改分辨率也无需重装。
详见[动态尺寸范围与验证](dynamic-dimensions.zh-CN.md)。

1. 关闭游戏。已装 此前固定尺寸草稿 的先选 **Remove**；当前自动尺寸草稿 可识别旧安装记录并移除其插件。
2. 将 当前自动尺寸草稿 完整包解压到可写目录，并保留该目录。
3. 双击 **Start.cmd**，选 **Check compatibility**，输入游戏目录。
4. 选 **Install**，再选 **Launch**。在游戏内正常选择分辨率。
5. 退出游戏后选 **Verify latest run**，核对日志里的实际 NR 尺寸、替换次数和错误计数。
6. 要恢复社区路径，关闭游戏后选 **Remove**。

仅在 `bin/x64` 添加我们的插件和安装记录。内核与日志留在 `profiles/automatic/bundle`。
不替换社区文件、不下载运行库、不修改游戏设置、不持久写入环境变量。
通过管理器启动时，只向子进程传入包目录；普通 Steam 启动不属于已核验的优化启动方式。

```powershell
.\tools\Manage.ps1 -Action Check -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Install -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Launch -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Status -GamePath 'D:\Games\Cyberpunk 2077'
.\tools\Manage.ps1 -Action Remove -GamePath 'D:\Games\Cyberpunk 2077'
```

Status 检查调用路由，不证明画质或耗时。没有时序历史时可以保留两次原生 Pre/Post，
同时替换 145 次内部调用。同次运行可以出现不同尺寸；不完整或失败的路由会被报告。

Launch、Status 需要原解压目录。目录丢失或移动后，另一份完整管理器仍可根据已知插件
身份移除安装，而不依赖旧内核。未知或被修改的插件不会被覆盖或悄悄删除。
`-Action Remove -ForgetRecordOnly` 只清除记录并保留插件文件，不等于卸载该文件。

`compatibility/automatic.lock.json` 固定 当前自动尺寸草稿 身份，旧锁文件仅用于卸载 此前固定尺寸草稿。
校验值用于发现文件变化，不是独立的发行方认证；请从项目所有者取得完整包。
