#!/usr/bin/env bash
set -euo pipefail

if [[ "${SKIP_XTOOL_PROBE:-0}" != "1" ]]; then
  command -v xtool >/dev/null || {
    echo 'xtool is required. Install it from https://github.com/xtool-org/xtool.' >&2
    exit 1
  }
  xtool --help | head -n 3
fi

swift test --package-path simple_live_tvos_core --parallel
