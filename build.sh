#!/bin/zsh
# Builds Levels.app next to this script with the Command Line Tools (no Xcode needed), ad-hoc signed.
set -e
cd "$(dirname "$0")"
APP=build/Levels.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk   # SDK 27 turns @State into a macro whose plugin only ships with Xcode
swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK" -target arm64-apple-macos26.0 \
  -o "$APP/Contents/MacOS/Levels" Sources/*/*.swift
cp Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Sign to the app's identity, not to this build's hash: macOS keeps the audio permission across rebuilds.
codesign --force --sign - -r='designated => identifier "com.nurik.levels"' "$APP"
echo "Built $APP"
