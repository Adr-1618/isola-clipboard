#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [ ! -d "$sdk_path" ]; then
  sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

test_binary=/private/tmp/isola-clipboard-smoke-tests
module_cache=/private/tmp/isola-clipboard-smoke-module-cache

swiftc \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  -target arm64-apple-macosx14.0 \
  "$project_dir/IsolaClipboard/ClipboardHistory.swift" \
  "$project_dir/IsolaClipboard/SystemIntegration.swift" \
  "$project_dir/Tests/ClipboardHistorySmoke.swift" \
  -o "$test_binary"

"$test_binary"
rm -f "$test_binary"
