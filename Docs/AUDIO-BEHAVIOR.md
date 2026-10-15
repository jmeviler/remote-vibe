# 音频设备影响核查（2026-10-10）

当前约定：长按遥控器时使用遥控器麦克风；松开后处理完音频尾段，再恢复原输入。这个行为保持不变。

虚拟声卡基于开源 [BlackHole](https://github.com/ExistentialAudio/BlackHole) 的 Core Audio HAL 插件实现，定制为独立 `RemoteVibeMic.driver`、单声道 48 kHz、输入可作为默认设备且输出不可作为默认设备。Google 和小米共用它；转文字由微信完成。上游版本、改动及 GPL v3 许可证见 [Driver/SOURCE.md](../Driver/SOURCE.md)，分享包包含对应源码。

## 本机观察

通过 CoreAudio 属性查询和 45 秒设备变更通知观察，不录音、不修改设备、不重启音频服务：

- 初始默认输入、默认输出、系统提示音输出均为 AirPods。
- 13:44:33 开始语音：默认输入变为 `Chromecast Mic`。
- 13:44:41 语音结束：默认输入恢复 AirPods。
- 这段观察期间，默认输出、系统提示音输出没有发生切换。
- 观察开始时，虚拟声卡 `DeviceIsRunningSomewhere = 0`，处于停止状态。
- 已安装驱动属性：允许成为默认输入 = 1；允许成为默认输出 = 0；允许成为系统提示音输出 = 0。
- 已有驱动代码测试通过：音频环回、缓冲区回绕、写入结束后读取静音、双客户端停止后释放缓冲、禁止默认输出。该检查在普通测试进程运行，没有向系统声卡写音频。

这是本机一次正常会话的路由观察，不是所有耳机、会议软件或音质的兼容性认证。

## 代码确认

`VirtualMicrophone.swift` 只向虚拟设备写入遥控器音频，不读取实体麦克风；输入流被关闭，IOProc 只在会话期间启动，结束调用 `AudioDeviceStop`。空闲时保留连接句柄，避免每次说话都重新创建，但不会持续写静音。

App 只设置系统默认输入，没有设置默认输出、系统提示音输出、实体设备音量或实体设备采样率的代码。驱动的 48 kHz 是虚拟设备自身的格式。没有独占实体设备、创建聚合设备或接管其他声卡的代码。

输入恢复按设备 UID 查找，避免设备编号变化；仅当当前默认输入仍是虚拟声卡时恢复。用户在语音期间自行改选其他输入，结束时会保留用户的新选择。

## 正常使用之外的边界

- 跟随系统默认输入的软件，可能在遥控器语音期间跟着切换输入，这是当前全局切换方案的影响范围。显式选择实体麦克风的软件不会因默认设备这一属性变更而被本 App 改选。
- 正常结束、断连中止和正常退出均尝试恢复。崩溃、`SIGKILL`、系统断电无法执行即时清理；已保存的恢复标记用于下次 App 成功连接音频组件时尝试恢复。
- 原麦克风拔出或不可用时，不能保证恢复到它；也不会擅自选择另一个实体麦克风。可在系统声音设置中手动选择当前需要的输入。
- 蓝牙耳机可能因自身麦克风启停改变通话模式或音质。本次只验证了路由恢复，未测声学质量或所有蓝牙配置；输出路由不变不等于音质绝对不变。
- 安装/卸载脚本会重启 `coreaudiod`，可能短暂打断系统播放和录音。这是安装维护行为，正常启动或每次语音都不会执行。本次优化没有重装驱动或重启音频服务。

2026-10-15 的代码补充：App 监听音频服务重启与设备变化，清理失效句柄并重新连接；录音中发生失效会取消本次语音，等待重新按键。开麦失败最多重建并重试一次。原输入暂时消失时保留恢复标记，设备重新出现且系统默认输入仍为虚拟麦克风时重试恢复。上述恢复行为已通过假设备测试，本节前面的本机观察仍是 2026-10-10 的记录，未作为本轮实测结果。

## 依据

- Apple：[默认输入设备属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultinputdevice)、[默认输出设备属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice)。本机 SDK `AudioHardware.h` 明确分别定义输入、输出和提示音输出。
- Apple：[Core Audio 常见任务与 HAL](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/ARoadmaptoCommonTasks/ARoadmaptoCommonTasks.html)、[音频单元的指定设备属性](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)。
- 本项目：[VirtualMicrophone.swift](../Sources/Audio/VirtualMicrophone.swift)、[驱动源码](../Driver/RemoteVibeMic.c)、[驱动构建参数](../Scripts/build-driver.sh)、[安装脚本](../Installer/postinstall)。

原始设备通知记录在本机忽略目录 `build/performance/audio-research/routes.txt`；未包含音频内容。
