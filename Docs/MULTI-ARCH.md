# Apple Silicon 与 Intel 分架构发布

从 v0.4.8 起，Apple Silicon 和 Intel 使用两个独立的构建任务与下载系列。M1、M2、M3、M4 等 M 系列共用 `arm64`，Intel Mac 使用 `x86_64`。两种架构均要求 macOS 15+，不覆盖无法升级到该系统的旧款 Intel Mac。

## 云端流程

| 芯片 | GitHub Actions runner | 架构参数 | 包名后缀 |
| --- | --- | --- | --- |
| Apple Silicon | `macos-15` | `REMOTE_VIBE_ARCH=arm64` | `AppleSilicon.zip` |
| Intel | `macos-15-intel` | `REMOTE_VIBE_ARCH=x86_64` | `Intel.zip` |

每台 runner 先核对本机架构，随后运行本架构的测试程序、编译 App 与语音驱动、签名、制作完整安装包和 App 更新包。包内 App 和驱动必须都是选定的单一架构。所有编译和打包均在云端执行。

`Scripts/build-target.sh` 集中解析架构及文件名后缀；测试和构建脚本共用它。驱动包也附带这个脚本，保持对应源码可重建。

两台 runner 各输出不重名的校验清单。汇总任务验证两种架构的全部四个 ZIP 后生成统一 `SHA256SUMS.txt`，上传 `Remote-Vibe-Release` 产物。任一架构失败都会阻止汇总和 Release 草稿生成。

## 安装与更新

完整安装包的 `hostArchitectures` 和安装前检查都限定目标架构；检查实际 Apple Silicon 硬件，避免 Rosetta 导致误判。已有组件的备份、卸载与覆盖规则保持不变。

App 手动检查更新按其编译架构寻找附件。Apple Silicon 沿用 `Remote-Vibe-<版本>-App-AppleSilicon.zip`，旧版本无需改动即可发现新版；Intel 匹配 `Remote-Vibe-<版本>-App-Intel.zip`。不会合并成 Universal 安装包。

## 验证与边界

`Tests/package_test.py` 核对每个下载包的校验值、版本、源码提交、App / 驱动架构与签名、安装器架构和图标资源。CI 还执行安装器的只读前置检查，验证本架构允许通过、另一架构被拒绝，不向系统安装组件。

隔离测试覆盖配置、手势、UI、语音会话、音频恢复和驱动内存回环。云端编译及这些测试不能替代真实蓝牙遥控器、系统 HAL 驱动加载与微信出字验证。Intel 初始版本作为试用包提供；当前仍需补齐 Intel 真机验收。

## 官方参考

- [GitHub 托管 runner：标签、架构与公开仓库额度](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Apple：macOS 二进制架构与通用二进制说明](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
