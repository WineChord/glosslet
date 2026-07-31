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
notary_profile="${GLOSSLET_NOTARY_PROFILE:-}"

if [[ -n "$notary_profile" ]]; then
    if [[ "${GLOSSLET_CODESIGN_IDENTITY:--}" == "-" ]]; then
        echo \
            "GLOSSLET_NOTARY_PROFILE requires GLOSSLET_CODESIGN_IDENTITY." \
            >&2
        exit 1
    fi
    notarization_archive="$repo_root/dist/.Glosslet-$version-notarization.zip"
    rm -f "$notarization_archive"
    ditto -c -k --sequesterRsrc --keepParent \
        "$app_path" \
        "$notarization_archive"
    xcrun notarytool submit \
        "$notarization_archive" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    rm -f "$notarization_archive"
fi

rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
(
    cd "$repo_root/dist"
    shasum -a 256 "$(basename "$archive_path")" \
        > "$(basename "$archive_path").sha256"
)

echo "$archive_path"
