#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen --spec project.yml

echo "Generated examples/app/SnapshotExamplesApps.xcodeproj"
