#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build"
swift build

echo "==> swift test"
swift test --parallel

echo "==> swift format lint"
if command -v swift-format >/dev/null 2>&1; then
    swift-format lint --recursive Sources Tests
else
    echo "swift-format not installed, skipping lint"
fi

echo "All checks passed."
