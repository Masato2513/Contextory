# 更新记录

本文件只记录当前个人精简分支的行为。上游项目的完整版本历史可在
[guyue55/MacRightClick](https://github.com/guyue55/MacRightClick) 及本仓库 Git 历史中查看。

## Unreleased

### Changed

- 设置窗口改为按需创建，关闭时释放 SwiftUI 视图树、图层与订阅；后台常驻只保留状态栏和动作队列，降低宿主进程内存占用。
- 设置窗口显示时动态展示 Dock 图标与系统退出入口，关闭窗口后恢复为无 Dock 图标的状态栏模式，宿主进程保持运行。
- Dock 或状态栏主动退出后暂停 Finder 菜单并抑制宿主自动复活；手动启动恢复功能，异常退出仍保留自动恢复能力。

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

### Removed

- 除“新建文件”以外的 Finder 动作、动作收藏、配置档与菜单布局选项。
- 更新检查、更新 UI、网络请求、外部工具安装与下载能力。
- 无效的 iCloud、OneDrive、CloudStorage 兼容开关及云盘路径注册逻辑。
- Quick Service、Homebrew Cask、Intel 架构与 Mac App Store 构建路线的现行支持。

### Notes

- 默认构建使用 Ad-hoc 签名且未经 Apple 公证，仅建议自用。
- iCloud Drive 和部分 File Provider 目录是否展示 FinderSync 菜单仍由 macOS/Finder 决定。
- Contextory 使用新的 Bundle ID 与共享容器，不自动迁移更名前版本的设置和动作队列。
