#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

xcrun swift-format lint \
    --recursive \
    --strict \
    Package.swift Sources Tests
swift test --parallel
"$repo_root/scripts/build_app.sh" release
