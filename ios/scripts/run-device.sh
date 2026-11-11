#!/usr/bin/env bash
# Build, install and launch TextWallpaper on the paired iPhone.
set -euo pipefail
DEVICE=00008130-001665811E38001C
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project TextWallpaper.xcodeproj -scheme TextWallpaper -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Debug-iphoneos/TextWallpaper.app
xcrun devicectl device process launch --device "$DEVICE" me.byeolki.textwallpaper
