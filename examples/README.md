# Examples

This repository includes an isolated examples workspace:

- `examples/lib`: Swift package with demo UIKit/SwiftUI screen modules and snapshot test targets.
- `examples/app`: Xcode app project (generated with XcodeGen) with separate UIKit and SwiftUI apps.

## Generate Example Apps Project

```bash
cd examples/app
./Scripts/generate_project.sh
```

## Run Package Snapshot Tests

From Xcode:
1. Open `examples/lib/Package.swift`.
2. Run test target `UIKitSnapshotsTests` (UIKit variant).
3. Run test target `SwiftUISnapshotsTests` (SwiftUI variant).

From CLI (iOS simulator):

```bash
xcodebuild test \
  -scheme UIKitSnapshotsTests \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -packagePath examples/lib

xcodebuild test \
  -scheme SwiftUISnapshotsTests \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -packagePath examples/lib
```

## Run App Project Test Plans

After generating `examples/app/SnapshotExamplesApps.xcodeproj`, run:

```bash
SNAPSHOT_REPORT_OUTPUT_DIR=.artifacts/snapshot-runs-pass xcodebuild test \
  -project examples/app/SnapshotExamplesApps.xcodeproj \
  -scheme UIKitExampleApp \
  -testPlan UIKitSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -resultBundlePath .artifacts/xcresult/UIKitSnapshots-pass.xcresult

SNAPSHOT_REPORT_OUTPUT_DIR=.artifacts/snapshot-runs-pass xcodebuild test \
  -project examples/app/SnapshotExamplesApps.xcodeproj \
  -scheme SwiftUIExampleApp \
  -testPlan SwiftUISnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -resultBundlePath .artifacts/xcresult/SwiftUISnapshots-pass.xcresult
```

Generate the final report from runtime JSON outputs (no DerivedData lookup):

```bash
swift run snapshot-report \
  --input-dir .artifacts/snapshot-runs-pass \
  --format json,html \
  --output .artifacts/review-report-pass
```

Or run everything in one step:

```bash
./examples/app/Scripts/run_pass_report.sh
```
