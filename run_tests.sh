#!/bin/zsh
# Compiles every source except the @main App file plus one test, and runs it. Usage: ./run_tests.sh VisibilityTest
cd "$(dirname "$0")"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
T=${1:-VisibilityTest}
mkdir -p build/tests && cp Tests/$T.swift build/tests/main.swift
swiftc -swift-version 5 -O -sdk $SDK -target arm64-apple-macos26.0 Sources/Engine/*.swift Sources/Model/*.swift build/tests/main.swift -o build/tests/$T 2>&1 | grep -E "error"
./build/tests/$T "${@:2}"
