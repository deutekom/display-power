#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.1}"
APP="DisplayPower"
BUILD=".build/release"
DMG="${APP}-v${VERSION}.dmg"
BUNDLE="${APP}.app"
RESOURCES="Sources/DisplayPower/Resources"
STAGING="$(mktemp -d)"

echo "→ swift build -c release"
swift build -c release

echo "→ App-Bundle zusammenstellen"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
cp "${BUILD}/${APP}" "${BUNDLE}/Contents/MacOS/"
cp -R "${BUILD}/${APP}_${APP}.bundle" "${BUNDLE}/Contents/Resources/"
cp "${RESOURCES}/AppIcon.icns" "${BUNDLE}/Contents/Resources/"

cat > "${BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>DisplayPower</string>
    <key>CFBundleDisplayName</key>       <string>DisplayPower</string>
    <key>CFBundleIdentifier</key>        <string>com.user.displaypower</string>
    <key>CFBundleVersion</key>           <string>VERSION_PLACEHOLDER</string>
    <key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
    <key>CFBundleExecutable</key>        <string>DisplayPower</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST
sed -i '' "s/VERSION_PLACEHOLDER/${VERSION}/g" "${BUNDLE}/Contents/Info.plist"

echo "→ DMG erstellen: ${DMG}"
cp -R "${BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "${APP}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG}"

rm -rf "${STAGING}" "${BUNDLE}"
echo "✓ ${DMG} erstellt"
