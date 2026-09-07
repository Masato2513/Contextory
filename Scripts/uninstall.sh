#!/bin/bash

# ==============================================================================
# 右键助手 (Contextory) 卸载工具
# ==============================================================================
set -e

echo "🧹 [Uninstall] 开始卸载右键助手并清理旧进程..."

# 1. 注销当前 Contextory FinderSync 扩展
echo "🔌 [Uninstall] 1. 反注册和卸载系统中的 FinderSync 插件..."
pluginkit -r io.github.masato2513.Contextory.Extension 2>/dev/null || true
pluginkit -r "/Applications/Contextory.app/Contents/PlugIns/ContextoryFinderExtension.appex" 2>/dev/null || true
pluginkit -r "/Applications/右键助手.app/Contents/PlugIns/ContextoryFinderExtension.appex" 2>/dev/null || true
pluginkit -r "build/右键助手.app/Contents/PlugIns/ContextoryFinderExtension.appex" 2>/dev/null || true

# 2. 终止常驻的主宿主 App 进程
echo "🛑 [Uninstall] 2. 终止常驻保活的主程序进程..."
killall Contextory 2>/dev/null || true

# 3. 删除主 App 部署包
echo "🗑️ [Uninstall] 3. 清除 /Applications 目录下的主程序..."
rm -rf "/Applications/Contextory.app"
rm -rf "/Applications/右键助手.app"

# 4. 清理共享中介目录
echo "📂 [Uninstall] 4. 清除共享中介缓存..."
rm -rf "$HOME/Library/Containers/io.github.masato2513.Contextory.Extension/Data" 2>/dev/null || true

# 5. 重启访达 (Finder)，释放扩展 XPC 会话
echo "🔄 [Uninstall] 5. 重启访达进程以释放扩展缓存..."
killall Finder 2>/dev/null || true

echo "=============================================================================="
echo "🟢 [Uninstall] 卸载与缓存清理完成。"
echo "=============================================================================="
