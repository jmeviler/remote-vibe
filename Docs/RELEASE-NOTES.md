Remote Vibe 0.4.7 · 简体中文 / English · Apple Silicon · macOS 15+

- 菜单栏改为透明图标，分别显示普通、语音中和鼠标模式；语音状态优先显示，悬停提示和辅助功能标签保留状态文字。
- 提供普通屏与 Retina 图标，由 macOS 适配深浅色菜单栏。图标缓存复用，随状态变化更新，没有新增轮询或动画。
- 修复深色遥控器卡片上「普通键位 / 鼠标键位」未选中文字过暗的问题，两种选中状态都清晰可读。

**下载选择**

- 首次安装：`Remote-Vibe-0.4.7-Mac-AppleSilicon.zip`，包含 App、语音组件、使用说明和对应源码。
- 已安装语音组件：`Remote-Vibe-0.4.7-App-AppleSilicon.zip`。退出 App、备份旧 App 后替换原位置；沿用现有驱动，无需重启音频服务。
- 在下载目录运行 `shasum -a 256 -c SHA256SUMS.txt` 校验两个 ZIP。

本版界面已在本机安装确认；图标资源加载、普通屏 / Retina 尺寸与两种键位选择状态已检查。自动化测试、完整构建与打包通过。真实遥控器与微信出字尚未在本版重新实测。

当前为未经过 Apple 公证的试用构建。语音识别仍依赖微信全局 Fn 语音输入；语音期间会临时切换系统默认麦克风。

---

The menu bar now uses transparent icons for normal, speaking and mouse modes, with speaking taking priority. Tooltips and accessibility labels retain the status text.

Standard and Retina assets adapt to light and dark menu bars through macOS template rendering. Images are cached and updated when the state changes, with no added polling or animation.

Fixed unreadable unselected text in the **Normal bindings / Mouse bindings** selector on the dark remote card. Both selection states are now readable.

**Downloads:** use `Mac-AppleSilicon.zip` for first setup, or `App-AppleSilicon.zip` to replace only the app after quitting and backing it up. The driver is unchanged. Verify downloads with `SHA256SUMS.txt`.

The interface was installed and visually confirmed on a local Mac. Bundled icon loading, standard/Retina sizes and both binding selection states were checked. Automated tests, the full build and packaging passed. Physical remote and WeChat transcription tests have not been repeated for this version. Trial build: ad hoc signed, not Apple-notarized. Recognition requires WeChat global hold-Fn input; voice temporarily changes the default input device.
