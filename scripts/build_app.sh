#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-release}"
output_root="$repo_root/dist"
app_path="$output_root/Glosslet.app"
contents_path="$app_path/Contents"

cd "$repo_root"
build_arguments=(
    --configuration "$configuration"
    --arch arm64
    --arch x86_64
)
swift build "${build_arguments[@]}" --product Glosslet
binary_root="$(swift build "${build_arguments[@]}" --show-bin-path)"

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_root/Glosslet" "$contents_path/MacOS/Glosslet"
cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Assets/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"

codesign \
    --force \
    --deep \
    --sign - \
    --identifier com.winechord.glosslet \
    "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
plutil -lint "$contents_path/Info.plist"

echo "$app_path"
