#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.derived}"

"$SCRIPT_DIR/gen.sh"

cd "$REPO_ROOT"
xcodebuild \
  -project "$REPO_ROOT/Lunardisk.xcodeproj" \
  -scheme Lunardisk \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test

swift test --package-path "$REPO_ROOT/Modules/CoreScan"
swift test --package-path "$REPO_ROOT/Modules/Visualization"
swift test --package-path "$REPO_ROOT/Modules/LunardiskAI"

