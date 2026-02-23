#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.derived}"
CONFIGURATION="${CONFIGURATION:-Debug}"

"$SCRIPT_DIR/gen.sh"

cd "$REPO_ROOT"
xcodebuild \
  -project "$REPO_ROOT/Lunardisk.xcodeproj" \
  -scheme Lunardisk \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

