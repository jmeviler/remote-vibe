# Intel 与通用包研究

研究日期：2026-10-15；源码基线：`eb216ab`（v0.4.7）。当前正式发布仍为 Apple Silicon / macOS 15+，本页记录可行性和后续改动范围。

## 结论

GitHub Actions 可以远程构建两种 Mac 架构。M1、M2、M3、M4 等 M 系列共用 `arm64`，无需逐型号打包；Intel Mac 使用 `x86_64`。支持 Intel 仍受最低 macOS 15 版本限制，不代表覆盖所有老款 Intel Mac。

GitHub 官方当前提供以下标准 macOS runner，公开仓库可免费使用：

| 目标 | Runner 标签 | 架构 |
| --- | --- | --- |
| Apple Silicon | `macos-15` | `arm64` |
| Intel Mac | `macos-15-intel` | `x86_64` |

建议分别在两种 runner 编译并运行隔离测试，再生成 Universal 2 通用包。通用 App 和语音驱动各自包含两种架构，macOS 选择本机架构执行，用户无需辨别芯片。也可先提供两个独立架构的安装包，减少首次适配范围。

## 已验证与边界

- 现有 Swift App 使用 `x86_64-apple-macos15.0` 目标编译和链接成功，产物为 `Mach-O 64-bit executable x86_64`。
- 现有 Core Audio 语音驱动使用 `-arch x86_64` 编译和链接成功，产物为 `Mach-O 64-bit bundle x86_64`。
- 上述编译试验在本地 Apple Silicon Mac 完成，发生在统一云端构建约定之前；后续架构验证全部放到 GitHub Actions。
- 尚未完成 Intel runner 上的测试、Intel 真机的蓝牙 / HID / 驱动加载 / 微信出字验证，或通用安装包制作。交叉编译成功不能替代这些验证。
- 云端 runner 能运行编译和隔离测试；实际遥控器与微信语音仍需真机验收。

## 后续实施范围

1. `.github/workflows/build.yml` 增加 `macos-15` / `macos-15-intel` 矩阵，明确目标架构和产物名称。
2. `Scripts/build-app.sh`、`Scripts/build-driver.sh` 及 `Tests/*.sh` 的固定 `arm64` 改为明确的架构参数，确保测试运行的是 runner 本机架构。
3. 若采用通用包，两个架构均通过后，在云端对 App 和驱动各执行 `lipo -create`，再对最终 bundle 签名与验证。只合并 App 而不合并驱动不足以支持两类 Mac。
4. 更新 `Installer/preinstall` 的 Apple Silicon 限制、`Scripts/package.sh` 的 `hostArchitectures`、下载文件名与中英文使用说明；保留 macOS 15 最低要求。
5. 更新 `Sources/App/ReleaseUpdate.swift` 的附件匹配。v0.4.7 客户端固定查找 `App-AppleSilicon.zip`，首次迁移需保留旧文件名的兼容附件，否则旧客户端会提示下载包尚未就绪。
6. 校验两类架构的 App / 驱动、源代码提交、签名、安装器约束及 SHA256。完成 Intel 真机验收后，再将 Intel 标记为正式支持。

## 官方参考

- [GitHub 托管 runner：标签、架构与公开仓库额度](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Apple：构建 Universal macOS 二进制](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
