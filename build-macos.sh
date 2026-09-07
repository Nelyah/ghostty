#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

nix develop --command bash -euo pipefail -c '
  zig build -Doptimize=ReleaseFast -Demit-macos-app=false
  nu macos/build.nu --configuration ReleaseLocal
'

open macos/build/ReleaseLocal/Ghostty.app
