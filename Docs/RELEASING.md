# 发布与更新

分发使用 GitHub Releases。App 只在用户点“检查更新”时查询本仓库最新正式 Release，比较版本并检查 App 下载包是否就绪。结果显示在菜单中；下载、退出 App 和替换文件由用户完成。没有后台轮询或自动安装。

App、语音驱动、测试程序和多架构验证的编译、打包统一使用 GitHub Actions 云端 Mac。本机只编辑源码、做无需编译的静态检查、下载校验产物和按需安装预览，不执行本机构建或打包。

## 维护者发布一次新版

1. 修改 `Resources/Info.plist` 的版本号和递增构建号，更新 `Docs/RELEASE-NOTES.md`，提交 PR。
2. 合并通过 CI 的 PR。在 GitHub **Actions → Build macOS App → Run workflow**，选择 `main`，勾选 `draft_release`。
3. 工作流验证、构建并打包，在 **Releases** 创建 `v<版本号>` 的草稿，附两个 ZIP 和校验文件。
4. 检查草稿内容、下载包与实际试说结果，再点 **Publish release**。发布后，App 的手动检查才能看到它。

同一版本只创建一次。已有同名草稿时，在 Releases 检查并处理，工作流不会覆盖已有发布。正常 PR / main 构建只上传 Actions 产物，不发布。

没有正式 Release 时，App 显示“暂无正式发布版本”。遇到 GitHub 匿名接口限流会明确提示，可稍后重试或直接打开发布页，不会自动重复请求。发布草稿或 GitHub Actions 产物不会被当成正式更新。

## 两种包

| 文件 | 使用方式 |
| --- | --- |
| `Remote-Vibe-<版本>-Mac-AppleSilicon.zip` | 首次安装，包含 App、驱动、使用说明和源码 |
| `Remote-Vibe-<版本>-App-AppleSilicon.zip` | 退出 App、备份并替换原 App，保留现有驱动与配置 |
| `SHA256SUMS.txt` | 在下载目录执行 `shasum -a 256 -c SHA256SUMS.txt` |

App 更新包适用于已安装当前语音组件的用户，未来若驱动变化，需另行说明升级要求。开发版用户应替换实际运行路径，避免同时保留两个正在使用的副本。

## 云端构建与产物校验

PR 和 main 的构建由 `.github/workflows/build.yml` 自动运行；需要正式发布草稿时，在 main 上触发同一工作流并启用 `draft_release`。`Scripts/package.sh` 在 runner 的干净工作树中执行；ZIP 内的源码和提交记录对应工作流的 `HEAD`。打包不会安装驱动或启动 App。

检查云端测试与打包成功后，下载 Actions 产物或 Release 草稿附件。校验 SHA256、ZIP 完整性、版本 / 构建号、`Source-Commit.txt`、App / 驱动签名及资源是否齐全。下载到本机校验不重新编译。已获得发布指令时，校验完成后直接合并和发布，无需再请求一次确认。

多架构方案见 [Intel 与通用包研究](MULTI-ARCH.md)；当前正式版仍仅支持 Apple Silicon / macOS 15+。

目前仅构建 Apple Silicon / macOS 15+。App 与驱动使用临时本机签名，安装包尚未使用 Developer ID 签名，也未经过 Apple 公证。GitHub Releases 提供分发，不代替 Apple 公证；面向更广泛用户分发前，可再接入 Apple Developer 证书与公证流程。

## 语言资源

`Resources/en.lproj` 和 `zh-Hans.lproj` 使用 macOS 原生 `.strings`。界面跟随系统的首选支持语言，其他语言回退英文。更改系统语言后重开 App；语音识别语言由微信决定。
