#!/bin/bash
# Generate GemmaChess.xcodeproj from project.yml using XcodeGen.
# Usage: ./scripts/gen-project.sh
set -e
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "!! xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
xcodegen generate
echo "==> Generated GemmaChess.xcodeproj"
