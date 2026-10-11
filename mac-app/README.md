# Remote Vibe · macOS

使用方法、默认键位、权限、构建和卸载说明见 [项目 README](../README.md)。

```sh
zsh build.sh
open "build/Remote Vibe.app"
```

点击菜单栏「遥控语音 → 打开遥控语音」进入设置，选择当前使用的 Google 或小米 RC003，一次使用一只。两种型号均采用按住 Fn 的微信语音输入流程。配置图随型号切换，两种均可选择图上的按键、选择动作并保存，各自的配置和草稿独立保留。

## 实现

- `KeyMapping.swift`：键位定义、本地配置、分型号 HID 映射、独立配置及组合快捷键。
- `ButtonGesture.swift`：单击、双击与长按状态机，0.3 秒双击间隔、0.55 秒长按阈值。
- `ActionCatalog.swift`：分类动作库、快捷键预设及音量 / 亮度 / 媒体系统按键。
- `KeyMappingView.swift`：AppKit 遥控器布局和配置界面，图形由原生控件绘制。
- `DesktopActions.swift`：按需查询可见窗口、双屏切换与稳定的同屏窗口循环。
- `WeChatApp.swift`：菜单栏、窗口及语音会话协调。
- `VoiceRemote.swift`、`RemoteProfile.swift`：单只遥控器的型号选择和切换。
- `Remote.swift`、`ATVVProtocol.swift`、`ADPCMDecoder.swift`：蓝牙语音连接与分型号解码，Google 保留原参数。
- `XiaomiVoiceKey.swift`：只在小米语音就绪时临时屏蔽其原始 F5，退出或切换时恢复。
- `FnKey.swift`、`VirtualMicrophone.swift`：Fn 按键和音频输入。

普通按键直接使用设备级 `UserKeyMapping`，无需后台脚本。单次 Esc、组合快捷键、滚动、桌面动作及设置了双击 / 长按的按键观察该遥控器的 HID 报告，将该键原始动作抑制后执行；其他键仍走系统映射。手势使用可取消的一次性定时器，空闲时没有额外轮询。配置每次保存立即应用，连接恢复检查复用 App 已有定时器。

设置页按单击、双击、长按分别编辑；手势使用条件与 Fn 保持规则见主 README。运行 `zsh Tests/test-button-gestures.sh` 检查时序、旧配置兼容及两种设置页，不触发真实系统按键。

0.4.0 的分类动作库同时支持打开用户选择的 `.app` 与 HTTP(S) 网页；参数按手势保存。系统快捷键遵循当前 Mac 和目标软件设置，亮度 / 音量 / 媒体控制遵循设备与播放器支持。

窗口清单在串行队列按需读取，辅助功能调用有超时。公开 AX 窗口通过进程和位置与当前可见 CG 窗口唯一匹配，不使用私有窗口 ID 接口或屏幕录制。执行前复核前台窗口、屏幕和映射状态；语音开始、保存配置或断开连接会取消待执行的切换。

构建前一版 App 自动保存在本机 `build/Remote Vibe.previous.*.app`。编译产物与备份不纳入源码发布。

回退到旧版时应同时恢复该版本的配置快照：旧版不认识新增动作类型。可用 `defaults export local.ben.RemoteVibe 路径.plist` 备份偏好，在退出 App 后用 `defaults import local.ben.RemoteVibe 路径.plist` 恢复，再运行对应旧构建。
