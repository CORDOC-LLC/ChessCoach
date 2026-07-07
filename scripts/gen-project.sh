#!/bin/bash
# Generate GemmaChess.xcodeproj from project.yml using XcodeGen.
# Usage: ./scripts/gen-project.sh
set -e
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "!! xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
# Local, untracked signing config (not in git — see local.env.example).
if [ -f local.env ]; then
  set -a; source local.env; set +a
fi
if [ -z "$DEVELOPMENT_TEAM" ]; then
  echo "!! DEVELOPMENT_TEAM not set. Copy local.env.example to local.env and fill in your Apple Developer Team ID." >&2
  exit 1
fi
xcodegen generate
echo "==> Generated GemmaChess.xcodeproj"
