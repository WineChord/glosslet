#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$repo_root/Packaging/Info.plist"
)"
app_path="$("$repo_root/scripts/build_app.sh" release | tail -n 1)"
archive_path="$repo_root/dist/Glosslet-$version-macos.zip"

rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
shasum -a 256 "$archive_path" > "$archive_path.sha256"

echo "$archive_path"
