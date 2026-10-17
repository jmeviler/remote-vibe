Remote Vibe 0.4.9 · 简体中文 / English · Apple Silicon / Intel · macOS 15+

- 优化安装器升级体验：完整安装包（PKG）支持直接覆盖升级，自动退出运行中的旧版并将已有组件备份至 `/Users/Shared/RemoteVibe-Uninstalled/`，无需手动先运行卸载包。
- 修复蓝牙连接定时器：在菜单保持展开时继续处理连接超时，避免遥控器重连延迟（#14）。
- 继续提供独立的 Apple Silicon 与 Intel 安装包与更新包，支持 macOS 15+。

**下载选择**

| Mac 芯片 | 首次安装或升级：App + 语音组件 | 已有对应语音组件：仅更新 App |
| --- | --- | --- |
| Apple Silicon（M1 / M2 / M3 / M4 等 M 系列） | `Remote-Vibe-0.4.9-Mac-AppleSilicon.zip` | `Remote-Vibe-0.4.9-App-AppleSilicon.zip` |
| Intel | `Remote-Vibe-0.4.9-Mac-Intel.zip` | `Remote-Vibe-0.4.9-App-Intel.zip` |

在“关于本机”查看芯片。两种架构均要求 macOS 15 或更新。更新前退出 App、备份旧 App，再替换原位置；App 更新包不会重启音频服务。完整包附对应源码、使用说明和卸载包。

`SHA256SUMS.txt` 包含全部四个 ZIP 的校验值。下载全部附件时运行 `shasum -a 256 -c SHA256SUMS.txt`；只下载一个包时可运行 `shasum -a 256 <文件名>`，与校验文件中该文件的值比较。

两种架构均通过云端原生编译、隔离测试、构建和打包检查。Intel 的真实蓝牙遥控器、系统驱动加载与微信出字尚未实测，当前作为新增试用包提供。此版本未改动音频处理逻辑。App 与驱动为临时签名，尚未经过 Apple 公证；语音识别依赖微信全局 Fn 语音输入。

---

Remote Vibe 0.4.9 · Simplified Chinese / English · Apple Silicon / Intel · macOS 15+

- Seamless installer upgrades: the full PKG installer now supports direct in-place upgrades by automatically closing running instances and safely backing up existing components to `/Users/Shared/RemoteVibe-Uninstalled/`, eliminating manual uninstall steps.
- Bluetooth timers: keep connection deadlines running while menus are open, avoiding reconnect delays (#14).
- Continues providing separate Apple Silicon and Intel native archives for macOS 15+.

Choose **Mac-AppleSilicon.zip** or **Mac-Intel.zip** for first setup or complete upgrades, and the matching **App-AppleSilicon.zip** or **App-Intel.zip** for an App-only update. Both require macOS 15+. The combined **SHA256SUMS.txt** covers all four archives.
