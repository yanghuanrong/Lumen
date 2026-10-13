#!/bin/bash
# 构建 Lumen.app
# 用法：
#   ./build.sh          # release 构建 + 打包
#   ./build.sh debug    # debug 构建 + 打包

set -euo pipefail

CONFIG="${1:-release}"
cd "$(dirname "$0")"

APP_NAME="Lumen"
BUNDLE_ID="com.lumen.translate"
VERSION="0.1.0"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# debug 参数会额外生成 Xcode 工程产物，方便断点调试
if [ "$CONFIG" = "debug" ]; then
    echo "==> 生成 Xcode 工程（调试用）"
    if [ -f Lumen.xcodeproj ]; then
        echo "    已存在 Lumen.xcodeproj，跳过生成"
        echo "    如需重建：rm -rf Lumen.xcodeproj && ruby scripts/generate_xcodeproj.rb"
    else
        if ruby scripts/generate_xcodeproj.rb 2>/dev/null; then
            echo "    ✅ 工程已生成"
        else
            echo "    ⚠️  生成失败（需要 gem install xcodeproj），跳过"
        fi
    fi
    echo ""
fi

echo "==> 编译 (${CONFIG})"
swift build --disable-sandbox -c "${CONFIG}"
BIN_PATH="$(swift build --disable-sandbox -c "${CONFIG}" --show-bin-path)"

echo "==> 打包 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Info.plist
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- 关键：无 Dock 图标，只在菜单栏与浮动面板出现 -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Lumen · 个人划词翻译工具</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# 临时图标（若缺少正式图标则用系统符号生成一个）
if [ ! -f "Resources/AppIcon.icns" ]; then
    mkdir -p Resources
    ICONSET="Resources/AppIcon.iconset"
    rm -rf "${ICONSET}"
    mkdir -p "${ICONSET}"

    # 用SF Symbol 渲染图标为 PNG
    cat > /tmp/lumen_icon.swift <<'SWIFT'
import AppKit
import Foundation

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext
// 圆角背景渐变
let colors = [
    NSColor(srgbRed: 0.24, green: 0.52, blue: 0.98, alpha: 1).cgColor,
    NSColor(srgbRed: 0.42, green: 0.32, blue: 0.92, alpha: 1).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: 1024),
                           end: CGPoint(x: 1024, y: 0),
                           options: [])
}
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
path.addClip()

// 书本符号
let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .regular)
if let symbol = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: NSRect(x: (1024 - tinted.size.width) / 2,
                           y: (1024 - tinted.size.height) / 2,
                           width: tinted.size.width,
                           height: tinted.size.height))
}

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
SWIFT

    if swiftc -O /tmp/lumen_icon.swift -o /tmp/lumen_icon 2>/dev/null; then
        /tmp/lumen_icon "${ICONSET}/icon_512x512@2x.png" 2>/dev/null || true
        if [ -f "${ICONSET}/icon_512x512@2x.png" ]; then
            cp "${ICONSET}/icon_512x512@2x.png" "${ICONSET}/icon_512x512.png"
            for s in 16 32 64 128 256 512; do
                sips -z ${s} ${s} "${ICONSET}/icon_512x512.png" \
                    --out "${ICONSET}/icon_${s}x${s}.png" >/dev/null 2>&1 || true
                d=$((s * 2))
                sips -z ${d} ${d} "${ICONSET}/icon_512x512.png" \
                    --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
            done
            iconutil -c icns "${ICONSET}" -o Resources/AppIcon.icns 2>/dev/null \
                && cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns" \
                || true
        fi
    fi
else
    cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

echo "==> 签名（ad-hoc）"
# 全局快捷键（Carbon HotKey）不需要辅助功能授权，但 ad-hoc 签名可保证 Gatekeeper 放行
codesign --force --sign - --timestamp=none "${APP_DIR}" 2>/dev/null || {
    echo "    签名跳过（不影响本机运行）"
}

echo ""
echo "✅ 构建完成: ${APP_DIR}"
echo ""
echo "运行方式："
echo "  open ${APP_DIR}                # 启动"
echo "  open -a ${APP_DIR} --args     # 启动"
echo ""
echo "安装到「应用程序」："
echo "  cp -R ${APP_DIR} /Applications/"