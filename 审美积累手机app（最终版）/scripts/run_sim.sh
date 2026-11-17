#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."

UDID=$(xcrun simctl list devices available | grep "iPhone 16 (" | head -1 | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
EXEC=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/AestheticApp" -type f 2>/dev/null | head -1)
APP_DIR="build/AestheticApp.app"

if [ -z "$EXEC" ]; then
    echo "未找到编译产物，先执行 xcodebuild build"
    exit 1
fi

echo "▶ 组装 .app（$EXEC）"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp "$EXEC" "$APP_DIR/AestheticApp"
cat > "$APP_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>AestheticApp</string>
    <key>CFBundleIdentifier</key><string>com.local.AestheticApp</string>
    <key>CFBundleName</key><string>审美积累</string>
    <key>CFBundleDisplayName</key><string>审美积累</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>MinimumOSVersion</key><string>17.0</string>
    <key>UILaunchScreen</key><dict/>
    <key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
    <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
    <key>NSCameraUsageDescription</key><string>用于拍摄并保存你的审美灵感图片</string>
    <key>NSPhotoLibraryUsageDescription</key><string>用于选择你相册里的图片</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>用于把语音转成文字，记录你的审美笔记</string>
    <key>NSMicrophoneUsageDescription</key><string>用于语音输入审美笔记</string>
</dict>
</plist>
PLIST

echo "▶ 安装到模拟器 $UDID"
xcrun simctl install "$UDID" "$APP_DIR"
xcrun simctl terminate "$UDID" com.local.AestheticApp 2>/dev/null || true
echo "▶ 启动"
xcrun simctl launch "$UDID" com.local.AestheticApp
