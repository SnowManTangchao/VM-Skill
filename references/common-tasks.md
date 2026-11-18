# 常见任务

下面的代码是调用形态，不是某一版 SDK 的完整示例。带 `VERIFY` 的类型名、枚举和方法，先在本机 CHM 或已引用程序集里确认，再写进用户工程。方案名、流程名、模块名用 `.sol` 里的真实字符串。

公共约定：输入类接口通常只对下一次执行有效；`ModuResult` 在每次运行后重新获取；回调里更新界面要封送回 UI 线程。

## 加载方案

```csharp
using VM.Core;
using VM.PlatformSDKCS;

// VERIFY: Load 的参数。公开资料要求绝对路径，有的版本第二参是密码。
VmSolution.Load(solutionPath);

VmProcedure procedure = VmSolution.Instance[procedureName] as VmProcedure;
if (procedure == null)
{
    throw new InvalidOperationException(
        "Procedure not found. The name must match the .sol file: " + procedureName);
}
```

加载前确认 VisionMaster 界面没有打开同一个文件。退出路径上释放方案，放在窗体 `FormClosing` 或等价的关闭逻辑里，不要放在终结器里。

```csharp
// VERIFY: 本机类型上的释放方法。公开资料里常见 Dispose，有的版本还要先关闭方案。
VmSolution.Instance.Dispose();
```

用户要求保存时再调用本机指南里的保存方法。参数编辑控件里的修改同样不会自动落盘。

## 运行流程

一次运行用流程或方案上的同步执行方法。在转到定义里确认名字；公开资料里流程对象常用 `Run()`，方案对象另有同步运行整个方案的方法。

```csharp
procedure.Run();
var result = procedure.ModuResult;
```

只跑一个模块时调用该模块的 `Run()`。模块上游的图像和 ROI 需要已经就绪，否则这次自执行没有输入。

连续运行是另一种模式。启动前在本机类型上确认间隔和停止成员，停止之后再 `Dispose`。

## 设置图像输入

图像从宿主进来时，方案里的图像源模块要处于 SDK 输入方式。枚举和属性名在图像源模块的参数类型上确认。

```csharp
// VERIFY: 图像源 Tool 的命名空间和程序集。
// VERIFY: 选择 SDK 输入的枚举成员。
// VERIFY: SetImageData / SetImagePath，以及图像对象的类型（公开资料里常见 ImageBaseData）。
var source = VmSolution.Instance[procedureName + "." + imageSourceName] as ImageSourceModuleTool;
if (source == null)
{
    throw new InvalidOperationException("Image source module not found.");
}

source.ModuParams.ImageSourceType = ImageSourceTypeEnum.SDK;
source.SetImageData(imageData);

procedure.Run();
```

`SetImageData` 和 `SetImagePath` 通常只喂给下一次执行。循环采图时，每一拍都重新设置，然后再 `Run()`。

像素格式、行对齐，以及和 `Bitmap`、OpenCV、HALCON 图像之间谁是 RGB、谁是 BGR，以本机图像转换说明为准。不要假设通道顺序。本技能不附带转换代码。

给流程或 Group 设输入图像时，用该对象参数上的输入方法，输入名称用方案里配置的名称。不要把图像源模块的 API 套到流程对象上。

## 读取结果

模块结果：运行结束后重新取 `ModuResult`，只访问这个结果类型里存在的属性。

```csharp
var tool = VmSolution.Instance[procedureName + "." + moduleName] as TargetModuleTool;
if (tool == null)
{
    throw new InvalidOperationException("Module not found.");
}

tool.Run();
var moduleResult = tool.ModuResult;
// 从 moduleResult 的实际属性读取。不要借用其他模块的字段名。
```

流程结果：在 VM 里把需要的量配置成流程输出，再用流程结果对象按那个输出名读取。字符串、整数、浮点和图像的取法不同，方法名以 `VmProcedure` 的结果类型为准。输出名是方案里配置的名字，不是模块内部字段名。

读不到新数据时按这个顺序查：

1. 这次运行前，只生效一次的输入有没有重新设置。
2. `ModuResult` 是不是运行完成之后重新取的。
3. 是否关掉了全部回调，却没有对这个流程或模块重新打开结果回调。
4. 输出名是否与方案里的配置一致。
5. 异常里的错误码到本机状态码章节去查。

## 绑定渲染控件和参数控件

先加载方案，再绑定。渲染控件绑流程，参数控件绑要编辑的模块。

```csharp
// VERIFY: 控件类型来自 WinForms 或 WPF 那一套程序集，不要混用。
renderControl.ModuleSource = procedure;
paramsControl.ModuleSource = moduleTool;
```

控件刷新是异步的。不要在 `Run()` 返回后立刻让渲染控件存图。要稳定图像时，读模块或流程的图像输出。

参数控件改的是已加载方案里的参数。需要写回 `.sol` 时，再显式保存。

## 回调里更新界面

工作结束回调在 SDK 线程上执行。WinForms 用 `BeginInvoke`。判断窗口句柄是否还在，避免关闭过程中封送。

```csharp
procedure.OnWorkEndStatusCallBack += (sender, args) =>
{
    if (IsDisposed || !IsHandleCreated)
    {
        return;
    }

    BeginInvoke(new Action(() =>
    {
        var result = procedure.ModuResult;
        // 在这里更新界面。
    }));
};
```

`OnWorkEndStatusCallBack` 是公开资料里常见的流程结束事件名。如果当前程序集里的事件名字不同，用转到定义看到的那个。

WPF 同样不要在回调线程碰控件：

```csharp
Application.Current.Dispatcher.BeginInvoke(new Action(() =>
{
    var result = procedure.ModuResult;
}));
```

回调里做完读取就可以返回。不要在回调里 `Invoke` 一条又会等待这个回调的同步调用，否则会卡住。高频流程优先 `BeginInvoke`，并丢掉窗口已经关闭时的更新。

## 最小宿主顺序

1. 配置 64 位 .NET Framework 工程和引用。
2. `Load` 绝对路径。
3. 按真实名称取出流程和模块，空则停止。
4. 需要外部图像时，设置 SDK 输入。
5. 运行。
6. 重新取得 `ModuResult` 或流程输出。
7. 需要画面时绑定 `ModuleSource`；回调里封送 UI。
8. 关闭时释放方案和控件。
