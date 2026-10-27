#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_dir="$project_dir/release"
release_app="$release_dir/Isola Clipboard.app"
staging_app=/private/tmp/IsolaClipboard-v1.0-release.app

sh "$project_dir/scripts/make-app-icon.sh"
sh "$project_dir/scripts/build-app.sh"
sh "$project_dir/scripts/run-smoke-tests.sh"

rm -rf "$staging_app"
ditto "$project_dir/build/IsolaClipboard.app" "$staging_app"
codesign --force --deep --sign - "$staging_app"
codesign --verify --deep --strict "$staging_app"
plutil -lint "$staging_app/Contents/Info.plist"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staging_app/Contents/Info.plist")
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staging_app/Contents/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$staging_app/Contents/Info.plist")
[ "$version" = "1.0.0" ] || { echo "Unexpected version: $version" >&2; exit 1; }
[ "$bundle_id" = "it.lucazucconi.IsolaClipboard" ] || { echo "Unexpected bundle ID: $bundle_id" >&2; exit 1; }
[ -s "$staging_app/Contents/Resources/AppIcon.icns" ] || { echo "Missing app icon" >&2; exit 1; }
file "$staging_app/Contents/MacOS/$executable" | grep -q 'arm64' || { echo "Release executable is not ARM64" >&2; exit 1; }

mkdir -p "$release_dir"
if [ -d "$release_app" ]; then
  archive_dir="$release_dir/previous-releases"
  mkdir -p "$archive_dir"
  mv "$release_app" "$archive_dir/Isola Clipboard.app.previous-$(date +%Y%m%d-%H%M%S)"
fi
ditto "$staging_app" "$release_app"
codesign --verify --deep --strict "$release_app"
echo "Packaged $release_app"
