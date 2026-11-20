Remote Vibe 0.5.0 · 简体中文 / English · Apple Silicon / Intel · macOS 15+

- 自定义语音输入与快速连续说话：菜单栏新增“语音输入设置”，默认保持长按 Fn（微信），可选按住右 Option、点按 `⌥Space` 切换、仅送音频不发按键（免辅助功能权限）或自定义快捷键；支持“不切换系统默认麦克风”模式与快速连续说话缓冲时序。
- 无锁音频缓冲与音质升级：虚拟麦克风改用单生产者单消费者无锁环形缓冲、因果三次 Hermite 平滑上采样与 `tanhf` 软限幅，减少锁争用断音与贴麦大音量削波；新增已安装驱动构建号校验提示（HAL 驱动本身仍为 0.1.0 / 构建号 1，已有对应架构驱动的用户可直接仅更新 App）。
- 蓝牙兼容与日常体验：Google 型号支持系统蓝牙改名后的遥控器与新版 Google TV 遥控器（基于 `0x180A` 身份特征校验排除误连设备）；新增菜单栏“登录时打开”开关、后台合并原子写入 `status.json`，并修复重复快捷键预设回显跳组。
- 继续提供独立的 Apple Silicon 与 Intel 安装包与更新包，支持 macOS 15+。

**下载选择**

| Mac 芯片 | 首次安装或升级：App + 语音组件 | 已有对应语音组件：仅更新 App |
| --- | --- | --- |
| Apple Silicon（M1 / M2 / M3 / M4 等 M 系列） | `Remote-Vibe-0.5.0-Mac-AppleSilicon.zip` | `Remote-Vibe-0.5.0-App-AppleSilicon.zip` |
| Intel | `Remote-Vibe-0.5.0-Mac-Intel.zip` | `Remote-Vibe-0.5.0-App-Intel.zip` |

在“关于本机”查看芯片。两种架构均要求 macOS 15 或更新。更新前退出 App、备份旧 App，再替换原位置；App 更新包不会重启音频服务。完整包附对应源码、使用说明和卸载包。

`SHA256SUMS.txt` 包含全部四个 ZIP 的校验值。下载全部附件时运行 `shasum -a 256 -c SHA256SUMS.txt`；只下载一个包时可运行 `shasum -a 256 <文件名>`，与校验文件中该文件的值比较。

两种架构均通过云端原生编译、隔离测试、构建和打包检查。Intel 的真实蓝牙遥控器、系统驱动加载与微信出字尚未实测，当前作为新增试用包提供。App 与驱动为临时签名，尚未经过 Apple 公证；默认触发依赖微信全局 Fn 语音输入，也可切换至其他语音输入工具的触发快捷键。

---

Remote Vibe 0.5.0 · Simplified Chinese / English · Apple Silicon / Intel · macOS 15+

- Configurable voice triggers and faster turnaround: added Voice Input Settings in the menu bar with built-in presets (Hold Fn for WeChat, Hold Right Option, Tap `⌥Space` toggle, Audio-only without Accessibility permission, or custom hold/tap shortcuts), optional fixed-input mode without switching the system default microphone, and faster consecutive speech buffering.
- Lock-free audio buffering and smoother resampling: replaced lock-based virtual microphone buffering with a lock-free SPSC ring buffer, causal cubic Hermite upsampling, and `tanhf` soft limiting, plus installed HAL driver build checks (the HAL driver remains 0.1.0 / build 1, so App-only updates apply if already installed).
- Expanded Bluetooth matching and daily UX: Google profile now matches renamed ATVV remotes and newer Google TV remotes via `0x180A` device identity checks, adds native Launch at Login (`SMAppService`), offloads `status.json` writes to a coalesced background queue, and preserves canonical vs alias shortcut selection in settings.
- Continues providing separate Apple Silicon and Intel native archives for macOS 15+.

Choose **Mac-AppleSilicon.zip** or **Mac-Intel.zip** for first setup or complete upgrades, and the matching **App-AppleSilicon.zip** or **App-Intel.zip** for an App-only update. Both require macOS 15+. The combined **SHA256SUMS.txt** covers all four archives.
