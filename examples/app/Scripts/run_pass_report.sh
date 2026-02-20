#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/examples/app/SnapshotExamplesApps.xcodeproj"
ARTIFACTS_DIR="$ROOT_DIR/.artifacts"
RUNS_DIR="$ARTIFACTS_DIR/snapshot-runs-pass"
XCRESULT_DIR="$ARTIFACTS_DIR/xcresult"
REPORT_DIR="$ARTIFACTS_DIR/review-report-pass"
DESTINATION="${SNAPSHOT_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.5}"

mkdir -p "$ARTIFACTS_DIR" "$RUNS_DIR" "$XCRESULT_DIR" "$REPORT_DIR"

UIKIT_XCRESULT="$XCRESULT_DIR/UIKitSnapshots-pass.xcresult"
SWIFTUI_XCRESULT="$XCRESULT_DIR/SwiftUISnapshots-pass.xcresult"

rm -rf "$UIKIT_XCRESULT" "$SWIFTUI_XCRESULT"

if [[ ! -d "$PROJECT_PATH" ]]; then
  "$ROOT_DIR/examples/app/Scripts/generate_project.sh"
fi

echo "Running UIKit snapshots..."
SNAPSHOT_REPORT_OUTPUT_DIR="$RUNS_DIR" xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme UIKitExampleApp \
  -testPlan UIKitSnapshots \
  -destination "$DESTINATION" \
  -resultBundlePath "$UIKIT_XCRESULT"

echo "Running SwiftUI snapshots..."
SNAPSHOT_REPORT_OUTPUT_DIR="$RUNS_DIR" xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme SwiftUIExampleApp \
  -testPlan SwiftUISnapshots \
  -destination "$DESTINATION" \
  -resultBundlePath "$SWIFTUI_XCRESULT"

echo "Generating report from runtime JSON outputs..."
swift run snapshot-report \
  --input-dir "$RUNS_DIR" \
  --format json,html \
  --output "$REPORT_DIR" \
  --name "UIKit + SwiftUI Recorded Pass"

echo "Done."
echo "xcresult bundles: $XCRESULT_DIR"
echo "Report: $REPORT_DIR/html/index.html"
