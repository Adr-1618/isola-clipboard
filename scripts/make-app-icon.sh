#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
resources_dir="$project_dir/IsolaClipboard/Resources"
iconset_dir=/private/tmp/IsolaClipboard.iconset
source_png=/private/tmp/IsolaClipboard-icon-1024.png
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [ ! -d "$sdk_path" ]; then
  sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$resources_dir"
rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"
swift -sdk "$sdk_path" -module-cache-path /private/tmp/isola-icon-module-cache \
  "$project_dir/scripts/GenerateAppIcon.swift" "$source_png"

make_icon() {
  source_size=$1
  name=$2
  sips -z "$source_size" "$source_size" "$source_png" --out "$iconset_dir/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

python3 -c 'import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
parts = []
for code, filename in (("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")):
    data = (root / filename).read_bytes()
    parts.append(code.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
body = b"".join(parts)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)' "$iconset_dir" "$resources_dir/AppIcon.icns"
echo "Created $resources_dir/AppIcon.icns"
