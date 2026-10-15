# Remote Vibe · 开发与维护

项目简介见 [README](../README.md)；默认键位、权限、手势设置和卸载方法见 [安装与使用说明](../Installer/开始使用.txt)。

编译、测试程序构建和打包统一在 GitHub Actions 云端 Mac 执行，流程见 [发布与更新](RELEASING.md)。本机用于源码编辑、静态检查、下载校验，以及按需安装预览。以下构建命令是云端 runner 使用的命令，从仓库根目录执行。`Scripts/build-target.sh` 从 `REMOTE_VIBE_ARCH` 或 runner 本机架构选择 `arm64` / `x86_64`；CI 明确设置并验证架构。

```sh
zsh Scripts/build-app.sh
```

从 Actions 产物或 Release 下载 App 后，在本机安装预览。点击菜单栏图标 →「打开遥控语音」进入设置，选择当前使用的 Google 或小米 RC003，一次使用一只。两种型号均采用按住 Fn 的微信语音输入流程。配置图随型号切换，两种均可选择图上的按键、选择动作并保存，各自的配置和草稿独立保留。

## 语音组件与打包

仅按键映射无需安装驱动。首次使用遥控器语音时，下载 Release 完整安装包并按说明安装；云端构建组件的命令为：

```sh
zsh Scripts/build-driver.sh
```

安装会重启系统音频服务；已有同名组件时拒绝覆盖。微信输入设备应选择系统默认输入或 `Chromecast Mic`。卸载组件使用 `sudo zsh Scripts/uninstall-driver.sh`，退出 App 后执行，组件会备份到 `build/disabled/`。

修改完成后先提交源码，由 GitHub Actions 生成分享包，确保包内源码归档对应当前 Git 提交。云端执行：

```sh
zsh Scripts/build-app.sh
zsh Scripts/build-driver.sh
zsh Scripts/package.sh
```

输出位于 runner 的 `build/share/`，并按架构上传为 `Remote-Vibe-AppleSilicon` / `Remote-Vibe-Intel` Actions 产物，再汇总为 `Remote-Vibe-Release`，包含完整安装 ZIP、独立 App 更新 ZIP 和校验文件。打包不执行安装。发布步骤见 [发布与更新](RELEASING.md)。

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
- `BluetoothTimers.swift`：蓝牙扫描、初始化和重连的一次性计时；在菜单跟踪模式中继续运行，替换、取消及销毁时清理旧回调。
- `XiaomiVoiceKeyOverride.swift`：只在小米语音就绪时临时屏蔽其原始 F5，退出或切换时恢复。
- `FnKey.swift`、`VirtualMicrophone.swift`：Fn 按键和音频输入。

普通按键直接使用设备级 `UserKeyMapping`，无需后台脚本。单次 Esc、组合快捷键、滚动、桌面动作及设置了双击 / 长按的按键观察该遥控器的 HID 报告，将该键原始动作抑制后执行；其他键仍走系统映射。手势使用可取消的一次性定时器，空闲时没有额外轮询。配置每次保存立即应用，连接恢复检查复用 App 已有定时器。

设置页按单击、双击、长按分别编辑；手势使用条件与 Fn 保持规则见安装与使用说明。运行 `zsh Tests/test-button-gestures.sh` 检查时序、旧配置兼容及两种设置页，不触发真实系统按键。

设置窗口支持调整大小，最小为 900 × 640；高度不足时可纵向滚动。如需截图预览，在云端 macOS job 运行 `zsh Tests/preview-design.sh round-3`，生成两种遥控器、连招页、编辑与禁用状态，以及 900 / 1080 / 1280 宽度的预览；将 `build/design/round-3/` 上传为产物后下载查看。预览使用真实视图和隔离的示例状态，不连接蓝牙、不写入用户配置、不访问钥匙串。三轮历史检查记录见 [DESIGN-REVIEW.md](DESIGN-REVIEW.md)。

0.4.0 的分类动作库同时支持打开用户选择的 `.app` 与 HTTP(S) 网页；参数按手势保存。系统快捷键遵循当前 Mac 和目标软件设置，亮度 / 音量 / 媒体控制遵循设备与播放器支持。

窗口清单在串行队列按需读取，辅助功能调用有超时。公开 AX 窗口通过进程和位置与当前可见 CG 窗口唯一匹配，不使用私有窗口 ID 接口或屏幕录制。执行前复核前台窗口、屏幕和映射状态；语音开始、保存配置或断开连接会取消待执行的切换。

构建脚本会将工作目录内的前一版 App 保存在 `build/Remote Vibe.previous.*.app`；GitHub runner 通常从干净检出开始。本机安装云端 App 前另行备份旧 App。编译产物与备份不纳入源码发布。

回退到旧版时应同时恢复该版本的配置快照：旧版不认识新增动作类型。可用 `defaults export local.ben.RemoteVibe 路径.plist` 备份偏好，在退出 App 后用 `defaults import local.ben.RemoteVibe 路径.plist` 恢复，再运行对应旧构建。

0.4.1 新增 Google **遥控器麦克风** 动作，可将普通键设为按下即开麦或长按后开麦，松开结束。Fn 映射的用途不变；小米继续使用原语音键。设置方法见安装与使用说明，验证边界见 [GOOGLE-VOICE-VALIDATION.md](GOOGLE-VOICE-VALIDATION.md)。运行 `zsh Tests/test-remote-voice.sh` 验证语音会话和两种型号的原语音路径。

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

## 语音恢复与配置维护（2026-10-15）

`VirtualMicrophone` 通过可注入的 `MicrophoneHardware` / `MicrophoneWriter` 访问 CoreAudio。监听设备清单与音频服务重启；服务重启会重建监听器和写入句柄，即使设备 ID 未变化。开麦启动失败只重建并重试一次。正在录音时设备失效会取消会话、释放 Fn，重连后等待用户重新按键，不自动重放音频。默认输入暂为 0 时保留恢复标记，原输入返回后按 UID 恢复；用户另选输入时保留其选择。

`VoiceSessionSchedule` 将准备、缓冲排空与收尾定时器注册到 `.common`，菜单展开时仍执行，取消会话同时撤销所有未执行的步骤。排空超时使用单调时间。0.2 / 0.55 秒启动等待和 0.2 / 0.8 秒收尾等待保持原值；本次没有声称降低微信识别延迟。

`status.json` 新增 `voiceTiming`、`audioBuffer` 和 `drainTimedOut`。时间单位为毫秒，起点是 App 收到 ATVV 音频开始事件；里程碑为虚拟麦克风启动、首批样本、Fn 按下、开始送音、音频停止、排空完成、Fn 松开与清理完成。`audioStopped` 是协议停止事件，不等于物理松键；`drainStarted` 是允许送音，不是微信开始识别的确认。峰值缓存与溢出丢帧数以 48 kHz 输出帧计。诊断不记录音频、识别文字或按键内容，也不增加空闲轮询。

`MappingStore` 逐键读取既有 JSON。损坏键位优先使用有效备份，无备份时禁用；其他可读键位保留。整份 JSON 损坏时恢复有效备份，无备份时禁用该模式的所有可配置按键并显示提示。读取不写偏好；保存前将有效旧数据存到原偏好键 + `.backup.v1`，损坏旧数据存到 `.recovery.v1`。每种型号与模式各自保存最近一份备份 / 损坏原文，后续正常保存不删除损坏原文。

菜单栏「键位配置」提供导入草稿、导出已保存配置、载入有效备份。JSON 文件包含版本、型号及两套键位；校验型号、版本、动作和 1 MB 大小上限，失败不改变草稿。导入 / 恢复不自动保存或应用，不包含钥匙串中的连招解锁数据。

`zsh Tests/test-audio-pipeline.sh` 使用假设备验证句柄重建、重试上限、监听器重建、输入恢复、缓冲排空 / 溢出、菜单模式收尾及取消，并运行 `driver_test.c`。`test-button-gestures.sh` 还验证配置恢复 / 备份 / 导入导出与中英文导入草稿。全部纳入 CI。测试不重启系统音频、不切换真实输入、不连接遥控器或向系统发按键；真实蓝牙与微信出字仍需实机验证。

## 0.4.3：语言、终端操作与更新

UI 和状态文字通过 `Sources/App/Localization.swift` 读取原生 `.strings`；协议标识、偏好键、动作类型与设备名保持不变。`Tests/test-button-gestures.sh` 在中文和英文资源下运行同一组 UI 检查。预览英文：`zsh Tests/preview-design.sh english en`。

`ReleaseUpdate.swift` 仅解析正式发布版本和可下载 App 包，网络请求仍由菜单按钮触发。`zsh Tests/test-app-support.sh` 验证语言资源和版本比较。

Codex CLI 使用已有键盘事件路径，新增数字键和 Ctrl+C/G/O/R 预设。方向、Enter、Esc、Tab、Shift+Tab 和自定义组合键已在动作库；不自动覆盖用户键位。具体用途依赖当前终端界面与 Codex 版本，可在 Codex 的 `/keymap` 查看或修改其绑定。官方参考：[交互快捷键](https://learn.chatgpt.com/docs/developer-commands?surface=cli#interactive-shortcuts)。

## 0.4.4：墨绿色按钮与快捷键入口

按钮、遥控器选中键与动作预览统一采用墨绿色。按钮标题单独绘制，以保证禁用与窗口失焦时的可读性，交互仍由原生控件处理，详见 [视觉检查](DESIGN-REVIEW.md)。

「终端 / Codex CLI」分类增加 `Shift + ←` 入口，发送与「滚动与光标 → 向左选择 · ⇧←」相同的 Shift + Left 组合键。具体用途由当前终端界面决定，不修改已有配置或输入事件路径。

## 0.4.5：独立鼠标模式

在普通键位的单击、双击或长按中选择「切换鼠标模式」，在鼠标键位页独立配置四方向移动和左右点击。切换键的普通配置在鼠标模式中优先，以保证同一按键可退出。切换动作支持单击、双击或长按，沿用既有手势阈值；切换键的整套手势在鼠标模式中保留。同一键有多个手势时先完成识别，切换仍等待全部松键。动作菜单首项提供模式切换入口。其他鼠标键可以使用既有动作库；持续移动与 Fn 一样只支持即时保持或长按保持。

普通配置继续使用原 `mappingKey`；鼠标配置另存为 `mappingKey + ".mouse"`。运行模式不持久化。模式切换等待所有原始按键释放后才更新设备级 `UserKeyMapping`，保持按下 / 松开两阶段使用同一套原生映射。映射所有权仍按既有快照复核；切换模式不夺回其他工具修改的映射。进入语音取消移动和待触发手势；保存、锁屏、休眠、设备断开、权限丢失或型号切换退出鼠标模式。菜单栏提供独立退出入口。

`MousePointer.swift` 使用一个仅在方向键按住期间存在的 60 Hz 定时器，根据单调时间加速并限制迟到回调的移动距离。组合方向归一化，相反方向抵消；指针按 Quartz 显示器坐标限制在可用屏幕上。左右点击先构造完整按下 / 抬起事件，再成对投递，连续左击按系统双击间隔处理。没有增加空闲轮询、驱动或后台服务。

`zsh Tests/test-button-gestures.sh` 同时运行鼠标状态、独立配置、事件构造、双击时序、移动加速、斜向移动、多屏边界和停止回归；注入时钟、屏幕与事件接收器，不向系统投递鼠标事件。中英文 UI 检查覆盖页签草稿、切换键保留、默认点击、重置及窄窗口宽度。自动验证不能确认真实蓝牙报告、目标应用点击行为或移动手感；实机操作仍需确认。
