#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/work/DerivedData"

xcodebuild \
  -project "$ROOT/louddd!.xcodeproj" \
  -scheme "louddd!" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Debug/louddd!.app"
open "$APP"
