#!/bin/zsh
# Renders the panel, empty state, expanded row, welcome and settings to build/snap/*.png (offscreen, scratch home).
cd "$(dirname "$0")"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
mkdir -p build/snap && cp Tests/Snapshot.swift build/snap/main.swift
swiftc -swift-version 5 -O -sdk $SDK -target arm64-apple-macos26.0 Sources/Engine/*.swift Sources/Model/*.swift Sources/Views/*.swift build/snap/main.swift -o build/snapshot 2>&1 | grep error
SCRATCH=$(mktemp -d)   # a throwaway home, so the run never touches your real preferences
CFFIXED_USER_HOME=$SCRATCH ./build/snapshot build/snap
rm -rf "$SCRATCH"
