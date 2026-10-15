Remote Vibe 0.4.6 · 简体中文 / English · Apple Silicon · macOS 15+

- 音频设备失效或系统音频服务重启后自动重建连接；开麦失败最多重建并重试一次。录音中断后取消本次语音，等待重新按键。
- 修复展开菜单时语音准备和收尾可能暂停的问题，及时释放 Fn 并恢复原麦克风。
- 配置逐键容错，保存前保留有效备份或损坏原文。菜单栏「键位配置」支持导出已保存键位、导入草稿和载入有效备份；导入与恢复后仍需点击「保存并生效」。
- 增加本地语音耗时、缓存峰值、缓冲溢出和排空超时诊断，不记录音频或识别文字。语音等待参数保持原值。
- 音频恢复、菜单收尾、配置备份与导入导出测试，以及已有驱动测试纳入 CI。

**下载选择**

- 首次安装：`Remote-Vibe-0.4.6-Mac-AppleSilicon.zip`，包含 App、语音组件、使用说明和对应源码。
- 已安装语音组件：`Remote-Vibe-0.4.6-App-AppleSilicon.zip`。退出 App、备份旧 App 后替换原位置；沿用现有驱动，无需重启音频服务。
- 在下载目录运行 `shasum -a 256 -c SHA256SUMS.txt` 校验两个 ZIP。

本版已通过隔离的音频恢复与驱动测试、语音协议 / 会话测试、手势 / 鼠标 / 配置测试、中英文 UI 检查及完整构建。真实遥控器与微信出字尚未在本版重新实测。

当前为未经过 Apple 公证的试用构建。语音识别仍依赖微信全局 Fn 语音输入；语音期间会临时切换系统默认麦克风。

---

This update rebuilds the audio connection after a device failure or an audio-service restart, retries a failed microphone start once, and cancels interrupted recordings until the next button press. Voice preparation and cleanup continue while the menu is open.

Bindings now recover per button and preserve a valid backup or the original damaged data before saving. The **Binding Configurations** menu exports saved normal/mouse bindings, imports a draft, and loads the last valid backup. Review imported or restored drafts and click **Save and Apply**.

Local diagnostics include session timings, peak buffering, overflow and drain timeouts, without recording audio or recognized text. Existing voice delay values are unchanged. Audio recovery, menu cleanup, configuration and driver tests now run in CI.

**Downloads:** use `Mac-AppleSilicon.zip` for first setup, or `App-AppleSilicon.zip` to replace only the app after quitting and backing it up. The driver is unchanged. Verify downloads with `SHA256SUMS.txt`.

Automated checks and the full build passed. Physical remote and WeChat transcription tests have not been repeated for this version. Trial build: ad hoc signed, not Apple-notarized. Recognition requires WeChat global hold-Fn input; voice temporarily changes the default input device.
