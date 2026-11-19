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
- 卸载注册表里显示名包含 VisionMaster 的项。会读取 `InstallLocation`、`InstallPath`，以及 `DisplayIcon` 指向的程序所在目录。有的安装 `InstallLocation` 是空的，但 `InstallPath` 或 `DisplayIcon` 仍指向安装目录
- 各固定磁盘根目录，以及 `Program Files`、`Program Files (x86)` 下名为 `VisionMaster*` 的目录

自定义目录如果不在上述位置，用 `-ExtraRoot` 或 `VM_SDK_DIR` 指出来。同一台机器可能装有多个版本。用与用户工程匹配的那一个，不要混用不同版本的 DLL 和帮助。

## 常见路径

下列路径是常见布局，安装程序允许改盘符和根目录。`4.x.x` 代表实际版本号。不同版本的帮助和工具不在同一条路径上，以定位脚本打印的结果为准。

| 用途 | 怎么找 |
|---|---|
| 安装根目录 | 脚本打印的安装目录。常见位置如 `C:\Program Files\VisionMaster4.x.x\`，也可能是 `E:\Program Files\VisionMaster4.2.0\` 这类自定义路径 |
| 应用帮助（WebHelp） | 脚本 `app-help` / `html`。常见文件是 `<InstallRoot>\Applications\Help\CH\index.html`，英文为 `EN\index.html` |
| 应用帮助（CHM） | 脚本 `app-help` / `chm`。有的版本（包括 4.2.x）没有 `index.html`，帮助在 `<InstallRoot>\Applications\Help\CH\` 和 `EN\` 的 `.chm` 里 |
| SDK 开发指南 | 脚本 `sdk-chm`。在 Development 或 Documentation 下，文件名随版本变化 |
| 引用导入工具 | 脚本 `import-ref`。有的版本在 `Development\V4.x\ComControls\Tool\ImportRef.exe`，有的版本整个安装里都没有这个文件 |
| 托管程序集 | 脚本 `assemblies`。同一 Development 树里的 `VM.Core.dll`、`VM.PlatformSDKCS.dll`，以及 `VMControls.Winform.Release.dll` 或 `VMControls.WPF.Release.dll` |
| log4net 配置 | 脚本 `log4net-config`。有的版本在 `Assembly\3rdLib\Log4Net\log4net.config`，有的在更深层目录，文件名大小写以磁盘为准 |

`V4.x` 有的安装就是这个文件夹名，有的版本会换成具体目录。两种都让脚本去找，不要只拼一条路径。

## 该打开哪一份

模块参数、默认值、取值范围和枚举以**应用帮助**为准。类、方法、事件和错误码以 **SDK 开发指南**或已引用程序集为准。

| 问题 | 打开 |
|---|---|
| 界面上怎么搭方案、模块参数是什么意思、默认值和范围 | 应用帮助。见下面的 HTML / CHM 规则，搜模块在界面上的名称 |
| 类、方法、事件、控件属性的签名 | 脚本 `sdk-chm` 里的 SDK 开发指南，或 IDE 里对已引用程序集转到定义 |
| 错误码 | SDK 指南里的状态码章节，用完整错误码字符串搜索 |
| 工程引用、平台和示例程序怎么配 | SDK 指南的环境配置 / 编程引导，并对照安装目录里的官方示例工程。`ImportRef.exe` 缺失时按 [C# 工程配置](csharp-project-setup.md) 手动添加引用 |

### 应用帮助是 HTML 还是 CHM

看定位脚本这一项安装的 `app-help`：

| 脚本结果 | 含义 | 打开哪一个 |
|---|---|---|
| `html` 下列出了 `index.html` | 这一版是 WebHelp | 优先 `Applications\Help\CH\index.html`。界面是英文时用 `EN\index.html`。用浏览器打开，顺着链接读当前模块那几节 |
| `html` 是 `(none)`，`chm` 列出了 `.chm` | 应用帮助已安装，这一版做成了 CHM。4.2.x 就是这种布局 | 按 `chm` 的打印顺序打开。先打开与界面语言相符的 `VisionMasterHelp.chm`（中文在 `Help\CH`，英文在 `Help\EN`）。这份里没有该模块时，再打开同一语言目录下的 `HIKVisionMasterHelp.chm` |
| `html` 和 `chm` 都有 | 两种帮助都在 | 参数查询优先用 `index.html`。CHM 是同一套应用帮助的补充 |
| 两边都是 `(none)` | 帮助确实不在这套安装里 | 这时才需要安装或修复帮助组件 |

`Applications\Help` 下的 CHM 是应用帮助，用来查模块参数。`sdk-chm` 是开发指南，用来查代码签名和错误码。脚本不会把应用帮助 CHM 算进 `sdk-chm`。

列表里如果还有别的应用帮助文件名，仍按打印顺序查，并优先语言目录与界面一致的那一份。没有 `index.html` 只说明这一版不是 WebHelp。

SDK 开发指南可能有多份 CHM。优先打开标题或路径里带 SDK、开发指南字样的那一份，打开后再看封面版本是否与安装版本一致。两处资料不一致时，以**当前引用的那套程序集**能否编译通过为准，并在交付说明里记下差异。

## 代理可以怎么读

- HTML 帮助可以直接打开本机上的 `index.html` 和它链接到的页面，读当前问题相关的那几节。
- CHM 用下面的临时检索。只在系统临时目录解包，结束即删。
- 签名优先用 IDE 查看已引用的 DLL。这不需要把手册拷出来。
- 引用手册时只保留回答当前问题所需的短句，并写上本机文件路径和版本。

不要把帮助目录、CHM 解包结果、PDF 或大段参数表复制到本技能仓库或用户的业务仓库。不要把官方示例整棵复制进业务项目；只借鉴用户点名的那一种用法，引用装在本机的示例路径即可。

### 临时检索 CHM

在装有 VisionMaster 的 Windows 电脑上，于本技能目录执行。`-Chm` 用定位脚本打印的完整路径，`-Query` 用模块在界面上的名称、参数名，或完整错误码：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\lookup-chm.ps1 -Chm "<app-help chm 的完整路径>" -Query "模块在界面上的名称"
```

脚本会：

1. 确认解包目录在系统临时目录下，并且不在本技能仓库或任何 Git 工作区里。否则直接拒绝，不写文件。
2. 用 Windows 自带的 `hh.exe` 把这一份 CHM 解到临时目录里一次性的 `vm-help-lookup-*` 文件夹。
3. 在解出的 HTML 里查找 `-Query`，向标准输出打印少量短摘录。不传 `-Query` 时只列出页面相对路径，不打印正文。
4. 结束时删除该临时目录，失败时也删。

摘录只留在当次对话里，并注明原来的 CHM 路径。不要把解包目录挪进仓库。

解包失败时，用本机帮助查看器打开同一份 CHM，在查看器里搜索：

```powershell
hh.exe "<app-help chm 的完整路径>"
```

SDK 开发指南如果也是 CHM，把 `-Chm` 换成 `sdk-chm` 里的路径。查错误码时 `-Query` 用完整错误码字符串。
