#!/bin/bash
# Builds "dist/Read my Script.app" (universal, ad-hoc signed) and "dist/ReadMyScript-<release>.zip" (+ .sig) for the updater.
# Usage: scripts/build-app.sh   – release: bump VERSION/RELEASE/BUILD; tag v<RELEASE>, upload zip and .sig.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.2.0          # CFBundleShortVersionString (numbers only)
RELEASE=0.2.0          # tag and zip name, may be "0.2.0-beta.1"
BUILD=2
APP="dist/Read my Script.app"

swift build -c release --arch arm64 --product ReadMyScript
swift build -c release --arch x86_64 --product ReadMyScript
mkdir -p .build/universal
lipo -create .build/arm64-apple-macosx/release/ReadMyScript .build/x86_64-apple-macosx/release/ReadMyScript \
  -output .build/universal/ReadMyScript

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/universal/ReadMyScript "$APP/Contents/MacOS/"
cp -R Resources/fonts "$APP/Contents/Resources/"
cp Resources/icon/AppIcon.icns "$APP/Contents/Resources/"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
cp -R Resources/help "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Read my Script</string>
  <key>CFBundleDisplayName</key><string>Read my Script</string>
  <key>CFBundleExecutable</key><string>ReadMyScript</string>
  <key>CFBundleIdentifier</key><string>io.github.moritz-poth.readmyscript</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>ReadMyScriptRelease</key><string>$RELEASE</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Moritz Poth</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string><string>fr</string><string>es</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>PDF</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
  </dict></array>
</dict>
</plist>
PLIST
# ad-hoc signed (no Apple Developer account): macOS needs "Open Anyway" once, see README
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"
# grep -c reads to the end (grep -q would close the pipe early and fail the pipeline under pipefail)
strings "$APP/Contents/MacOS/ReadMyScript" | grep -c "readmyscript/releases" >/dev/null || { echo "stale binary?" >&2; exit 1; }

# old zip and signature go first: a run that fails later never leaves a new zip next to an old .sig
ZIP="dist/ReadMyScript-$RELEASE.zip"
rm -f "$ZIP" "$ZIP.sig"
ditto -c -k --keepParent "$APP" "$ZIP"
# update signature: installed apps only accept zips signed with the key in this Mac's Keychain
if PUB=$(swift scripts/update-key.swift public 2>/dev/null) && grep -q "\"$PUB\"" Sources/ReadMyScript/Updater.swift \
   && swift scripts/update-key.swift sign "$ZIP"; then
  echo "Done: $APP, $ZIP (+ .sig – upload both)"
else
  echo "Done: $APP, $ZIP – NOT SIGNED (no update key, or it differs from Updater.publicKey): not releasable" >&2
fi
