# 2026-09-13 Godot退出崩溃定位

结论：直接故障已定位到本机Duet WinTab 1.1.4.4的进程退出清理路径。普通Python进程仅加载该DLL即可复现，不需要Godot、Voxel Tools或测试场景。
具体Duet内部实现缺陷尚无私有符号或源码可查；不把定位到DLL等同于知道其内部哪行代码写错。

## 最小化结果
| 进程/配置 | 结果 |
|---|---|
| 无插件临时工程，headless导入 | exit 0 |
| 无插件临时工程，headless运行2秒后退出 | exit 0 |
| 同一工程，仅Camera+BoxMesh+Light，OpenGL | 0xC0000005 |
| 同一工程，D3D12 | 0xC0000005 |
| 同一工程，Vulkan | 0xC0000005 |
| 同一工程，--tablet-driver winink（两次） | 0xC0000005 |
| 同一工程，dummy/wintab | 到达QUIT后未在25秒内结束，执行器终止；不记为自然退出或已确认相同异常码 |
| Python仅打印并退出 | exit 0 |
| Python仅ctypes.WinDLL加载系统wintab32.dll并退出 | 0xC0000005 |

因此跳过“逐步加入插件/地形”的后续步骤：无插件已经复现，独立DLL加载进一步缩小了范围。

## 调用栈
使用本机已安装WinDbg附带的x64 CDB，启动临时工程并在首次访问冲突处暂停；系统符号来自微软符号服务器。没有修改系统调试注册表或安装工具。

```text
ExceptionCode: c0000005
ExceptionAddress: ntdll!RtlEnterCriticalSection+0xd
Parameter[0]: 1 (write)
Parameter[1]: 0x30

ntdll!RtlEnterCriticalSection+0xd
wintab32!Ordinal999+0x226b
wintab32!Ordinal999+0x101d
wintab32!WTMgrCsrPressureBtnMarksEx+0x794
ntdll!LdrpCallInitRoutine+0x61
ntdll!LdrShutdownProcess+0x22a
ntdll!RtlExitUserProcess+0xad
KERNEL32!ExitProcessImplementation+0xb
msvcrt!_crtExitProcess+0x15
```

WinTab没有私有调试符号，以上是导出符号加偏移，不把它们当成准确的内部函数名称。
地址0x30属于近空地址；栈显示DLL在进程卸载时调用临界区入口并触发写访问冲突。

## DLL身份
- 路径：C:/Windows/System32/wintab32.dll
- CompanyName：Duet, Inc.
- ProductName / FileDescription：Duet WinTab
- FileVersion：1.1.4.4
- OriginalFilename：WinDuet.dll
- PE时间戳：2022-05-17
- Authenticode：Valid，签名主体Duet, Inc.
- SHA256见tmp/exit-probe/dll_identity.json。

## 为什么换输入后端也没解决
Godot 4.7该构建在Windows DisplayServer构造阶段直接LoadLibraryW("wintab32.dll")，以探测WinTab功能。选择winink或dummy不会阻止这一步DLL加载，因此不是有效规避措施。
源码：https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/platform/windows/display_server_windows.cpp#L7179
此前找到的WinRT修复#121633目前没有与本次WinTab调用栈对应的证据，不据此认定升级Godot即可解决。

## 证据与后续
- tmp/exit-probe/results.json：无插件最小工程各后端退出码。
- tmp/exit-probe/tablet_results.json：输入后端隔离；其中exit=1的dummy/wintab属于超时终止。
- tmp/exit-probe/dll_isolation.json：Python空进程对照及仅加载DLL复现。
- tmp/exit-probe/capture_final.log：异常参数、寄存器、调用栈和DLL信息。
- tmp/exit-probe/exit.dmp：已成功保存的本地小型崩溃转储。
- tmp/exit-probe/project.godot、probe.gd、probe.tscn：无插件最小工程。

下一步应通过Duet官方安装器修复/更新其WinTab组件；若不再使用Duet，可考虑卸载。修复后先重复最小退出和体素smoke，再恢复正式基准。
本次仅完成定位，没有卸载Duet、替换/删除系统DLL、停止服务、修改注册表或主项目设置，没有重跑正式性能矩阵。

## 卸载并重启后复核（2026-09-13 18:51）
用户手动卸载Duet并重启后，System32和SysWOW64下的wintab32.dll均不存在；标准HKLM/HKCU卸载项未查到Duet。
同一最小工程的OpenGL、D3D12、Vulkan三种图形后端均exit 0，无脚本错误。原始日志：tmp/exit-probe/post-uninstall-20260913-185054/。
同一体素基准的D3D12短负载也正常完成并exit 0：128块放置/挖掘、数据与碰撞确认通过，没有0xC0000005。套件用时20.4秒，日志：tmp/voxel-bench-results/suite-20260913-185108/。
本轮复核说明此前可重复的Duet WinTab退出崩溃已消除；没有修改系统设置或切换引擎。只做短负载复核，正式性能矩阵仍未执行。
