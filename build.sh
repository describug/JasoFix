#!/bin/bash
# JasoFix.app 빌드 스크립트 (Xcode 프로젝트 없이 swiftc로 빌드)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/JasoFix.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -o "$APP/Contents/MacOS/JasoFix" Sources/JasoFix/*.swift
codesign --force --sign - "$APP"

echo "빌드 완료: $APP"
