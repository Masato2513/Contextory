#!/usr/bin/env bash

# ==============================================================================
# 右键助手 (Contextory) 自动化编译与打包脚本（Apple Silicon）
# ==============================================================================
set -euo pipefail

echo "🚀 [Build] 开始自动化编译与打包流程..."

# 1. 初始化目录
BUILD_DIR="build"
APP_NAME="右键助手"
VOLUME_NAME="Contextory"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
# App 使用中文显示名，内部产品、可执行文件与扩展统一使用 Contextory。
EXT_BUNDLE="$APP_BUNDLE/Contents/PlugIns/ContextoryFinderExtension.appex"
DISTRIBUTION_ROUTE="${DISTRIBUTION_ROUTE:-website-dev}"
CODE_SIGN_IDENTITY="-"
CODESIGN_RUNTIME_ARGS=""

if [ "$DISTRIBUTION_ROUTE" = "website-release" ]; then
    if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
        echo "❌ [Build] website-release 需要设置 DEVELOPER_ID_APPLICATION，例如：Developer ID Application: Your Name (TEAMID)"
        exit 2
    fi
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
    CODESIGN_RUNTIME_ARGS="--options runtime --timestamp"
elif [ "$DISTRIBUTION_ROUTE" = "mac-app-store" ]; then
    echo "❌ [Build] 当前仓库已确定主分发路线为官网/开源站外分发。"
    echo "❌ [Build] Mac App Store 路线需要恢复主 App sandbox、正式 App Group 与 security-scoped access 后再单独启用。"
    exit 2
elif [ "$DISTRIBUTION_ROUTE" != "website-dev" ]; then
    echo "❌ [Build] 未知 DISTRIBUTION_ROUTE=$DISTRIBUTION_ROUTE，可选：website-dev / website-release / mac-app-store"
    exit 2
fi

submit_for_notarization() {
    local target="$1"

    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
        xcrun notarytool submit "$target" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --wait
    else
        echo "❌ [Build] website-release 需要 NOTARY_PROFILE，或 APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD"
        exit 2
    fi
}

if [ -n "${VERSION_OVERRIDE:-}" ]; then
    VERSION="$VERSION_OVERRIDE"
elif [ -f "VERSION" ]; then
    VERSION=$(tr -d '\r\n' < VERSION)
else
    echo "❌ [Build] 缺少 VERSION 文件，无法确定构建版本。"
    exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ [Build] VERSION 必须是稳定语义版本，实际为: $VERSION"
    exit 2
fi
echo "🏷️ [Build] 检测到全局版本号: $VERSION"
echo "🚢 [Build] 当前分发路线: $DISTRIBUTION_ROUTE"

echo "🧹 [Build] 清理旧编译目录: $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "📝 [Build] 动态创建 VFS Overlay 解决系统底层 SwiftBridging 重定义冲突..."
cat << 'EOF' > "$BUILD_DIR/empty.modulemap"
// 空的 modulemap 文件，用于通过 VFS 覆盖解决系统重定义冲突
EOF

cat << EOF > "$BUILD_DIR/overlay.yaml"
{
  'version': 0,
  'roots': [
    {
      'type': 'directory',
      'name': '/Library/Developer/CommandLineTools/usr/include/swift',
      'contents': [
        {
          'type': 'file',
          'name': 'bridging.modulemap',
          'external-contents': '$(pwd)/$BUILD_DIR/empty.modulemap'
        }
      ]
    }
  ]
}
EOF

echo "📂 [Build] 创建 macOS App Bundle 结构..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$EXT_BUNDLE/Contents/MacOS"
mkdir -p "$EXT_BUNDLE/Contents/Resources"

# 2. 动态写入主 App 的 Info.plist (包含 CFBundleIconFile)
echo "📝 [Build] 生成主程序的 Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.masato2513.Contextory</string>
    <key>CFBundleName</key>
    <string>Contextory</string>
    <key>CFBundleDisplayName</key>
    <string>右键助手</string>
    <key>CFBundleExecutable</key>
    <string>Contextory</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>用于读取当前 Finder 目录，以便在云盘位置通过 Command 加右键新建文件。</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 3. 动态写入 FinderSync 扩展的 Info.plist
echo "📝 [Build] 生成访达扩展的 Info.plist..."
cat <<EOF > "$EXT_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.masato2513.Contextory.Extension</string>
    <key>CFBundleName</key>
    <string>ContextoryFinderExtension</string>
    <key>CFBundleDisplayName</key>
    <string>右键助手扩展</string>
    <key>CFBundleExecutable</key>
    <string>ContextoryFinderExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>FinderSync</string>
    </dict>
</dict>
</plist>
EOF

# 4. 转换并打包 AppIcon
if [ -f "Resources/AppIcon.png" ]; then
    echo "🎨 [Build] 检测到 Resources/AppIcon.png，开始转换为系统级 AppIcon.icns..."
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # 缩放切图
    sips -z 16 16     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1 || true
    sips -z 32 32     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1 || true
    sips -z 32 32     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1 || true
    sips -z 64 64     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1 || true
    sips -z 128 128   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1 || true
    sips -z 256 256   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 256 256   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1 || true
    sips -z 512 512   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1 || true
    sips -z 1024 1024 "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1 || true

    if command -v zopflipng >/dev/null; then
        echo "🗜️ [Build] 使用 zopflipng 优化 AppIcon.iconset 体积..."
        for icon_png in "$ICONSET_DIR"/*.png; do
            zopflipng -y -m --lossy_transparent "$icon_png" "$icon_png" >/dev/null 2>&1 || true
        done
    fi
    
    if command -v iconutil >/dev/null; then
        # macOS 26 的 iconutil 可能输出 Invalid Iconset 却仍返回 0，必须检查真实产物。
        rm -f "$BUILD_DIR/AppIcon.icns"
        iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns" || true
        if [ -s "$BUILD_DIR/AppIcon.icns" ]; then
            cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
            echo "🟢 [Build] 成功合成并注入 AppIcon.icns 至打包！"
        else
            cp "Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
            /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.png" "$APP_BUNDLE/Contents/Info.plist"
            echo "⚠️ [Build] iconutil 未生成有效 ICNS，已改用 1024px PNG 图标。"
        fi
    else
        echo "⚠️ [Build] 未找到 iconutil 工具，使用 AppIcon.png 直接降级拷贝..."
        cp "Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.png" "$APP_BUNDLE/Contents/Info.plist"
    fi
else
    echo "⚠️ [Build] 未找到 Resources/AppIcon.png 资源，跳过图标打包。"
fi

# 状态栏使用独立的 36×36 Retina 模板图，不复用彩色 AppIcon。
if [ -s "Resources/StatusBarIcon.png" ]; then
    cp "Resources/StatusBarIcon.png" "$APP_BUNDLE/Contents/Resources/StatusBarIcon.png"
    echo "🖱️ [Build] 已注入状态栏模板图标。"
else
    echo "❌ [Build] 缺少 Resources/StatusBarIcon.png。"
    exit 2
fi

# 分发包内保留本项目及本轮参考代码的授权声明，满足 MIT 再分发要求。
cp "LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
cp "THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"

# 拷贝 Office 三件套最小骨架到 .app/Contents/Resources/Templates/
if [ -d "Resources/Templates" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Templates"
    cp -R Resources/Templates/. "$APP_BUNDLE/Contents/Resources/Templates/"
    echo "📄 [Build] 已拷贝 Word/Excel/PowerPoint 模板到 .app/Contents/Resources/Templates/"
fi

# 5. 源码列表定义
HOST_SOURCES="
    Sources/Contextory/AppDelegate.swift \
    Sources/Contextory/Services/FinderCompatibilityMenuController.swift \
    Sources/Contextory/Views/ContentView.swift \
    Sources/Contextory/Views/GeneralSettingsView.swift \
    Sources/Contextory/Views/FinderSettingsView.swift \
    Sources/Contextory/Views/DiagnosticsSettingsView.swift \
    Sources/Contextory/Views/SettingsComponents.swift \
    Sources/Contextory/Core/MenuAction.swift \
    Sources/Contextory/Core/DefaultActionRegistry.swift \
    Sources/Contextory/Core/SharedStorageManager.swift \
    Sources/Contextory/Core/SharedFolderMonitor.swift \
    Sources/Contextory/Core/ActionDispatcher.swift \
    Sources/Contextory/Core/SharedHUDManager.swift \
    Sources/Contextory/Core/FullDiskAccessChecker.swift \
    Sources/Contextory/Core/LaunchServiceManager.swift \
    Sources/Contextory/Core/LaunchPresentationPolicy.swift \
    Sources/Contextory/Core/FinderExtensionDiagnostics.swift \
    Sources/Contextory/Core/ExtensionHeartbeat.swift \
    Sources/Contextory/Core/SystemReloader.swift \
    Sources/Contextory/Core/PermissionRefreshCoordinator.swift \
    Sources/Contextory/Core/Actions/NewFileAction.swift \
    Sources/Contextory/Core/Logging/AppLog.swift \
    Sources/Contextory/Core/Distribution.swift
"

EXT_SOURCES="
    Sources/ContextoryFinderExtension/FinderSync.swift \
    Sources/Contextory/Core/MenuAction.swift \
    Sources/Contextory/Core/DefaultActionRegistry.swift \
    Sources/Contextory/Core/SharedStorageManager.swift \
    Sources/Contextory/Core/ActionDispatcher.swift \
    Sources/Contextory/Core/SharedHUDManager.swift \
    Sources/Contextory/Core/FullDiskAccessChecker.swift \
    Sources/Contextory/Core/LaunchPresentationPolicy.swift \
    Sources/Contextory/Core/ExtensionHeartbeat.swift \
    Sources/Contextory/Core/Actions/NewFileAction.swift \
    Sources/Contextory/Core/Logging/AppLog.swift \
    Sources/Contextory/Core/Distribution.swift
"

SDK_PATH=$(xcrun --show-sdk-path)
# 自用构建统一启用编译优化；单元测试仍由 SwiftPM 使用独立的调试配置。
COMMON_FLAGS="-O -parse-as-library -sdk $SDK_PATH -vfsoverlay $BUILD_DIR/overlay.yaml"

# 按分发路线注入编译期常量，供 Sources/Contextory/Core/Distribution.swift 读取
case "$DISTRIBUTION_ROUTE" in
    website-dev)     COMMON_FLAGS="$COMMON_FLAGS -D WEBSITE_DEV" ;;
    website-release) COMMON_FLAGS="$COMMON_FLAGS -D WEBSITE_RELEASE" ;;
    mac-app-store)   COMMON_FLAGS="$COMMON_FLAGS -D MAC_APP_STORE" ;;
esac

# 6. 编译 Apple Silicon 宿主主程序
echo "🛠️ [Build] 编译宿主主程序 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx15.0 $HOST_SOURCES \
    -o "$APP_BUNDLE/Contents/MacOS/Contextory"

# 7. 编译 Apple Silicon Finder Sync 扩展
echo "🛠️ [Build] 编译 Finder Sync 扩展插件 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx15.0 $EXT_SOURCES \
    -o "$EXT_BUNDLE/Contents/MacOS/ContextoryFinderExtension"


# 9. 对生成的程序和扩展进行签名
echo "🔐 [Build] 选取 Entitlements 模板（按 DISTRIBUTION_ROUTE）..."
# 模板外置在 entitlements/ 目录下，便于审计与版本对比；不再走 here-doc 动态生成。
# 三个文件 source-of-truth：
#   entitlements/website.host.entitlements  → website-dev / website-release
#   entitlements/mas.host.entitlements      → mac-app-store（本轮 build.sh 未启用，仅占位）
#   entitlements/extension.entitlements     → 三条路线共用（FinderSync 必须 sandbox + AppGroup）
case "$DISTRIBUTION_ROUTE" in
    website-dev|website-release)
        HOST_ENTITLEMENTS="entitlements/website.host.entitlements"
        ;;
    mac-app-store)
        HOST_ENTITLEMENTS="entitlements/mas.host.entitlements"
        ;;
    *)
        echo "❌ [Build] 未识别的 DISTRIBUTION_ROUTE=$DISTRIBUTION_ROUTE，无法定位 host entitlements 模板"
        exit 2
        ;;
esac
EXT_ENTITLEMENTS="entitlements/extension.entitlements"

for f in "$HOST_ENTITLEMENTS" "$EXT_ENTITLEMENTS"; do
    if [ ! -f "$f" ]; then
        echo "❌ [Build] 找不到 entitlements 模板: $f"
        exit 2
    fi
done

cp "$HOST_ENTITLEMENTS" "$BUILD_DIR/Contextory.entitlements"
cp "$EXT_ENTITLEMENTS"  "$BUILD_DIR/ContextoryFinderExtension.entitlements"

echo "🔐 [Build] 自动进行嵌套签名..."
# A. 先签名最内层插件的二进制与整个 XPC 插件 bundle
codesign --force --sign "$CODE_SIGN_IDENTITY" $CODESIGN_RUNTIME_ARGS --entitlements "$BUILD_DIR/ContextoryFinderExtension.entitlements" "$EXT_BUNDLE/Contents/MacOS/ContextoryFinderExtension"
codesign --force --sign "$CODE_SIGN_IDENTITY" $CODESIGN_RUNTIME_ARGS --entitlements "$BUILD_DIR/ContextoryFinderExtension.entitlements" "$EXT_BUNDLE"

# B. 再签名主程序二进制。官网分发路线保持主 App 非沙盒，并在 website-release 下启用 hardened runtime。
# B. 主 App 二进制 + 整个 .app Bundle 都用 host entitlements 模板。
#    历史上这两行都漏了 --entitlements，导致主 App 实际是 adhoc 无 entitlements；
#    本轮 build.sh 重构后必须显式传入，否则 application-groups 不生效，
#    SharedStorageManager 与 FinderSync 之间的 cross-container 物理路径访问会被
#    macOS 15+ Hidden Subsystem Block 拦截。
codesign --force --sign "$CODE_SIGN_IDENTITY" $CODESIGN_RUNTIME_ARGS --entitlements "$BUILD_DIR/Contextory.entitlements" "$APP_BUNDLE/Contents/MacOS/Contextory"
codesign --force --sign "$CODE_SIGN_IDENTITY" $CODESIGN_RUNTIME_ARGS --entitlements "$BUILD_DIR/Contextory.entitlements" "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [ "$DISTRIBUTION_ROUTE" = "website-release" ]; then
    echo "🧾 [Build] 提交 App 到 Apple notary service 并 stapler 附票..."
    NOTARY_ZIP="$BUILD_DIR/Contextory-notary.zip"
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
    submit_for_notarization "$NOTARY_ZIP"
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    rm -f "$NOTARY_ZIP"
fi

# 10. 打包压缩为 Distribution 压缩包与 DMG 磁盘映像
echo "📦 [Build] 正在打包压缩为 distributable .zip 绿色免安装版..."
cd "$BUILD_DIR"
zip -r -q "Contextory.zip" "$APP_NAME.app"
cd ..

echo "📦 [Build] 开始构建 Drag-to-Install DMG 磁盘映像..."
DMG_TEMP_DIR="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# A. 拷贝 App 以及 Applications 快捷方式
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# B. 创建原始可写 DMG (UDRW 格式)
RAW_DMG="$BUILD_DIR/Contextory_raw.dmg"
echo "⚡ [Build] 清理前次 CI 残留的 DMG 挂载..."
hdiutil detach "/Volumes/$VOLUME_NAME" >/dev/null 2>&1 || true
rm -f "$RAW_DMG"
for attempt in 1 2 3; do
    if hdiutil create -volname "$VOLUME_NAME" -srcfolder "$DMG_TEMP_DIR" -ov -format UDRW "$RAW_DMG" >/dev/null 2>&1; then
        break
    fi
    echo "⚠️ [Build] hdiutil create 失败（attempt $attempt/3），重试..."
    sleep 2
done
if [ ! -f "$RAW_DMG" ]; then
    echo "❌ [Build] hdiutil create 三次重试均失败，退出。"
    exit 1
fi

# C. 本机构建时挂载原始 DMG，通过 Finder 写入窗口排版元数据。
# GitHub Actions 没有可交互 Finder 会话，CI 直接保留系统默认布局，避免 AppleScript 超时。
if [ "${CI:-false}" = "true" ]; then
    echo "🎨 [Build] CI 环境跳过 Finder 窗口排版，使用系统默认 DMG 布局。"
else
    echo "🎨 [Build] 静默挂载临时磁盘映像并启动 Finder 视觉排版排布..."
    # 使用 -nobrowse 避免在用户桌面弹出影响体验
    device=$(hdiutil attach -nobrowse -readwrite "$RAW_DMG" | egrep '/Volumes/' | awk '{print $1}')
    sleep 1.5

    osascript <<EOF || echo "⚠️ [Build] Finder UI 排版失败，默认继承系统基础布局。"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set containerWindow to container window
        set current view of containerWindow to icon view
        set toolbar visible of containerWindow to false
        set statusbar visible of containerWindow to false
        -- 设定黄金分辨率大小宽 550, 高 360
        set the bounds of containerWindow to {400, 200, 950, 560}
        set icon size of icon view options of containerWindow to 128
        set arrangement of icon view options of containerWindow to not arranged
        
        -- 对称拖拽排版
        set position of item "$APP_NAME.app" to {150, 180}
        set position of item "Applications" to {400, 180}
        
        delay 1
        close containerWindow
    end tell
end tell
EOF

    sleep 1
    hdiutil detach "$device" >/dev/null || true
    sleep 1
fi

# D. 转换为正式发布版只读高压缩 DMG (UDZO 格式)
FINAL_DMG="$BUILD_DIR/Contextory.dmg"
rm -f "$FINAL_DMG"
echo "⚡ [Build] 正在将原始映像转换为只读高压缩分发级 DMG..."
hdiutil convert "$RAW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

if [ "$DISTRIBUTION_ROUTE" = "website-release" ]; then
    echo "🧾 [Build] 提交 DMG 到 Apple notary service 并 stapler 附票..."
    submit_for_notarization "$FINAL_DMG"
    xcrun stapler staple "$FINAL_DMG"
    xcrun stapler validate "$FINAL_DMG"
fi

# E. 清理临时过渡资源
rm -f "$RAW_DMG"
rm -rf "$DMG_TEMP_DIR"

echo "=============================================================================="
echo "🎉 [Build] 成功！应用已成功编译并完成双格式打包分发。"
echo "📍 宿主应用路径: $APP_BUNDLE"
echo "📦 绿色免安装版: $BUILD_DIR/Contextory.zip"
echo "📀 拖拽式安装版: $BUILD_DIR/Contextory.dmg"
echo "=============================================================================="
