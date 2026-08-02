#!/usr/bin/env bash

set -euo pipefail

lookback="${1:-15m}"

/usr/bin/log show \
    --info \
    --style compact \
    --last "$lookback" \
    --predicate \
    'subsystem == "com.winechord.glosslet" AND (category == "CodexLatency" OR category == "CodexLifecycle")'
