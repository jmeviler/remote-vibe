# Remote Vibe · 开发与维护

项目简介见 [README](../README.md)；默认键位、权限、手势设置和卸载方法见 [安装与使用说明](../Installer/开始使用.txt)。

以下命令从仓库根目录执行。脚本自身也按所在位置定位根目录，支持通过绝对路径调用。

```sh
zsh Scripts/build-app.sh
open "build/Remote Vibe.app"
```

点击菜单栏「遥控语音 → 打开遥控语音」进入设置，选择当前使用的 Google 或小米 RC003，一次使用一只。两种型号均采用按住 Fn 的微信语音输入流程。配置图随型号切换，两种均可选择图上的按键、选择动作并保存，各自的配置和草稿独立保留。

## 语音组件与打包

仅按键映射无需安装驱动。首次使用遥控器语音时，构建并安装组件：

```sh
zsh Scripts/build-driver.sh
sudo zsh Scripts/install-driver.sh
```

安装会重启系统音频服务；已有同名组件时拒绝覆盖。微信输入设备应选择系统默认输入或 `Chromecast Mic`。卸载组件使用 `sudo zsh Scripts/uninstall-driver.sh`，退出 App 后执行，组件会备份到 `build/disabled/`。

修改完成后先提交源码，再生成分享包，确保包内源码归档对应当前 Git 提交：

```sh
zsh Scripts/build-app.sh
zsh Scripts/build-driver.sh
zsh Scripts/package.sh
```

输出位于 `build/share/`，包含安装包、卸载包、首次使用说明、源码、版本记录及许可证。打包不执行安装。

## 实现

- `KeyMapping.swift`：键位定义、本地配置、分型号 HID 映射、独立配置及组合快捷键。
- `ButtonGesture.swift`：单击、双击与长按状态机，0.3 秒双击间隔、0.55 秒长按阈值。
- `ActionCatalog.swift`：分类动作库、快捷键预设及音量 / 亮度 / 媒体系统按键。
- `KeyMappingView.swift`：AppKit 遥控器布局和配置界面，图形由原生控件绘制。
- `SettingsUI.swift`：暖白与深绿主题、遥控器展示区、动作预览和可伸缩窗口布局。
- `DesktopActions.swift`：按需查询可见窗口、双屏切换与稳定的同屏窗口循环。
- `AppController.swift`：菜单栏、窗口及语音会话协调。
- `RemoteAudioSession.swift`：物理语音键与 Google 普通键开麦的会话、超时、尾音及取消处理。
- `RemoteController.swift`、`RemoteProfile.swift`：单只遥控器的型号选择和切换。
- `BluetoothRemote.swift`、`ATVVProtocol.swift`、`ADPCMDecoder.swift`：蓝牙语音连接与分型号解码，Google 保留原参数。
- `XiaomiVoiceKeyOverride.swift`：只在小米语音就绪时临时屏蔽其原始 F5，退出或切换时恢复。
- `FnKey.swift`、`VirtualMicrophone.swift`：Fn 按键和音频输入。

普通按键直接使用设备级 `UserKeyMapping`，无需后台脚本。单次 Esc、组合快捷键、滚动、桌面动作及设置了双击 / 长按的按键观察该遥控器的 HID 报告，将该键原始动作抑制后执行；其他键仍走系统映射。手势使用可取消的一次性定时器，空闲时没有额外轮询。配置每次保存立即应用，连接恢复检查复用 App 已有定时器。

设置页按单击、双击、长按分别编辑；手势使用条件与 Fn 保持规则见安装与使用说明。运行 `zsh Tests/test-button-gestures.sh` 检查时序、旧配置兼容及两种设置页，不触发真实系统按键。

设置窗口支持调整大小，最小为 900 × 640；高度不足时可纵向滚动。运行 `zsh Tests/preview-design.sh round-3` 生成两种遥控器、连招页、编辑与禁用状态，以及 900 / 1080 / 1280 宽度的本机预览，输出到 `build/design/round-3/`。预览使用真实视图和隔离的示例状态，不连接蓝牙、不写入用户配置、不访问钥匙串。三轮检查记录见 [DESIGN-REVIEW.md](DESIGN-REVIEW.md)。

0.4.0 的分类动作库同时支持打开用户选择的 `.app` 与 HTTP(S) 网页；参数按手势保存。系统快捷键遵循当前 Mac 和目标软件设置，亮度 / 音量 / 媒体控制遵循设备与播放器支持。

窗口清单在串行队列按需读取，辅助功能调用有超时。公开 AX 窗口通过进程和位置与当前可见 CG 窗口唯一匹配，不使用私有窗口 ID 接口或屏幕录制。执行前复核前台窗口、屏幕和映射状态；语音开始、保存配置或断开连接会取消待执行的切换。

构建前一版 App 自动保存在本机 `build/Remote Vibe.previous.*.app`。编译产物与备份不纳入源码发布。

回退到旧版时应同时恢复该版本的配置快照：旧版不认识新增动作类型。可用 `defaults export local.ben.RemoteVibe 路径.plist` 备份偏好，在退出 App 后用 `defaults import local.ben.RemoteVibe 路径.plist` 恢复，再运行对应旧构建。

0.4.1 新增 Google **遥控器语音** 动作，可将普通键设为按下即开麦或长按后开麦，松开结束。Fn 映射的用途不变；小米继续使用原语音键。设置方法见安装与使用说明，验证边界见 [GOOGLE-VOICE-VALIDATION.md](GOOGLE-VOICE-VALIDATION.md)。运行 `zsh Tests/test-remote-voice.sh` 验证语音会话和两种型号的原语音路径。

## 目录与命名调整

源码从原来的单层目录迁入 `Sources/App`、`Bluetooth`、`Audio`、`Input`、`Unlock` 和 `UI`。这些是文件分组，仍共用原来的 Swift 编译流程。测试、资源、驱动、安装素材、脚本及文档各自位于仓库根目录的对应文件夹。

| 原名称 | 当前名称 | 职责 |
| --- | --- | --- |
| `WeChatApp` | `AppController` | App 生命周期、界面及语音协调 |
| `Remote` | `BluetoothRemote` | 蓝牙连接与协议通信 |
| `VoiceRemote` | `RemoteController` | 遥控器选择、切换与事件转发 |
| `BridgeError` | `ATVVError` | ATVV 协议错误 |
| `TextInput` | `ClipboardPaste` | 文本粘贴与剪贴板恢复 |
| `XiaomiVoiceKey` | `XiaomiVoiceKeyOverride` | 小米原语音键的临时 F5 映射覆盖 |
| `StudioTheme.swift` | `SettingsUI.swift` | 设置页样式与布局组件 |
| `KeyBinding` | `ButtonAction` | 按键、文本、网页、应用或语音动作 |
| `MappedButton.all` | `MappedButton.chromecast` | Google 型号的按键表 |
| `WeChatApp.save()` | `AppController.writeStatus()` | 写入运行状态 |
| `Remote.close()` / `VoiceRemote.close()` | `cancelVoice()` | 取消语音会话 |

设置页内部的 `StudioTheme`、`StudioPanel`、`StudioPage`、`StudioScrollView`、`StudioShell` 分别改为 `SettingsTheme`、`SettingsPanel`、`SettingsPage`、`SettingsScrollView`、`SettingsView`。

运行行为与配置格式保持一致：沿用已有偏好键、JSON 字段、钥匙串服务、Bundle ID、设备 UID 和 `Chromecast Mic` 显示名；现有 Google / 小米配置无需迁移。驱动随包保留源码、构建脚本和许可证，源码归档仍使用当前 Git 提交。
