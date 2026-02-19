# SnapshotReportKit

Swift Package toolchain to build modern static reports for [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing).

Current version: `0.2.0`

It provides:

- JSON report output.
- JUnit XML output with attachment entries.
- HTML output (stitch-inspired look) with pass/fail/skip status and attachment preview.
- Aggregation of multiple test runs into one report.
- Custom HTML template support via Stencil.
- Reporter protocol architecture (`SnapshotReporter`) with one implementation per format.
- Swift 6 concurrency-ready APIs (`Sendable`, actor-based runtime components).
- Swift Testing-based package tests.
- XCTest + Swift Testing-compatible assertion surface.
- Device/runtime compatibility validation for snapshot presets.
- Auto-record behavior when reference assets do not exist (configurable).
- Advanced image diff attachments on failures.
- Per-run output directory support for test plan/package aggregation (`SNAPSHOT_REPORT_OUTPUT_DIR`, `--input-dir`).

## Reporter Architecture

All reporters conform to `SnapshotReporter` and are implemented in separate files:

- `Sources/SnapshotReportCore/Reporters/JSON/JSONSnapshotReporter.swift`
- `Sources/SnapshotReportCore/Reporters/JUnit/JUnitSnapshotReporter.swift`
- `Sources/SnapshotReportCore/Reporters/HTML/HTMLSnapshotReporter.swift`

Dispatcher:

- `Sources/SnapshotReportCore/Reporting/ReportWriters.swift`

Protocol:

- `Sources/SnapshotReportCore/Reporting/SnapshotReporter.swift`

## DocC (Common Model)

Common report model documentation is provided in DocC format:

- `Sources/SnapshotReportCore/Documentation.docc/SnapshotReportCore.md`
- `Sources/SnapshotReportCore/Documentation.docc/CommonModel.md`

## Install / Build

```bash
swift build
```

## CLI Usage

```bash
swift run snapshot-report \
  --input .artifacts/run-1.json \
  --input .artifacts/run-2.json \
  --format json,junit,html \
  --output .artifacts/report \
  --name "iOS Snapshot Regression"
```

Optional custom HTML template:

```bash
swift run snapshot-report \
  --input .artifacts/run.json \
  --format html \
  --output .artifacts/report \
  --html-template ./my-report.stencil

# Aggregate every JSON run produced by app + local packages (e.g. from test plan)
swift run snapshot-report \
  --input-dir .artifacts/snapshot-runs \
  --format json,junit,html \
  --output .artifacts/report
```

Outputs:

- `.artifacts/report/report.json`
- `.artifacts/report/report.junit.xml`
- `.artifacts/report/html/index.html`
- `.artifacts/report/html/attachments/*`

## Input JSON Schema

Each `--input` file is a `SnapshotReport` JSON document.

```json
{
  "name": "Snapshot Tests",
  "generatedAt": "2026-02-19T20:00:00Z",
  "metadata": {
    "platform": "iOS",
    "device": "iPhone 16"
  },
  "suites": [
    {
      "name": "CheckoutSnapshots",
      "tests": [
        {
          "id": "F15A36E7-4ADE-4D46-8159-8DE96813F08A",
          "name": "testCheckoutCard",
          "className": "CheckoutSnapshotsTests",
          "status": "failed",
          "duration": 0.152,
          "failure": {
            "message": "Snapshot mismatch",
            "file": "/path/to/CheckoutSnapshotsTests.swift",
            "line": 44,
            "diff": "Pixel mismatch around CTA area"
          },
          "attachments": [
            {
              "name": "Reference",
              "type": "png",
              "path": "/absolute/path/reference.png"
            },
            {
              "name": "Diff dump",
              "type": "dump",
              "path": "/absolute/path/failure.txt"
            }
          ]
        }
      ]
    }
  ]
}
```

Attachment `type` values:

- `png`: previewed inline in HTML.
- `dump` or `text`: rendered as text block in HTML.
- `binary`: linked for download.

## Integration With SnapshotTesting

Use the included collector to record test outcomes from your test target and emit input JSON:

```swift
import SnapshotReportCore

let collector = SnapshotReportCollector(reportName: "UI Snapshots")

await collector.recordFailure(
  suite: "CheckoutSnapshots",
  test: "testCheckoutCard",
  className: "CheckoutSnapshotsTests",
  duration: 0.152,
  message: "Snapshot mismatch",
  file: #filePath,
  line: #line,
  diff: "Pixel mismatch around CTA area",
  attachments: [
    .init(name: "Reference", type: .png, path: "/tmp/reference.png"),
    .init(name: "Diff", type: .dump, path: "/tmp/diff.txt")
  ]
)

try await collector.writeJSON(to: URL(fileURLWithPath: ".artifacts/run-ios.json"))
```

Then aggregate multiple runs:

```bash
swift run snapshot-report \
  --input .artifacts/run-ios.json \
  --input .artifacts/run-macos.json \
  --output .artifacts/report
```

## SnapshotTesting Extension (Automatic Reports)

`SnapshotReportSnapshotTesting` extends [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) with:

- Report-aware assertions
- Automatic JSON run report generation at test bundle end
- Multi-appearance snapshot assert (`light` + `dark` by default)
- Optional high contrast variants (`highContrastLight`, `highContrastDark`)
- Device preset validation against runtime iOS major version
- Advanced image diff attachment generation on image mismatches

### Add To Xcode

1. Add this package to your Xcode project.
2. Link your test target with:
   - `SnapshotTesting`
   - `SnapshotReportSnapshotTesting`
3. (Optional) add env vars in your test scheme:
   - `SNAPSHOT_REPORT_OUTPUT_DIR=.artifacts/snapshot-runs`
   - `SNAPSHOT_REPORT_NAME=My App Snapshot Tests`

### Usage In Tests

```swift
import XCTest
import SnapshotTesting
import SnapshotReportSnapshotTesting

final class LoginSnapshotsTests: XCTestCase {
  override func setUp() {
    super.setUp()
    configureSnapshotReport(
      reportName: "iOS Snapshot Tests",
      outputJSONPath: ".artifacts/snapshot-run.json",
      metadata: ["platform": "iOS", "suite": "Login"]
    )
  }

  func test_login_screen() {
    // Default: light + dark snapshots from a single assert.
    assertSnapshot(
      of: LoginViewController(),
      device: .iPhoneSe
    )
  }

  func test_login_screen_all_contrasts() {
    assertSnapshot(
      of: LoginViewController(),
      device: .iPhoneSe,
      appearances: SnapshotAppearanceConfiguration.all
    )
  }
}
```

`assertSnapshot` configuration highlights:

- `device`: validates compatibility against current iOS major version (can override with `osMajorVersion`).
- `missingReferencePolicy`: defaults to `.recordOnMissingReference` (auto-record if asset is missing).
- `diffing`: defaults to `CoreImageDifferenceDiffing()` and attaches an advanced diff PNG on failures.

### Custom Snapshotting Strategies

You can still use any SnapshotTesting strategy and record it in the report:

```swift
assertReportingSnapshot(
  of: value,
  as: .json
)
```

### Generate Final HTML/JUnit/JSON

After tests generate one or more run JSON files:

```bash
swift run snapshot-report \
  --input .artifacts/snapshot-run.json \
  --output .artifacts/report \
  --format json,junit,html
```

## HTML Template Customization (Stencil)

Default template is bundled at:

- `Sources/SnapshotReportCore/Resources/default-report.stencil`

You can override with `--html-template` and use these context keys:

- `report.name`
- `report.generatedAt`
- `report.summary.total|passed|failed|skipped|duration`
- `suites[]`
- `suite.tests[]`
- `test.status`, `test.name`, `test.className`, `test.duration`
- `test.failure.message|file|line|diff`
- `test.attachments[].name|type|path|content`
