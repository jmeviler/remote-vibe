Remote Vibe 0.6.0 · 简体中文 / English · Apple Silicon / Intel · macOS 15+

- 全新“语音工作台”（Voice Studio）：在遥控器示意图上点击麦克风语音键即可进入专属语音设置面板，直接配置微信 / 豆包 / 系统听写 / 自定义快捷键及通话连说开关；在设置窗口内按住遥控器语音键可实时查看麦克风收音音量条跳动（自动静默试麦，不误触输入快捷键）。
- 直观改键与真机联动：打开设置窗口时按下手里的遥控器实体按键即可自动高亮跳到对应键位；`单击 / 双击 / 长按` 自动以圆点标注已配置状态，关闭窗口若有未保存草稿会弹窗提醒。
- 动作搜索与键盘直录：百余项预设动作新增实时关键词搜索过滤；自定义按键与语音触发升级为点击后直接在键盘按下组合键录制（自动过滤方向键与功能键的隐式 Fn 标记）。
- 主次视觉层级与深色模式：区分主操作、次要操作与危险按钮样式，合并精简顶部就绪胶囊与底栏状态，全面适配 macOS 浅色与深色模式（Dark Mode）自动切换。
- 继续提供独立的 Apple Silicon 与 Intel 安装包与更新包，支持 macOS 15+（HAL 语音驱动仍为 0.1.0 / 构建号 1，已有对应架构驱动的用户可直接仅更新 App）。

**下载选择**

| Mac 芯片 | 首次安装或升级：App + 语音组件 | 已有对应语音组件：仅更新 App |
| --- | --- | --- |
| Apple Silicon（M1 / M2 / M3 / M4 等 M 系列） | `Remote-Vibe-0.6.0-Mac-AppleSilicon.zip` | `Remote-Vibe-0.6.0-App-AppleSilicon.zip` |
| Intel | `Remote-Vibe-0.6.0-Mac-Intel.zip` | `Remote-Vibe-0.6.0-App-Intel.zip` |

在“关于本机”查看芯片。两种架构均要求 macOS 15 或更新。更新前退出 App、备份旧 App，再替换原位置；App 更新包不会重启音频服务。完整包附对应源码、使用说明和卸载包。

`SHA256SUMS.txt` 包含全部四个 ZIP 的校验值。下载全部附件时运行 `shasum -a 256 -c SHA256SUMS.txt`；只下载一个包时可运行 `shasum -a 256 <文件名>`，与校验文件中该文件的值比较。

两种架构均通过云端原生编译、隔离测试、构建和打包检查。Intel 的真实蓝牙遥控器、系统驱动加载与微信出字尚未实测，当前作为新增试用包提供。App 与驱动为临时签名，尚未经过 Apple 公证；默认触发依赖微信全局 Fn 语音输入，也可在语音工作台切换至其他语音输入工具的触发快捷键。

---

Remote Vibe 0.6.0 · Simplified Chinese / English · Apple Silicon / Intel · macOS 15+

- Voice Studio & live mic meter: clicking the microphone button on the remote diagram opens an interactive Voice Studio with presets (WeChat, Doubao/Whisper, Dictation, Mic-only, or Custom Shortcut), audio routing toggles, and a live 24-bar audio input meter (holding the remote mic button while viewing Settings runs a silent mic check automatically).
- Physical-to-UI button jump & gesture indicators: pressing any physical key on a connected remote while Settings is focused jumps straight to that key; `Single / Double / Long Press` tabs mark configured gestures, and closing with unsaved drafts prompts to save or discard.
- Instant action filter & direct shortcut recorder: filter 110+ preset actions by keyword and record custom keyboard shortcuts with a single click and keypress.
- Adaptive Dark Mode & button hierarchy: full Light and Dark Mode support, clear primary/secondary/destructive button styling, and a unified status pill & footer.
- Continues providing separate Apple Silicon and Intel native archives for macOS 15+ (HAL driver remains 0.1.0 / build 1).

Choose **Mac-AppleSilicon.zip** or **Mac-Intel.zip** for first setup or complete upgrades, and the matching **App-AppleSilicon.zip** or **App-Intel.zip** for an App-only update. Both require macOS 15+. The combined **SHA256SUMS.txt** covers all four archives.
