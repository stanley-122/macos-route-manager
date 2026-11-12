#!/bin/bash
# 產出可分享的安裝檔 build/RouteManager-<版本>.dmg
# 內容：RouteManager.app、指向「應用程式」的捷徑、給收件人看的「先讀我.txt」
# 打開 dmg 會看到拖曳安裝畫面（背景圖 Assets/dmg-background.tiff，由 Assets/make-dmg-bg.swift 產生）
# 版面靠 Finder 的 AppleScript 設定，第一次跑時系統可能會問「是否允許控制 Finder」，請按允許。
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP="build/RouteManager.app"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
VOL="路由管理 ${VER}"
DMG="build/RouteManager-${VER}.dmg"
RW="build/RouteManager-rw.dmg"
STAGE="build/dmg-stage"

# 同名磁碟若還掛著（例如之前打開過），先退出，避免名稱衝突
if [ -d "/Volumes/${VOL}" ]; then hdiutil detach "/Volumes/${VOL}" -force >/dev/null; fi

rm -rf "${STAGE}"
mkdir -p "${STAGE}/.background"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/應用程式"
cp "Assets/dmg-background.tiff" "${STAGE}/.background/background.tiff"

cat > "${STAGE}/先讀我.txt" <<'TXT'
路由管理（RouteManager）

用途：用圖形介面管理 macOS 的 IPv4 靜態路由（看路由表、新增／刪除、存常用路由一鍵套用）。
需求：macOS 14 以上，Apple 晶片或 Intel 都可以。

安裝：
1. 把「RouteManager」拖到「應用程式」資料夾。
2. 第一次開啟：這個 App 沒有 Apple 開發者簽章，系統會擋。
   請到「應用程式」對 RouteManager 按右鍵 →「打開」→ 再按「打開」。
   若沒有「打開」選項：到「系統設定 → 隱私權與安全性」往下找到 RouteManager，按「強制打開」。
3. 之後就能正常點兩下開啟。

注意：
- 新增或刪除路由時，系統會跳出管理員授權視窗；送出前會先顯示要執行的完整指令。
- 加的路由是臨時的，重開機就會消失，可以用「已存路由」一鍵重新套用。
- 預設路由、本機網段等系統路由刻意鎖住不能刪。
TXT

# 1) 先做可寫的映像，掛起來讓 Finder 排版
rm -f "${RW}" "${DMG}"
hdiutil create -volname "${VOL}" -srcfolder "${STAGE}" -ov -format UDRW "${RW}" >/dev/null
hdiutil attach "${RW}" -readwrite -noautoopen >/dev/null

# 2) Finder 排版：視窗 600x400、圖示 96、背景圖、三個項目的位置（要和背景圖對齊）
osascript <<OSA
tell application "Finder"
  -- 剛掛上時 Finder 可能還沒認到，最多等 15 秒
  repeat 30 times
    if exists disk "${VOL}" then exit repeat
    delay 0.5
  end repeat
  tell disk "${VOL}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "RouteManager.app" of container window to {150, 190}
    set position of item "應用程式" of container window to {450, 190}
    set position of item "先讀我.txt" of container window to {300, 270}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/${VOL}" >/dev/null

# 3) 轉成壓縮唯讀版本，清掉暫存
hdiutil convert "${RW}" -format UDZO -o "${DMG}" >/dev/null
rm -f "${RW}"
rm -rf "${STAGE}"
xattr -c "${DMG}"
hdiutil verify "${DMG}" >/dev/null && echo "OK: ${DMG}"
