# Remote Vibe · macOS

使用方法、默认键位、权限、构建和卸载说明见 [项目 README](../README.md)。

```sh
zsh build.sh
open "build/Remote Vibe.app"
```

点击菜单栏「遥控语音 → 打开遥控语音」进入设置。选择图上的按键、选择动作，然后保存。语音按钮固定为按住 Fn 的微信语音输入流程。

## 实现

- `KeyMapping.swift`：键位定义、本地配置、原生 HID 映射及组合快捷键。
- `KeyMappingView.swift`：AppKit 遥控器布局和配置界面，图形由原生控件绘制。
- `DesktopActions.swift`：按需查询可见窗口、双屏切换与稳定的同屏窗口循环。
- `WeChatApp.swift`：菜单栏、窗口及语音会话协调。
- `Remote.swift`、`ATVVProtocol.swift`、`ADPCMDecoder.swift`：蓝牙语音连接和解码。
- `FnKey.swift`、`VirtualMicrophone.swift`：Fn 按键和音频输入。

普通按键直接使用设备级 `UserKeyMapping`，无需后台脚本。单次 Esc、组合快捷键、滚动及桌面动作观察该遥控器的 HID 报告，将该键原始动作抑制后执行；其他键仍走系统映射。配置每次保存立即应用，连接恢复检查复用 App 已有定时器。

窗口清单在串行队列按需读取，辅助功能调用有超时。公开 AX 窗口通过进程和位置与当前可见 CG 窗口唯一匹配，不使用私有窗口 ID 接口或屏幕录制。执行前复核前台窗口、屏幕和映射状态；语音开始、保存配置或断开连接会取消待执行的切换。

构建前一版 App 自动保存在本机 `build/Remote Vibe.previous.*.app`。编译产物与备份不纳入源码发布。

回退到旧版时应同时恢复该版本的配置快照：旧版不认识新增动作类型。可用 `defaults export local.ben.RemoteVibe 路径.plist` 备份偏好，在退出 App 后用 `defaults import local.ben.RemoteVibe 路径.plist` 恢复，再运行对应旧构建。
