# C# 工程配置

联合编程的宿主是 Windows 上的 .NET Framework 工程。下面是公开资料和工程实践里反复出现的约束。每一条都用本机 SDK 指南再确认一次，尤其是用户安装的版本与这里的默认假设不一致时。

## 目标框架

使用 **.NET Framework 4.6.1** 或本机指南允许的更高 Framework 版本。VM SDK 通常不支持 .NET Core、.NET 5 及以后的运行时。不要把现有 Framework 工程改成 `net6.0`、`net8.0` 这类目标。

新建项目时选「Windows 窗体应用 (.NET Framework)」或「WPF 应用 (.NET Framework)」，不要选标题里只有「Windows 窗体应用」的跨平台模板。

旧式 csproj 里对应：

```xml
<TargetFrameworkVersion>v4.6.1</TargetFrameworkVersion>
```

用户工程已经是 4.7.2 或 4.8 时，保持原样，不要降级。只有本机指南写明某个 Framework 版本不可用时才调整。

## 平台

原生依赖是 64 位。下面两种写法都要避开 32 位进程：

- 平台目标设为 **x64**
- 若必须用 AnyCPU，取消「首选 32 位」

旧式 csproj：

```xml
<PlatformTarget>x64</PlatformTarget>
<Prefer32Bit>false</Prefer32Bit>
```

32 位进程加载这些原生库时会在运行期失败。设计器也要跑在 64 位 Visual Studio 里，否则工具箱里的 VM 控件可能加不进来。

## 引用哪些程序集

以本机 Development 目录里真实存在的文件为准。

| 宿主需要 | 通常要引用 |
|---|---|
| 只调用方案和流程 | `VM.Core.dll`、`VM.PlatformSDKCS.dll` |
| WinForms 控件 | 上面两个，加上 `VMControls.Winform.Release.dll` 及其依赖 |
| WPF 控件 | 上面两个，加上 `VMControls.WPF.Release.dll` 及其依赖 |
| 某个算法模块的强类型 Tool | 该模块自己的程序集，例如图像源、Blob、识别模块各自的 DLL |

控件库通常还依赖 `VMControls.Interface.dll`、`VMControls.BaseInterface.dll`、`VMControls.RenderInterface.dll`。有导入工具时用它带上依赖；没有时按下一节把磁盘上存在的那些 DLL 手动加进来。WinForms 和 WPF 的控件库不要同时加进一个只使用其中一种界面的工程。

命名空间以程序集为准。方案和流程的公开类型常见于 `VM.Core` 与 `VM.PlatformSDKCS`。具体模块的 Tool 类型在该模块程序集自己的命名空间里。

## 添加程序集引用

以定位脚本打印的路径为准。不要自己拼一条固定的 `ImportRef.exe` 或 DLL 路径。

### 脚本列出了 ImportRef.exe

`import-ref` 不是 `(none)` 时，用它打印的那一个文件。有的版本在 `Development\V4.x\ComControls\Tool\ImportRef.exe`，有的放在别的目录，有的安装里没有这个文件。

1. 确认路径属于当前要用的这一套安装，而不是另一边的旧版本。
2. 启动该 `ImportRef.exe`，选择包含 `.csproj` 的工程目录。
3. 导入基础库，再只导入方案里真正用到的模块。
4. 回到 Visual Studio 重新加载项目。
5. 检查引用里有 `VM.Core` 和 `VM.PlatformSDKCS`，以及选中的模块和控件库。

一个工程不要对两个 VM 版本各导一次。升级 VM 后，用新版本的导入工具重新导入，并清理输出目录里残留的旧 DLL。

### 没有 ImportRef.exe

`import-ref` 为 `(none)` 时，这一版没有该工具。按脚本 `assemblies` 里打印的完整路径，在 Visual Studio 里用「添加引用 → 浏览」手动加。开发组件可以是齐全的，只是没带导入工具。

| 宿主需要 | 手动添加 |
|---|---|
| 只调用方案和流程 | 脚本列出的 `VM.Core.dll`、`VM.PlatformSDKCS.dll` |
| WinForms 控件 | 再加上 `VMControls.Winform.Release.dll`，以及脚本列出的 `VMControls.Interface.dll` |
| WPF 控件 | 再加上 `VMControls.WPF.Release.dll`，以及脚本列出的 `VMControls.Interface.dll` |

控件库若还依赖同目录下的 `VMControls.BaseInterface.dll`、`VMControls.RenderInterface.dll`，而脚本没单独列出，到已列出的控件 DLL 所在目录查看，把磁盘上真实存在的依赖一并引用。

旧式 csproj 用脚本打印的完整路径作为 `HintPath`，并关掉复制本地：

```xml
<Reference Include="VM.Core">
  <HintPath>脚本打印的 VM.Core.dll 完整路径</HintPath>
  <Private>False</Private>
</Reference>
```

路径里有空格时，原样放进 `HintPath`。不要把这些 DLL 复制进业务仓库。

## 复制本地

手动添加引用后，把这些 VM 程序集的「复制本地 / Copy Local」设为 **False**（csproj 里的 `Private` 为 `False`）。这样生成目录不会再放进一份可能过期的副本，进程使用与本机安装配套的那一套。导入工具如果已经这么设置，就不要改回去。

运行的电脑上需要安装匹配版本的 VisionMaster，并且进程要能找到这些程序集和原生依赖。做法跟本机官方示例：环境变量、工作目录，或示例里的探测路径。不要把整棵 VM 安装目录复制进业务仓库。若本机指南要求把某几个原生文件放到 exe 旁边，只复制指南点名的那些文件。

## log4net.config

有的版本会到可执行文件旁的固定相对路径查找 log4net 配置。公开资料里，缺文件时有的只是警告，有的会在初始化时失败。配置文件的内容从定位脚本 `log4net-config` 打印的那一份读取。不要假设它一定在：

```text
<InstallRoot>\Development\V4.x\ComControls\Assembly\3rdLib\Log4Net\log4net.config
```

有的安装把这份文件放在 Development 树的更深处，磁盘上的文件名也可能是 `log4Net.config`。脚本按文件名查找，不区分大小写，并打印真实路径。

输出目录旁的相对路径跟本机官方示例工程。不要把脚本找到的深层目录原样当成运行时相对路径，也不要在示例并不是 `3rdLib\Log4Net\` 时仍写死这条路径。在示例工程里搜索 `log4net.config`，用它的 `Content Include` 和 `Link`。

只有示例也使用 `3rdLib\Log4Net\log4net.config` 时，才用下面这段：

```xml
<Content Include="3rdLib\Log4Net\log4net.config">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  <Link>3rdLib\Log4Net\log4net.config</Link>
</Content>
```

列出多个配置文件时，用示例工程实际复制的那一份。脚本显示 `(none)` 时，仍然以示例工程为准。示例里也没有，就不要自己编一份替代配置。配置可以按示例放进用户的业务工程，不要把它再发布到本技能仓库。

## 工具箱

WinForms：工具箱「选择项」里浏览 `VMControls.Winform.Release.dll`。WPF：引用 `VMControls.WPF.Release.dll`，在 XAML 里映射该程序集的命名空间。控件加不进工具箱时，先核对平台是 x64、引用来自当前安装、设计器没有停在 32 位。

## 生成后检查

- 进程是 64 位。
- 输出目录里没有混入另一版本的 `VM.Core.dll`。
- `log4net` 配置的相对路径和本机示例一致。
- 启动失败时，先看本机安装是否带了开发组件，再用安装目录里的环境检测工具。工具的文件名以本机 `Applications\Tools` 为准，不要假设每一版都叫同一个名字。
