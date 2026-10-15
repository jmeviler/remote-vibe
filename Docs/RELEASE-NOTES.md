Remote Vibe 0.4.8 · 简体中文 / English · Apple Silicon / Intel · macOS 15+

- 新增 Intel Mac 下载包；Apple Silicon 与 Intel 分别编译、测试和打包，每个包包含对应架构的 App 和语音驱动。
- 全部构建由 GitHub Actions 的 Apple Silicon / Intel 云端 Mac 完成；两种架构都通过后才汇总发布附件。
- 安装器检查实际芯片，拒绝不匹配的安装包，包括在 Apple Silicon 上通过 Rosetta 打开 Intel 安装器的情况。
- 手动检查更新按当前 App 架构匹配下载包；保留 Apple Silicon 原文件名，兼容旧版更新检测。
- 发布前检查下载校验值、App / 驱动架构与签名、安装器约束、图标资源和对应源码。

**下载选择**

| Mac 芯片 | 首次安装：App + 语音组件 | 已有对应语音组件：仅更新 App |
| --- | --- | --- |
| Apple Silicon（M1 / M2 / M3 / M4 等 M 系列） | `Remote-Vibe-0.4.8-Mac-AppleSilicon.zip` | `Remote-Vibe-0.4.8-App-AppleSilicon.zip` |
| Intel | `Remote-Vibe-0.4.8-Mac-Intel.zip` | `Remote-Vibe-0.4.8-App-Intel.zip` |

在“关于本机”查看芯片。两种架构均要求 macOS 15 或更新。更新前退出 App、备份旧 App，再替换原位置；App 更新包不会重启音频服务。完整包附对应源码、使用说明和卸载包。

`SHA256SUMS.txt` 包含全部四个 ZIP 的校验值。下载全部附件时运行 `shasum -a 256 -c SHA256SUMS.txt`；只下载一个包时可运行 `shasum -a 256 <文件名>`，与校验文件中该文件的值比较。

两种架构均通过云端原生编译、隔离测试、构建和打包检查。Intel 的真实蓝牙遥控器、系统驱动加载与微信出字尚未实测，当前作为新增试用包提供。此版本未改动音频处理逻辑。App 与驱动为临时签名，尚未经过 Apple 公证；语音识别依赖微信全局 Fn 语音输入。

---

This release adds separate Intel Mac downloads alongside Apple Silicon. Each archive contains the matching native App and audio driver. GitHub Actions builds and tests each architecture on its own macOS runner; release assets are assembled only after both pass.

The installer rejects the wrong physical CPU, including an Intel installer opened through Rosetta on Apple silicon. Manual update checks match the current App architecture, while existing AppleSilicon asset names remain compatible with older clients.

Choose **Mac-AppleSilicon.zip** or **Mac-Intel.zip** for first setup, and the matching **App-AppleSilicon.zip** or **App-Intel.zip** for an App-only update after quitting and backing up the old App. Both require macOS 15+. The combined **SHA256SUMS.txt** covers all four archives.

Native cloud builds, isolated tests and package checks passed for both architectures. Intel Bluetooth remotes, system driver loading and WeChat transcription still require physical-device validation; Intel is offered as a new trial package. Audio processing is unchanged. The App and driver are ad hoc signed, not Apple-notarized. Voice recognition requires WeChat global hold-Fn input.
