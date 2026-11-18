---
name: vm-skill
description: "Use when writing or reviewing a C# host for Hikrobotics VisionMaster (VM) joint programming (联合编程 / 二次开发). Covers the VM SDK: load a .sol solution, run VmProcedure, set ModuParams, read ModuResult, and embed render or parameter controls in WinForms or WPF. Trigger on VisionMaster, VM, VM SDK, VmSolution, C# host. Look up module parameters, defaults, ranges, and error codes in the local VM manuals."
license: MIT
compatibility: "Requires a local Windows VisionMaster install with application help and the SDK development components. This skill does not include those manuals."
metadata:
  author: SnowManTangchao
  version: "1.0.0"
---

# VisionMaster 联合编程

指导编码代理编写、修改和审查 **C# 宿主程序**：用海康机器人 VisionMaster（VM）SDK 加载 `.sol` 方案、运行流程、设置输入、读取模块结果，并在 WinForms 或 WPF 里嵌入 VM 渲染控件和参数控件。

官方手册留在用户本机的 VM 安装目录里。模块参数名、默认值、取值范围、枚举、错误码和确切重载，都到本机帮助或已引用的程序集里核对。云端环境没有 VisionMaster。没有本机运行记录时，交付说明里写明代码尚未在 VM 上运行。

## 先选择工作类型

先读 [四种开发模式](references/development-modes.md)，再只打开当前任务需要的参考。

| 用户要做的事 | 路线 | 接着读 |
|---|---|---|
| 在 VM 图形界面里搭方案、调模块、看结果 | VM 图形界面 | 本机应用帮助。不要写 SDK 宿主 |
| 用 C# 宿主加载 `.sol`、跑流程、嵌控件 | **联合编程（本技能主线）** | 下面的工作流，以及对象模型、工程配置、常见任务 |
| 不加载方案，直接调海康算子库并自建全部界面 | 算子 SDK | 本机手册里的算子 SDK 章节。不要套用 `VmSolution` 流程 |
| 把自研算法做成 VM 里可拖拽的模块 | 算法模块（C++） | 本机手册里的模块开发章节 |

联合编程是主线。任务属于其他路线时，先说明该走哪一条，再只做用户明确要求的部分。

## 动手前定位本机文档

在用户的 Windows 电脑上运行 [scripts/find-vm-install.ps1](scripts/find-vm-install.ps1)。怎么读它的输出、帮助文件和 CHM 各查什么，见 [本机安装与文档](references/local-docs.md)。

下面这些内容以本机资料为准，不要凭记忆补全：

- 某个模块的参数名、默认值、取值范围、枚举
- 结果字段的类型、数组形态和过程输出名称
- 错误码含义
- 当前版本是否存在某个重载、事件或控件

可以在 IDE 里对已引用的程序集使用转到定义。需要引用手册句子时，只摘当前问题用到的短句，并注明本机文件路径。不要把 CHM、PDF、WebHelp 解包或复制进本仓库，也不要复制进用户的业务仓库。

## 联合编程工作流

1. 确认路线是 SDK 联合编程，并确认界面是 WinForms 还是 WPF。
2. 定位安装根目录、应用帮助、SDK 开发指南 CHM，以及 Development 里的程序集。
3. 检查现有 `.csproj` 的目标框架、平台和引用。缺引用时按 [C# 工程配置](references/csharp-project-setup.md) 处理。
4. 核对方案里的真实名称：流程名、模块名、图像入口、要读的结果名。索引字符串必须与 `.sol` 里的名称完全一致。方案不在工作区时，向用户要这些名称，不要自己编。
5. 按 [对象模型](references/object-model.md) 组织调用：加载方案，取出流程或模块，设置只对下一次运行有效的输入，运行，然后重新取得结果。只有用户要求保存方案时才写入 `.sol`。
6. 绑定渲染控件、读取结果、把回调封送回 UI 线程。步骤见 [常见任务](references/common-tasks.md)。
7. 交付时列出仍要在本机手册或本机运行中确认的签名、参数和错误码。

## 对象模型规则

这些规则在公开的 VM SDK 资料里反复出现。落地前仍用当前安装版本的 SDK 指南核对。

- 入口单例是 `VmSolution.Instance`。
- 流程内对象用 `VmSolution.Instance["流程名.模块名"]` 取得。全局模块通常只用模块名，不带流程前缀。
- 模块侧常见的三个入口是 `ModuParams`、`ModuResult` 和 `Run()`。
- `SetImageData`、`SetInputXxx` 这类输入接口通常只对下一次执行有效。每次运行前按需要重新设置。
- `ModuResult` 通常在每次运行之后重新获取。不要一直拿着运行前的结果对象。
- 改参数不会自动写回 `.sol`。保存方案是单独的调用。

## 编写约束

- 沿用用户工程已有的 UI 框架、命名和项目风格。
- 程序集从本机 Development 目录引用。用安装目录里的 `ImportRef.exe`，或按本机指南手动添加。不要把海康 DLL、示例方案或许可证提交进本技能仓库。
- 宿主目标框架使用 .NET Framework 4.6.1 或本机指南写明的更高 Framework 版本。不要把工程改成 .NET Core 或 .NET 5 及以上，除非该版本的 SDK 指南写明支持。
- 平台使用 64 位。AnyCPU 时不要勾选「首选 32 位」。需要写死时用 x64，并在本机文档里确认。
- 程序退出前释放方案和控件。不要在终结器里调用 SDK。
- 回调在 SDK 工作线程上触发。更新 WinForms 控件走 `Invoke` 或 `BeginInvoke`，更新 WPF 走 `Dispatcher`。
- 调试请求只改用户点名的代码。不要自行打开相机、通信或运动控制。
- 客户的 `.sol`、图像、加密狗信息和许可证留在用户机器上。

## 交付

给出能放进用户工程的 C# 改动。写明方案路径、流程名、模块名这些假设从哪里来。列出必须在本机帮助或一次真实运行里确认的点。没有本机运行证据时，写明尚未在 VisionMaster 上运行。
