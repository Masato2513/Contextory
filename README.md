# Contextory（右键助手）

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="右键助手图标">
</p>

<h1 align="center">Contextory</h1>

<p align="center">
  macOS Finder 右键新建文件助手
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
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
| 当前版本 | `1.0.2`（以 `VERSION` 文件为准） |
| 支持架构 | 仅 `arm64`，即 Apple Silicon / M 系列 Mac |
| 最低系统 | macOS 15（Sequoia） |
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

- 七种常用格式分别使用 `新建文本.txt`、`新建 Markdown 文档.md`、`新建 JSON 数据.json`、`新建文档.docx`、`新建表格.xlsx`、`新建演示文稿.pptx`、`新建 PDF 文档.pdf`。
- 同名时依次生成 `新建文档 2.docx`、`新建文档 3.docx`，保留各自名称及后缀。
- TXT、Markdown、JSON 以及“其他…”创建真正的空文件。
- DOCX、XLSX、PPTX 使用内置的有效模板；PDF 使用最小有效 PDF 结构。
- “其他…”可输入完整文件名，例如 `test.csv`、`config.yaml`、`index.html` 或 `.env`。
- “其他…”会拒绝 DOCX、XLSX、PPTX、PDF，避免生成无法打开的零字节伪文件。
- 创建成功后 Finder 保留新文件的高亮选中；成功提示默认关闭，可在“概览”中手动开启。

对于 iCloud Drive、同步桌面、OneDrive 等会抑制第三方 FinderSync 菜单的
File Provider 目录，可在“Finder → 云盘兼容菜单”中启用 `⌘ + 右键`。该手势
弹出独立的新建文件菜单并复用上面的全部格式、模板、命名与高亮逻辑；普通右键
仍由 Finder 原样处理。

菜单图标统一为 16×16，并为浅色、深色外观生成独立缓存。系统外观变化时扩展会刷新缓存；打开菜单时只读取一次系统外观值作兜底，不使用定时轮询。

状态栏使用独立的 20 pt 自定义鼠标模板图标。仓库保存 36×36 Retina PNG，macOS 根据模板透明度自动处理浅色、深色、高对比度和按下状态，不复用彩色 App 图标。

宿主进程在后台不会预先创建设置窗口；首次打开设置时创建窗口并显示 Dock 图标，之后复用普通侧栏和滚动布局。关闭窗口后隐藏 Dock 图标、停止设置页自动检测，保留窗口和导航状态以便快速再次打开。设置页显示期间可以从 Dock 菜单正常退出 App。

通过 Dock 或状态栏执行“退出”会暂停 Finder 菜单并阻止扩展重新拉起宿主；扩展进程可能仍由 macOS 暂时保留，但不会继续提供动作。再次手动打开右键助手会恢复菜单。异常崩溃不写入主动退出状态，扩展仍可自动恢复宿主。

宿主由 Launch Services 强制保持单实例。Finder 扩展初始化和 Finder 重启不会抢先启动宿主；只有用户手动打开、登录启动或实际点击文件动作时才会按需启动。普通双击请求显示设置窗口；扩展后台恢复和启用了静默模式的登录启动不会弹出窗口。

1.0.3 不再在关闭动画后销毁设置视图或主动调用 malloc 回收。设置页共用一个串行检测入口，避免重复创建检测任务；动作队列合并唤醒信号，每批最多领取 32 个事件，当前动作完成后再继续。Finder 扩展只保留菜单描述与动作投递代码。内存变化应在相同设置、相同窗口状态下实测，不能用可执行文件大小推算。

## 设置功能

- 概览：Finder Extension 状态、登录时启动、后台静默启动、成功提示。
- Finder：扩展注册、`⌘ + 右键`云盘兼容菜单、全部目录或自定义目录、文件访问权限检测。
- 诊断：服务状态、动作队列、推荐修复、诊断报告和可选调试日志。

“完全磁盘访问”只影响受保护位置的文件读写，不决定 Finder 菜单是否显示。没有访问受保护目录的需求时，不必为了菜单显示而授权。

云盘兼容菜单默认关闭。启用后需要授予“辅助功能”权限，并在第一次使用时允许
右键助手控制 Finder；它只监听右键按下/抬起事件，不监听键盘输入或鼠标移动。
若希望重启 Mac 后仍可直接使用，请同时启用“登录时启动右键助手”。

## 离线与隐私

运行时只进行本地文件操作、系统日志记录，以及 Finder Extension 与宿主 App 之间的本地动作队列通信。启用云盘兼容菜单后，会使用本机辅助功能 API 识别 Finder 点击位置，并通过本机 Apple Events 读取当前 Finder 目录；这些操作不经过网络。源码已移除更新 UI、更新检查、外部工具下载和无效的云盘路径注册逻辑。

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
- macOS 15（Sequoia）或更高版本
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

### GitHub Actions 自动发布

仓库内置 `.github/workflows/release.yml`。推送与 `VERSION` 一致的版本标签时，GitHub Actions 会在 Apple Silicon macOS runner 上自动运行测试、构建并校验产物，然后创建 GitHub Release，上传 DMG、ZIP 与 SHA-256 校验文件。

发布 1.0.2：

```bash
git tag v1.0.2
git push origin v1.0.2
```

也可以在仓库的 Actions 页面手动运行“构建与发布”；手动运行只生成保留 30 天的 Actions Artifact，不会创建或覆盖 Release。

CI 产物采用 Ad-hoc 签名且未经 Apple 公证，适合作为自用备份。首次安装仍可能需要在“系统设置 → 隐私与安全性”中手动允许。

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
7. 在 Finder 设置中启用云盘兼容菜单并完成辅助功能、Finder 自动化授权。
8. 在 iCloud Drive、iCloud 同步桌面或 OneDrive 空白处按住 `⌘` 再右键，能够创建文件；不按 `⌘` 的普通右键保持原行为。

安装新构建后第一次仍看到旧图标或旧菜单时，执行一次 `killall Finder` 清除 Finder Extension 进程缓存。之后系统外观切换由扩展自动处理。

## 已知限制

- Finder 仍可能在 iCloud Drive、同步桌面以及部分 File Provider 目录中抑制第三方 FinderSync 原生菜单；这是系统限制。需要在设置中启用独立的 `⌘ + 右键`兼容菜单。
- `⌘ + 右键`依赖宿主 App 后台运行、辅助功能权限和 Finder 自动化权限；通过 Dock 或状态栏退出右键助手后，该手势会随宿主一起停用。
- “其他…”用于普通空文件，不负责生成 Office、PDF 等结构化文件；这些格式必须走对应的一键模板动作。
- 当前产物仅包含 `arm64`，不能在 Intel Mac 上运行。

## 排障

Finder 中没有菜单时，依次检查：

1. 打开右键助手，在“Finder”页确认扩展已注册并启用。
2. 到系统设置确认 Finder Extension 开关处于开启状态。
3. 在“诊断”页执行建议修复或复制诊断报告。
4. 执行 `killall Finder`，再重新打开 Finder 菜单。
5. 仅当目标目录确实受保护且创建失败时，再检查完全磁盘访问权限。

`⌘ + 右键`兼容菜单没有响应时，确认 Finder 页中的开关已开启，并检查“隐私与安全性 → 辅助功能”和“隐私与安全性 → 自动化”中的右键助手权限。Ad-hoc 签名产物升级后，macOS 可能要求重新授权。

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

本项目是 [guyue55/MacRightClick](https://github.com/guyue55/MacRightClick) 的个人精简分支，继续遵循 [MIT License](LICENSE)。上游代码版权归 `guyue55`，本分支的修改版权归 `Masato2513`；两项声明均保留在许可证文件中。Finder 组合右键兼容层参考了 MIT 项目 MacTweaks，声明见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。具体修改内容记录在本 README 与 [CHANGELOG](CHANGELOG.md)，避免许可证正文随功能变化而失真。
