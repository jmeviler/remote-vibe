# Remote Vibe

把 Chromecast Voice Remote 变成 Mac 上的语音输入与快捷键遥控器。

原生 Swift / AppKit 应用，无 Web 服务、Electron 或第三方运行时。按键映射使用 macOS 原生 HID 接口，配置界面和蓝牙语音在同一个菜单栏 App 中运行。

## 使用

1. 在 macOS 蓝牙设置中配对 **Chromecast Remote**。
2. 启动 Remote Vibe，在设置窗口中点击遥控器上的按键。
3. 选择功能，点击 **保存并生效**。

全部 15 个物理按键都显示在界面中，包括侧边音量键。14 个普通按键可配置；语音键固定为按住说话。

| 按键 | 默认功能 |
| --- | --- |
| 语音 | 按住说话，松开结束 |
| 静音 | Enter 回车 / 发送 |
| 独立返回箭头 | Backspace 退格删除 |
| 中央确认 | Enter 回车 / 确认 |
| 方向盘 | 上、下、左、右 |
| 其他按键 | 保留原按键功能 |

可选动作包括回车、退格、取消、方向键、Tab、空格、上下滚动、禁用和自定义快捷键。自定义支持 Control、Shift、Option、Command 与字母、数字、方向键、F1–F12 等组合。例如为某个按键配置 `Control + Shift + ↑`。

映射作用于当前软件；Enter 是否发送以及快捷键的行为由该软件决定。App 自动保存配置，运行期间在遥控器重连后恢复映射；正常退出时恢复接管前的设备设置。设置窗口可关闭，App 继续在菜单栏运行。

## 语音输入

收音来自**遥控器自带麦克风**。App 通过 ATVV 蓝牙协议接收音频，写入 `Chromecast Mic`，并模拟长按 Fn，交给用户现有的微信全局语音输入功能转成文字。

使用前，需确保微信的长按 Fn 语音输入已能在其他软件中工作：

1. 点击目标软件的文本输入框。
2. 按住遥控器语音键说话，松开等待出字。
3. 用返回键回删，或短按静音键发送。

Remote Vibe 自身不调用云端识别接口、不保存录音或转写；微信语音的数据处理遵循微信自身设置和服务规则。

## 构建

当前构建目标为 **Apple Silicon、macOS 15 或更新版本**。需要 Xcode Command Line Tools（Swift / Clang），音频组件构建还使用 Python 3 标准库写入 plist。

在本仓库根目录运行：

```sh
cd mac-app
zsh build.sh
open "build/Remote Vibe.app"
```

普通按键映射不需要安装驱动。组合快捷键和滚动功能使用系统的**输入监控**与**辅助功能**权限；语音功能还需要蓝牙权限、辅助功能权限，以及下述音频组件。

### 语音组件（仅首次使用语音时）

在 `mac-app` 目录中运行：

```sh
zsh Driver/build-driver.sh
sudo zsh install-driver.sh
```

安装仅添加 `/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver`，遇到已有同名组件会拒绝覆盖，并会重启 CoreAudio。不会安装内核扩展，也不会新增开机启动项。该组件只能作为默认输入设备，不能成为默认扬声器。

微信应使用系统默认输入，或选择 `Chromecast Mic`。App 在语音开始时切换默认输入，结束后尽可能恢复先前仍可用的输入设备。

## 保存与移除

- 配置保存在用户偏好域 `local.ben.RemoteVibe` 的 `keyMappings.v1`，不在项目目录中写配置。
- 运行状态在 `~/Library/Application Support/RemoteVibe/status.json`，仅包含设备和计数信息。
- 点击 **恢复此键默认**，再保存，可撤销某个按键的自定义设置。
- 从菜单栏退出 App，会停止监听并恢复本次接管前的按键设置。
- 卸载音频组件：退出 App 后，在 `mac-app` 中运行 `sudo zsh uninstall-driver.sh`。组件会移动到本机 `build/disabled/`，保留撤销路径。

当前构建使用本地签名，尚未签名公证用于公开二进制分发。应用标识保持不变，以兼容已授权的本机安装。

## 目录

```text
mac-app/
  Sources/                当前 App 源码
  Driver/                 虚拟麦克风源码及上游许可证
  Tests/                  已有的 Fn 与音频组件验证代码
  build.sh                原生 App 构建
  install-driver.sh       安装可选语音组件
  uninstall-driver.sh     移除语音组件
```

`build/`、早期录音、研究记录、本机日志与本机备份均排除在 Git 提交之外。核心 App 无外部包依赖，不需要包管理器。现有验证代码不参与正常构建。

## 已验证与限制

- 同一只 Chromecast Remote 上的遥控器收音、微信出字、静音键发送、返回键删除已通过实际操作验证。
- 配置界面、所有按键的映射表与保存逻辑已接入；未声称所有自定义快捷键在每个软件中都已实测。
- 遥控器 VID / PID 为 `0x18D1 / 0x9450`，其他遥控器型号暂不支持。
- 如果某些按键被遥控器配置为红外控制，它们可能不向 Mac 发送蓝牙事件，此时无法由本 App 映射。

## 许可证与参考

本项目采用 [GPL v3](LICENSE)，随项目提供 BlackHole 衍生音频组件的对应源码。

- [vibe-mote](https://github.com/Tilkmilk/vibe-mote)：遥控器辅助编程的交互参考，未使用其 Windows 注入或驱动代码。
- [vRemoter](https://github.com/VincentKingHsu/vRemoter)：ATVV 协议实现参考及部分代码来源，保留 MIT 许可与原作者声明，见 [THIRD_PARTY_NOTICES](mac-app/THIRD_PARTY_NOTICES.md)。
- [BlackHole](https://github.com/ExistentialAudio/BlackHole)：虚拟麦克风基础代码，GPL v3，修改说明见 [Driver/SOURCE.md](mac-app/Driver/SOURCE.md)。
