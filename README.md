# Contextory（右键助手）

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="右键助手图标">
</p>

<h1 align="center">Contextory</h1>

<p align="center">
  macOS Finder 右键新建文件助手
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-000000?logo=apple&logoColor=white" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">

  <a href="https://github.com/Masato2513/Contextory/releases/latest">
    <img src="https://img.shields.io/github/v/release/Masato2513/Contextory?label=version" alt="Release">
  </a>

  <a href="https://github.com/Masato2513/Contextory/releases">
    <img src="https://img.shields.io/github/downloads/Masato2513/Contextory/total" alt="Downloads">
  </a>

  <a href="./LICENSE">
    <img src="https://img.shields.io/github/license/Masato2513/Contextory" alt="License">
  </a>

  <a href="https://github.com/Masato2513/Contextory/stargazers">
    <img src="https://img.shields.io/github/stars/Masato2513/Contextory?style=flat" alt="Stars">
  </a>
</p>


Contextory 是一个面向个人使用的 macOS Finder 右键新建文件工具，中文显示名为“右键助手”。名称由 Context 与 Factory 组合而来，表达“右键上下文的工具工厂”。当前分支基于
[guyue55/MacRightClick](https://github.com/guyue55/MacRightClick) 精简，只保留新建文件、必要设置与诊断能力。

## 当前版本

| 项目 | 状态 |
| --- | --- |
| 产品名称 | Contextory |
| 中文显示名 | 右键助手 |
| 当前版本 | `1.0.0`（以 `VERSION` 文件为准） |
| 支持架构 | 仅 `arm64`，即 Apple Silicon / M 系列 Mac |
| 最低系统 | macOS 13 |
| 默认签名 | Ad-hoc，未使用 Developer ID、未公证 |
| 网络能力 | 无更新检查、下载、广告、遥测或其他网络请求 |

## Finder 菜单

```text
新建文件
├─ 文本文件 (.txt)
├─ Markdown (.md)
├─ JSON (.json)
├─ Word 文档 (.docx)
├─ Excel 表格 (.xlsx)
├─ PowerPoint 演示文稿 (.pptx)
├─ PDF 文档 (.pdf)
└─ 其他…
```

- 七种常用格式使用固定默认名，例如 `新建文件.md`。
- 同名时依次生成 `新建文件 2.md`、`新建文件 3.md`。
- TXT、Markdown、JSON 以及“其他…”创建真正的空文件。
- DOCX、XLSX、PPTX 使用内置的有效模板；PDF 使用最小有效 PDF 结构。
- “其他…”可输入完整文件名，例如 `test.csv`、`config.yaml`、`index.html` 或 `.env`。
- “其他…”会拒绝 DOCX、XLSX、PPTX、PDF，避免生成无法打开的零字节伪文件。
- 创建成功后 Finder 保留新文件的高亮选中；成功提示可在“概览”中关闭。

菜单图标统一为 16×16，并为浅色、深色外观生成独立缓存。系统外观变化时扩展会刷新缓存；打开菜单时只读取一次系统外观值作兜底，不使用定时轮询。

状态栏使用独立的 20 pt 自定义鼠标模板图标。仓库保存 36×36 Retina PNG，macOS 根据模板透明度自动处理浅色、深色、高对比度和按下状态，不复用彩色 App 图标。

宿主进程在后台不会预先创建设置窗口；只有打开设置时才加载 SwiftUI 视图树并显示 Dock 图标，关闭窗口后会释放界面资源、隐藏 Dock 图标，并继续以轻量状态栏模式运行。设置页显示期间可以从 Dock 菜单正常退出 App。

通过 Dock 或状态栏执行“退出”会暂停 Finder 菜单并阻止扩展重新拉起宿主；扩展进程可能仍由 macOS 暂时保留，但不会继续提供动作。再次手动打开右键助手会恢复菜单。异常崩溃不写入主动退出状态，扩展仍可自动恢复宿主。

## 设置功能

- 概览：Finder Extension 状态、登录时启动、后台静默启动、成功提示。
- Finder：扩展注册、全部目录或自定义目录、文件访问权限检测。
- 诊断：服务状态、动作队列、推荐修复、诊断报告和可选调试日志。

“完全磁盘访问”只影响受保护位置的文件读写，不决定 Finder 菜单是否显示。没有访问受保护目录的需求时，不必为了菜单显示而授权。

## 离线与隐私

运行时只进行本地文件操作、系统日志记录，以及 Finder Extension 与宿主 App 之间的本地动作队列通信。源码已移除更新 UI、更新检查、外部工具下载和无效的云盘路径注册逻辑。

如需自行复核，可在构建后搜索可执行文件中的常见网络符号：

```bash
rg -a -i 'URLSession|https?://|github\.com|sparkle' \
  "build/右键助手.app/Contents/MacOS/Contextory" \
  "build/右键助手.app/Contents/PlugIns/ContextoryFinderExtension.appex/Contents/MacOS/ContextoryFinderExtension"
```

预期没有匹配结果。

## 构建

### 环境要求

- Apple Silicon Mac
- macOS 13 或更高版本
- Xcode 或 Xcode Command Line Tools，且可用 `swiftc`、`xcrun`、`codesign`、`hdiutil`、`iconutil`

首次配置命令行工具时可执行：

```bash
xcode-select --install
```

### 测试与本机构建

在仓库根目录执行：

```bash
swift test
./Scripts/build.sh
```

默认 `website-dev` 构建只生成 `arm64` 代码、启用 `-O` 编译优化并使用 Ad-hoc 签名。产物位于：

- `build/右键助手.app`
- `build/Contextory.zip`
- `build/Contextory.dmg`

### 可选：Developer ID 签名与公证

仅在拥有有效 Apple Developer 证书和已配置的 `notarytool` 钥匙串配置时使用：

```bash
DISTRIBUTION_ROUTE=website-release \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="contextory" \
./Scripts/build.sh
```

## 安装与注册 Finder Extension

推荐打开 DMG 后将 App 拖入“应用程序”；升级时先退出右键助手，并在 Finder 提示时选择“替换”。下面的复制命令适合首次安装；如果目标位置已有 App，请先将它移到废纸篓，避免目录合并后留下旧文件。

```bash
cp -R "build/右键助手.app" /Applications/
pluginkit -a "/Applications/右键助手.app/Contents/PlugIns/ContextoryFinderExtension.appex"
pluginkit -e use -i io.github.masato2513.Contextory.Extension
killall Finder
open "/Applications/右键助手.app"
```

然后在“系统设置”的 Finder 扩展管理页面确认“右键助手扩展”已启用。不同 macOS 版本的入口名称可能略有差异，通常位于“通用 → 登录项与扩展 → Finder 扩展”。

Ad-hoc 构建首次打开被 Gatekeeper 阻止时，可按住 Control 点击 App 并选择“打开”，或在“系统设置 → 隐私与安全性”中允许。只应放行自己构建且确认来源的产物。

## 验收清单

1. Finder 空白处右键能看到“新建文件”子菜单。
2. 七种常用格式均可创建并按规则处理同名文件。
3. “其他…”能创建带自定义后缀的普通空文件。
4. 创建后文件保持高亮；关闭“显示成功提示”后不再弹出成功提示。
5. 浅色与深色外观下菜单图标清晰、尺寸一致；切换外观后重新打开菜单即可更新。
6. 重启 App 与 Finder 后扩展仍可正常使用。

安装新构建后第一次仍看到旧图标或旧菜单时，执行一次 `killall Finder` 清除 Finder Extension 进程缓存。之后系统外观切换由扩展自动处理。

## 已知限制

- Finder 可能在 iCloud Drive、同步桌面以及部分 File Provider 目录中抑制第三方 FinderSync 菜单。这不是文件创建逻辑本身能够绕过的限制；可先在菜单正常的本地目录创建，再拖入云盘目录。
- “其他…”用于普通空文件，不负责生成 Office、PDF 等结构化文件；这些格式必须走对应的一键模板动作。
- 当前产物仅包含 `arm64`，不能在 Intel Mac 上运行。

## 排障

Finder 中没有菜单时，依次检查：

1. 打开右键助手，在“Finder”页确认扩展已注册并启用。
2. 到系统设置确认 Finder Extension 开关处于开启状态。
3. 在“诊断”页执行建议修复或复制诊断报告。
4. 执行 `killall Finder`，再重新打开 Finder 菜单。
5. 仅当目标目录确实受保护且创建失败时，再检查完全磁盘访问权限。

可用以下命令检查签名和架构：

```bash
codesign --verify --deep --strict --verbose=2 "build/右键助手.app"
file "build/右键助手.app/Contents/MacOS/Contextory"
file "build/右键助手.app/Contents/PlugIns/ContextoryFinderExtension.appex/Contents/MacOS/ContextoryFinderExtension"
hdiutil verify "build/Contextory.dmg"
```

## 卸载

```bash
./Scripts/uninstall.sh
```

该脚本会删除 `/Applications` 中的 Contextory App、注销当前扩展、清理当前扩展数据，并重启 Finder。它属于破坏性清理操作；如需保留诊断或队列数据，请先备份。

## 私有仓库备份

`build/`、SwiftPM 缓存和 macOS 临时文件已由 `.gitignore` 排除。私有仓库保存的是可重复构建的源码、图标、模板、脚本和文档；换设备后重新运行测试与构建即可，不需要提交生成的 App、ZIP 或 DMG。

上传前建议执行：

```bash
git status --short
git diff --check
swift test
./Scripts/build.sh
```

确认变更无误后再提交。示例提交信息：

```bash
git add -A
git commit -m "refactor: finalize offline Finder new-file helper"
git remote -v
git push
```

如果私有仓库不是当前 `origin`，请先根据 `git remote -v` 的结果添加或调整远端，再执行推送。不要把 Apple ID、App 专用密码、`notarytool` 凭据或其他签名秘密写入仓库。

## 仓库结构

```text
Resources/                              App/状态栏图标与有效文件模板
Sources/Contextory/                    宿主 App、设置界面与核心逻辑
Sources/ContextoryFinderExtension/     Finder Sync 扩展
Tests/                                  Swift 单元测试
Scripts/build.sh                        arm64 构建、签名与打包
Scripts/uninstall.sh                    本机卸载与当前扩展数据清理
```

## 许可证与来源

本项目是 [guyue55/MacRightClick](https://github.com/guyue55/MacRightClick) 的个人精简分支，继续遵循 [MIT License](LICENSE)。上游代码版权归 `guyue55`，本分支的修改版权归 `Masato2513`；两项声明均保留在许可证文件中。具体修改内容记录在本 README 与 [CHANGELOG](CHANGELOG.md)，避免许可证正文随功能变化而失真。
