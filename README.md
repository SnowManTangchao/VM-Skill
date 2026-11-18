# VM-Skill

海康机器人 **VisionMaster（VM）联合编程** 的 [Agent Skill](https://agentskills.io)。给 Claude Code、Codex、Cursor，以及其他支持 Agent Skills 的编码代理使用。

技能教代理怎么写一个 C# 宿主：用 VM SDK 加载 `.sol` 方案、运行流程、设置输入、读取模块结果，并在 WinForms 或 WPF 里嵌入渲染控件和参数控件。算子参数、默认值、取值范围和错误码不在这个仓库里，它们留在你电脑上已经安装的 VM 帮助中。

## 这是什么

- 一份安装在代理侧的工作说明：`SKILL.md` 负责选择路线，`references/` 写联合编程的对象模型和工程注意点
- 一个只读定位脚本：在 Windows 上找出本机 VM 的应用帮助、SDK CHM 和 Development 程序集
- 联合编程（VM SDK + C# 宿主）是主线。图形界面、算子 SDK、C++ 自定义模块只做路线区分

## 这不是什么

- 不是 VisionMaster 官方手册，也不附带 CHM、PDF、WebHelp 的副本或摘录
- 不是可运行的工业 HMI 示例工程
- 不包含模块参数全表、状态码全表或 API 签名大全
- 不能代替本机安装。没有装 VM、没有开发组件和帮助时，代理无法核对参数和错误码

代理应打开本机帮助核对细节，而不是凭记忆编造签名。本仓库的作者没有在云端环境里运行 VisionMaster。

## 前提

- Windows 上已安装 VisionMaster，并且安装了**应用帮助**和 **SDK 开发组件**
- 要编译宿主时：Visual Studio，工程目标为 .NET Framework 4.6.1 或安装文档要求的更高 Framework 版本，平台为 64 位
- 编码代理支持 [Agent Skills](https://agentskills.io)

常见文档位置（版本号和盘符以本机为准）：

| 用途 | 常见路径 |
|---|---|
| 安装根目录 | `C:\Program Files\VisionMaster4.x.x\`，或例如 `D:\VisionMaster4.4.0\` |
| 应用帮助 | `<安装根>\Applications\Help\CH\index.html` |
| 引用导入工具 | `<安装根>\Development\V4.x\ComControls\Tool\ImportRef.exe` |
| 核心程序集 | `VM.Core.dll`、`VM.PlatformSDKCS.dll`，以及 WinForms / WPF 控件库 |

也可以设置环境变量 `VM_SDK_DIR` 指向安装根目录或其中的 Development 目录。定位脚本会读它。

## 安装

### 用 npx skills（推荐）

在需要使用该技能的项目目录中执行：

```bash
npx skills add SnowManTangchao/VM-Skill
```

安装到当前用户、对所有项目生效：

```bash
npx skills add SnowManTangchao/VM-Skill --global
```

只装给指定代理：

```bash
npx skills add SnowManTangchao/VM-Skill --agent claude-code --agent codex --agent cursor
```

更新：

```bash
npx skills update SnowManTangchao/VM-Skill
```

`npx skills` 会读取仓库根目录的 `SKILL.md`。技能名是 `vm-skill`。

### 手动复制

把本仓库中的 `SKILL.md`、`references/` 和 `scripts/` 放进一个名为 **`vm-skill`** 的文件夹。目录名需要和 `SKILL.md` 里的 `name` 一致。

用户级目录：

| 代理 | 路径 |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills\vm-skill\` |
| Codex | `%USERPROFILE%\.agents\skills\vm-skill\` |
| Codex 旧目录（仍会被扫描） | `%USERPROFILE%\.codex\skills\vm-skill\` |
| Cursor | `%USERPROFILE%\.cursor\skills\vm-skill\` |

项目级目录：

| 代理 | 路径 |
|---|---|
| Claude Code | `.claude\skills\vm-skill\` |
| Codex | `.agents\skills\vm-skill\` |
| Cursor | `.cursor\skills\vm-skill\` |

手动复制不会进入 `npx skills update`。能用 npx 时优先用 npx。装完后重开代理会话；Claude Code 里也可以执行 `/reload-skills`。

## 让代理找到本机手册

在装有 VisionMaster 的 Windows 电脑上：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1
```

脚本打印应用帮助、CHM 和程序集的候选路径。加上 `-Json` 可得到一段 JSON。安装不在默认位置时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1 -ExtraRoot "D:\VisionMaster4.4.0"
```

找不到任何安装时，脚本以退出码 1 结束，并说明搜过哪里。它不启动 VM，也不检查加密狗或许可证。

## 仓库内容

```text
VM-Skill/
├── SKILL.md                 # 路线选择、联合编程工作流、编写约束
├── references/
│   ├── local-docs.md        # 如何定位并查阅本机帮助
│   ├── development-modes.md # 四种开发模式，主线是联合编程
│   ├── object-model.md      # 方案、流程、模块和控件
│   ├── csharp-project-setup.md
│   └── common-tasks.md      # 加载、运行、送图、取结果、绑定控件、回调
├── scripts/
│   └── find-vm-install.ps1
├── LICENSE                  # 本仓库原创文字与脚本的 MIT 许可
└── NOTICE.md                # VisionMaster 官方软件与手册的版权边界
```

## 版权

本仓库原创的技能文字和脚本采用 [MIT 许可证](LICENSE)。

VisionMaster 软件、SDK 和官方手册（含 CHM、PDF、WebHelp）的版权属于杭州海康机器人（Hangzhou Hikrobotics）/ 厂商。这些材料不在 MIT 许可范围内，不要复制进本仓库。说明见 [NOTICE.md](NOTICE.md)。

## English

VM-Skill is an Agent Skill for Hikrobotics VisionMaster joint programming. It tells a coding agent how to write a C# WinForms or WPF host that loads a `.sol` solution, runs procedures, and reads module results. Official manuals stay on the machine where VisionMaster is installed.

```bash
npx skills add SnowManTangchao/VM-Skill
```

The locator script searches common install folders and `VM_SDK_DIR`. It does not start VisionMaster:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1
```
