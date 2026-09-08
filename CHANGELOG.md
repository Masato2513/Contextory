# 更新记录

本文件只记录当前个人精简分支的行为。上游项目的完整版本历史可在
[guyue55/MacRightClick](https://github.com/guyue55/MacRightClick) 及本仓库 Git 历史中查看。

## Unreleased

## 1.0.1 — 2026-09-08

### Added

- 新增可选的 `⌘ + 右键`独立兼容菜单，可在 iCloud Drive、同步桌面、OneDrive 等 FinderSync 菜单受限的位置复用全部新建文件动作。
- 新增辅助功能授权引导、Finder 自动化用途说明和 MIT 第三方声明；兼容层不使用轮询、不监听键盘输入，也不新增常驻进程。

### Changed

- 最低系统版本提升至 macOS 15（Sequoia），删除旧系统兼容分支；宿主设置页统一使用 `pluginkit`读取 Finder 扩展状态，不再直接链接 FinderSync framework。

### Fixed

- 修复兼容菜单弹出后错误激活宿主 App、导致持续按住 `⌘`再次右键时落入 Finder 系统菜单的问题；重复触发时会无动画关闭旧菜单并在新位置重新弹出，Finder 系统菜单跟踪期间不再积压延迟菜单。
- 使用系统登录项 AppleEvent 区分后台启动和用户双击，删除前台状态与延迟启发式判断，修复首次安装或关闭窗口后需要重复打开的问题。
- 串行化 Dock 身份切换与窗口展示，明确窗口释放所有权，并在设置页关闭后请求系统回收空闲内存。

## 1.0.0 — 2026-09-07

### Added

- Finder“新建文件”子菜单，仅保留 TXT、Markdown、JSON、DOCX、XLSX、PPTX、PDF 与“其他…”。
- DOCX、XLSX、PPTX 有效模板和最小有效 PDF 生成能力。
- 自定义文件名及后缀创建，同名文件自动递增编号。
- Finder 菜单图标统一为 16×16，并适配浅色、深色系统外观。
- 自定义鼠标状态栏模板图标，由 macOS 自动适配菜单栏外观。
- 精简的概览、Finder 与诊断设置页面。

### Changed

- 英文产品名完整更名为 Contextory，并同步可执行文件、Swift 模块、Bundle ID、App Group、通知、日志、脚本和构建产物名称；中文显示名仍为“右键助手”。
- App 显示名称改为“右键助手”。
- 构建目标收敛为 Apple Silicon `arm64`，最低支持 macOS 13。
- 文件创建成功后保留 Finder 高亮选中，成功提示可在设置中关闭。
- 外观切换使用事件通知刷新图标缓存，并在菜单打开时进行一次轻量兜底校验。
- 删除不再被精简版使用的动作配置、菜单布局与缓存代码。
- 默认本机构建使用 `-O` 优化，测试保留 SwiftPM 的独立调试配置。
- 重写构建、安装、验收、离线边界、已知限制与排障文档。
- 设置窗口改为按需创建，关闭时释放 SwiftUI 视图树、图层与订阅；后台常驻只保留状态栏和动作队列，降低宿主进程内存占用。
- 设置窗口显示时动态展示 Dock 图标与系统退出入口，关闭窗口后恢复为无 Dock 图标的状态栏模式，宿主进程保持运行。
- Dock 或状态栏主动退出后暂停 Finder 菜单并抑制宿主自动复活；手动启动恢复功能，异常退出仍保留自动恢复能力。
- 禁止宿主多实例运行，并移除 Finder 扩展初始化阶段的抢先拉起；主动退出后的首次手动启动立即显示设置窗口，消除无响应与重复进程。
- 设置窗口关闭后等待 AppKit 动画事务结束再释放 SwiftUI 视图树，避免 Dock 身份切换期间发生窗口动画释放崩溃。
- 增加 GitHub Actions arm64 发布流程；版本标签可自动生成 Release、DMG、ZIP 与 SHA-256 校验文件。

### Removed

- 除“新建文件”以外的 Finder 动作、动作收藏、配置档与菜单布局选项。
- 更新检查、更新 UI、网络请求、外部工具安装与下载能力。
- 无效的 iCloud、OneDrive、CloudStorage 兼容开关及云盘路径注册逻辑。
- Quick Service、Homebrew Cask、Intel 架构与 Mac App Store 构建路线的现行支持。

### Notes

- 默认构建使用 Ad-hoc 签名且未经 Apple 公证，仅建议自用。
- iCloud Drive 和部分 File Provider 目录是否展示 FinderSync 菜单仍由 macOS/Finder 决定。
- Contextory 使用新的 Bundle ID 与共享容器，不自动迁移更名前版本的设置和动作队列。
