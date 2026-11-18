# 本机安装与文档

VM 的算子说明、参数默认值、取值范围和错误码以**这台电脑上的安装**为准。版本和盘符都会变。先定位文件，再打开对应的那一本，不要假设路径固定，也不要把手册复制进仓库。

## 先跑定位脚本

在装有 VisionMaster 的 Windows 电脑上，于本技能目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1
```

需要机器可读的结果时加上 `-Json`。安装不在常见位置时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1 -ExtraRoot "D:\VisionMaster4.4.0"
```

脚本只查找文件。它不启动 VisionMaster，也不检查许可证。

脚本会查看：

- 环境变量 `VM_SDK_DIR`（可以指向安装根目录，也可以指向里面的 Development 或程序集目录）
- 卸载注册表里显示名包含 VisionMaster 的安装位置
- 各固定磁盘根目录，以及 `Program Files`、`Program Files (x86)` 下名为 `VisionMaster*` 的目录

自定义目录如果不在上述位置，用 `-ExtraRoot` 或 `VM_SDK_DIR` 指出来。同一台机器可能装有多个版本。用与用户工程匹配的那一个，不要混用不同版本的 DLL 和帮助。

## 常见路径

下列路径是常见布局，安装程序允许改盘符和根目录。`4.x.x` 代表实际版本号。

| 用途 | 常见位置 |
|---|---|
| 安装根目录 | `C:\Program Files\VisionMaster4.x.x\`，或自定义根目录如 `D:\VisionMaster4.4.0\` |
| 应用帮助 | `<InstallRoot>\Applications\Help\CH\index.html` |
| SDK 开发指南 | Development 相关目录下的 CHM。文件名随版本变化，以脚本列出的 `.chm` 为准 |
| 引用导入工具 | `<InstallRoot>\Development\V4.x\ComControls\Tool\ImportRef.exe` |
| 托管程序集 | 同一 Development 树里的 `VM.Core.dll`、`VM.PlatformSDKCS.dll`，以及 `VMControls.Winform.Release.dll` 或 `VMControls.WPF.Release.dll` |

`V4.x` 有的安装就是这个文件夹名，有的版本会换成具体目录。两种都让脚本去找，不要只拼一条路径。

## 该打开哪一份

| 问题 | 打开 |
|---|---|
| 界面上怎么搭方案、模块参数是什么意思、默认值和范围 | 应用帮助 `Applications\Help\CH\index.html`，搜模块在界面上的名称 |
| 类、方法、事件、控件属性的签名 | SDK 开发指南 CHM，或 IDE 里对已引用程序集转到定义 |
| 错误码 | SDK 指南里的状态码章节，用完整错误码字符串搜索 |
| 工程引用、平台和示例程序怎么配 | SDK 指南的环境配置 / 编程引导，并对照安装目录里的官方示例工程 |

CHM 可能有多份。优先打开标题或路径里带 SDK、开发指南字样的那一份，打开后再看封面版本是否与安装版本一致。应用帮助回答「这个模块做什么、参数怎么理解」；CHM 和程序集回答「代码里叫什么」。两处不一致时，以**当前引用的那套程序集**能否编译通过为准，并在交付说明里记下差异。

## 代理可以怎么读

- HTML 帮助可以直接打开本机上的 `index.html` 和它链接到的页面，读当前问题相关的那几节。
- 签名优先用 IDE 查看已引用的 DLL。这不需要把手册拷出来。
- 引用手册时只保留回答当前问题所需的短句，并写上本机文件路径和版本。

不要把帮助目录、CHM 解包结果、PDF 或大段参数表复制到本技能仓库或用户的业务仓库。不要把官方示例整棵复制进业务项目；只借鉴用户点名的那一种用法，引用装在本机的示例路径即可。
