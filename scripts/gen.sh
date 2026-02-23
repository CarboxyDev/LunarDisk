#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cd "$REPO_ROOT"
xcodegen generate
echo "Generated Lunardisk.xcodeproj"

