#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/build"
app_path="$build_dir/IsolaClipboard.app"
work_app=/private/tmp/IsolaClipboard-v03-build.app
binary=/private/tmp/IsolaClipboard-v03-binary
module_cache=/private/tmp/isola-clipboard-v03-module-cache
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk

if [ ! -d "$sdk_path" ]; then
  sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$build_dir"
if [ ! -f "$project_dir/IsolaClipboard/Resources/AppIcon.icns" ]; then
  sh "$project_dir/scripts/make-app-icon.sh"
fi

swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ServiceManagement \
  "$project_dir/IsolaClipboard/IsolaClipboardMain.swift" \
  "$project_dir/IsolaClipboard/AppDelegate.swift" \
  "$project_dir/IsolaClipboard/ClipboardHistory.swift" \
  "$project_dir/IsolaClipboard/SystemIntegration.swift" \
  -o "$binary"

rm -rf "$work_app"
mkdir -p "$work_app/Contents/MacOS" "$work_app/Contents/Resources"
cp "$binary" "$work_app/Contents/MacOS/IsolaClipboard"
cp "$project_dir/IsolaClipboard/Info.plist" "$work_app/Contents/Info.plist"
cp "$project_dir/IsolaClipboard/Resources/AppIcon.icns" "$work_app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$work_app/Contents/PkgInfo"
codesign --force --deep --sign - "$work_app"
codesign --verify --deep --strict "$work_app"

if [ -d "$app_path" ]; then
  archive_dir="$build_dir/previous-builds"
  mkdir -p "$archive_dir"
  previous_path="$build_dir/IsolaClipboard.app.previous-$(date +%Y%m%d-%H%M%S)"
  previous_path="$archive_dir/$(basename "$previous_path")"
  mv "$app_path" "$previous_path"
fi
ditto "$work_app" "$app_path"
codesign --verify --deep --strict "$app_path"
plutil -lint "$app_path/Contents/Info.plist"
echo "Built $app_path"
