#!/bin/bash
# 編譯並組成 build/RouteManager.app（ad-hoc 簽章）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/RouteManager.app"
# 通用版：同時支援 Apple 晶片（arm64）與 Intel（x86_64），分享給別人才不會挑機器
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/RouteManager"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/RouteManager"
# App 圖示（由 Assets/make-icon.swift 產生，見 README）
cp "Assets/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>RouteManager</string>
  <key>CFBundleIdentifier</key><string>io.github.stanley-122.RouteManager</string>
  <key>CFBundleName</key><string>RouteManager</string>
  <key>CFBundleDisplayName</key><string>路由管理</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign -s - --force "${APP}"
xattr -cr "${APP}"
codesign -v "${APP}" && echo "OK: ${APP}"
