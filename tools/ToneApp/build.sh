#!/bin/zsh
# Builds build/ToneApp.app: a tiny regular app that plays a steady 440 Hz tone, for the audio tests.
set -e
cd "$(dirname "$0")/../.."
APP=build/ToneApp.app
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -O -sdk "$SDK" -target arm64-apple-macos26.0 tools/ToneApp/main.swift -o "$APP/Contents/MacOS/ToneApp"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>ToneApp</string><key>CFBundleIdentifier</key><string>com.test.toneapp</string><key>CFBundleExecutable</key><string>ToneApp</string><key>CFBundlePackageType</key><string>APPL</string><key>LSBackgroundOnly</key><false/></dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP (it plays a tone when run; run_tests.sh ModelTest build/ToneApp.app uses it)"
