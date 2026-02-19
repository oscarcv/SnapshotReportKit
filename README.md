# SnapshotReportKit

Swift Package toolchain to build modern static reports for [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing).

Current version: `0.3.0`

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
- Advanced image diff attachments on failures (CoreImage).
- Per-run output directory support for test plan/package aggregation (`SNAPSHOT_REPORT_OUTPUT_DIR`, `--input-dir`).
- **xcresult input** — ingest `.xcresult` bundles from `xcodebuild test` directly (`--xcresult`).
- **odiff integration** — SIMD-accelerated pixel diff images via the [`odiff`](https://github.com/dmtrKovalenko/odiff) binary, run automatically after merge (`--odiff`).
- **Design reference links** — optional `referenceURL` per test case, rendered as a button in the HTML report (Zeplin, Figma, or any URL).
- **Xcode project inspection** — `inspect` subcommand to detect snapshot targets and generate CI configuration.

## Reporter Architecture

All reporters conform to `SnapshotReporter` and are implemented in separate files:

- `Sources/SnapshotReportCore/Reporters/JSON/JSONSnapshotReporter.swift`
- `Sources/SnapshotReportCore/Reporters/JUnit/JUnitSnapshotReporter.swift`
- `Sources/SnapshotReportCore/Reporters/HTML/HTMLSnapshotReporter.swift`

Dispatcher:

- `Sources/SnapshotReportCore/Reporting/ReportWriters.swift`

Protocol:

- `Sources/SnapshotReportCore/Reporting/SnapshotReporter.swift`

## Install / Build

```bash
swift build
```

## CLI Usage

### Basic report generation

```bash
swift run snapshot-report \
  --input .artifacts/run-1.json \
  --input .artifacts/run-2.json \
  --format json,junit,html \
  --output .artifacts/report \
  --name "iOS Snapshot Regression"
```

### Aggregate a whole directory

```bash
swift run snapshot-report \
  --input-dir .artifacts/snapshot-runs \
  --format json,junit,html \
  --output .artifacts/report
```

### Ingest an xcresult bundle directly

No custom assertion layer needed — point at the `.xcresult` produced by `xcodebuild test`:

```bash
swift run snapshot-report \
  --xcresult DerivedData/MyApp.xcresult \
  --format json,junit,html \
  --output .artifacts/report
```

Mix JSON runs and xcresult bundles freely:

```bash
swift run snapshot-report \
  --xcresult DerivedData/MyApp.xcresult \
  --input .artifacts/extra-run.json \
  --output .artifacts/report
```

### odiff pixel diff

[odiff](https://github.com/dmtrKovalenko/odiff) is a SIMD-accelerated image diff tool that produces highlighted difference images. Install it first:

```bash
brew install dmtrKovalenko/tap/odiff
```

odiff runs automatically if it is found on PATH. To specify the binary path explicitly:

```bash
swift run snapshot-report \
  --input-dir .artifacts/snapshot-runs \
  --odiff /usr/local/bin/odiff \
  --output .artifacts/report
```

For each failed test that has both a reference (`"Snapshot"`) and an actual (`"Actual Snapshot"`) attachment, an `"odiff"` diff image is appended and displayed in the HTML report.

### Custom HTML template

```bash
swift run snapshot-report \
  --input .artifacts/run.json \
  --format html \
  --output .artifacts/report \
  --html-template ./my-report.stencil
```

Outputs:

- `.artifacts/report/report.json`
- `.artifacts/report/report.junit.xml`
- `.artifacts/report/html/index.html`
- `.artifacts/report/html/attachments/*`

## Xcode Project Inspection

The `inspect` subcommand scans a `.xcodeproj` to detect snapshot test targets and output recommended configuration.

```bash
swift run snapshot-report inspect --project MyApp.xcodeproj
```

With a GitLab CI scheduled-pipeline snippet:

```bash
swift run snapshot-report inspect --project MyApp.xcodeproj --gitlab
```

Example output:

```
=== SnapshotReportKit Inspection: MyApp.xcodeproj ===

Snapshot testing targets detected:
  • MyAppSnapshotTests

Recommended environment variables to set in each scheme's test action:
  SNAPSHOT_REPORT_OUTPUT_DIR = $(SRCROOT)/.artifacts/snapshot-runs
  SRCROOT                    = $(SRCROOT)
  SCHEME_NAME                = <your scheme name>
  GIT_BRANCH                 = $(GIT_BRANCH)
  TEST_PLAN_NAME             = <your test plan name>

Add this call at the start of each snapshot test suite's setUp():
  configureSnapshotReport(reportName: "<TargetName> Snapshots")

# === Suggested .gitlab-ci.yml snippet for scheduled snapshot runs ===

snapshot-tests:
  stage: test
  script:
    - xcodebuild test -project MyApp.xcodeproj -scheme MyApp ...
  artifacts:
    paths:
      - .artifacts/snapshot-runs/
      - .artifacts/snapshot-report/
    reports:
      junit: .artifacts/snapshot-report/report.junit.xml
  only:
    - schedules
```

## Input JSON Schema

Each `--input` file is a `SnapshotReport` JSON document.

```json
{
  "name": "Snapshot Tests",
  "generatedAt": "2026-02-20T10:00:00Z",
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
          "referenceURL": "https://app.zeplin.io/project/abc/screen/123",
          "failure": {
            "message": "Snapshot mismatch",
            "file": "/path/to/CheckoutSnapshotsTests.swift",
            "line": 44,
            "diff": "Pixel mismatch around CTA area"
          },
          "attachments": [
            {
              "name": "Snapshot",
              "type": "png",
              "path": "/absolute/path/reference.png"
            },
            {
              "name": "Actual Snapshot",
              "type": "png",
              "path": "/absolute/path/actual.png"
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

`referenceURL` is optional. When present it renders a "View Reference" link in the HTML report.

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
    .init(name: "Snapshot", type: .png, path: "/tmp/reference.png"),
    .init(name: "Diff", type: .dump, path: "/tmp/diff.txt")
  ],
  referenceURL: "https://app.zeplin.io/project/abc/screen/123"
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
- Advanced image diff attachment generation on image mismatches (CoreImage)
- Actual snapshot attachment for odiff post-processing
- Optional `referenceURL` per assertion (Zeplin, Figma, or any design link)

### Add To Xcode

1. Add this package to your Xcode project.
2. Link your test target with:
   - `SnapshotTesting`
   - `SnapshotReportSnapshotTesting`
3. (Optional) add env vars in your test scheme:
   - `SNAPSHOT_REPORT_OUTPUT_DIR=.artifacts/snapshot-runs`
   - `SNAPSHOT_REPORT_NAME=My App Snapshot Tests`

### Usage In Swift Testing (Parallel By Default)

`Swift Testing` runs tests in parallel by default. This package is parallel-safe for recording because it uses actor-isolated collectors/runtime and supports per-run output directories (`SNAPSHOT_REPORT_OUTPUT_DIR`) for aggregation.

```swift
import Testing
import SnapshotTesting
import SnapshotReportSnapshotTesting

@Suite("Login Snapshots")
struct LoginSnapshots {
  private static let reportConfigured: Void = {
    configureSnapshotReport(
      reportName: "iOS Snapshot Tests",
      metadata: ["platform": "iOS", "suite": "Login"]
    )
    configureSnapshotAssertionDefaults(
      .init(
        device: .iPhone13,
        configuredOSMajorVersion: 26,
        captureHeight: .large,
        highContrastReport: false
      )
    )
  }()

  @Test("login screen light/dark")
  func loginDefaultModes() {
    _ = Self.reportConfigured

    let failures = assertSnapshot(
      of: LoginViewController(),
      highContrastReport: false,
      referenceURL: "https://app.zeplin.io/project/abc/screen/login"
    )

    #expect(failures.isEmpty)
  }

  @Test("login screen all appearance modes")
  func loginAllModes() {
    _ = Self.reportConfigured

    let failures = assertSnapshot(
      of: LoginViewController(),
      captureHeight: .complete,
      highContrastReport: true
    )

    #expect(failures.isEmpty)
  }
}
```

### Usage In XCTestCase

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
      device: .iPhoneSe,
      referenceURL: "https://www.figma.com/file/abc/Login?node-id=1"
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
- `configuredOSMajorVersion`: a single configured runtime major version (default from global assertion defaults).
- Global defaults are centralized with `configureSnapshotAssertionDefaults(...)`, and per-assert overrides remain optional.
- `captureHeight`: choose `.device`, `.large`, `.complete`, or `.points(Double)` for taller captures.
- `highContrastReport: true` forces high-contrast variants and uses order: high contrast light, light, dark, high contrast dark.
- `missingReferencePolicy`: defaults to `.recordOnMissingReference` (auto-record if asset is missing).
- `diffing`: defaults to `CoreImageDifferenceDiffing()` and attaches an advanced diff PNG on failures. The actual image is also always attached so `odiff` can run at CLI time.
- `referenceURL`: optional design reference URL (Zeplin, Figma, etc.) rendered as a link in the HTML report.

### Custom Snapshotting Strategies

You can still use any SnapshotTesting strategy and record it in the report:

```swift
assertReportingSnapshot(
  of: value,
  as: .json,
  referenceURL: "https://app.zeplin.io/project/abc/screen/123"
)
```

### Generate Final HTML/JUnit/JSON

After tests generate one or more run JSON files:

```bash
# Basic
swift run snapshot-report \
  --input .artifacts/snapshot-run.json \
  --output .artifacts/report \
  --format json,junit,html

# With odiff (auto-detected on PATH, or specify --odiff /path/to/odiff)
swift run snapshot-report \
  --input-dir .artifacts/snapshot-runs \
  --output .artifacts/report \
  --format json,junit,html

# From xcresult (no custom assertion layer required)
swift run snapshot-report \
  --xcresult DerivedData/MyApp.xcresult \
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
- `test.referenceURL` — design reference URL (empty string if not set)
- `test.failure.message|file|line|diff`
- `test.attachments[].name|type|path|content`

Attachment names produced automatically by the assertion layer:

| Name | Description |
|---|---|
| `Snapshot` | Reference image from `__Snapshots__/` |
| `Actual Snapshot` | Image captured during the failing test run |
| `Advanced Diff` | CoreImage difference blend (when `diffing` is provided) |
| `odiff` | SIMD-accelerated diff from the `odiff` binary (added at CLI time) |
| `Failure Message` | Plain-text failure message (when no diff text is embedded) |

## Environment Variables (Runtime Configuration)

| Variable | Effect |
|---|---|
| `SNAPSHOT_REPORT_OUTPUT_DIR` | Directory for per-run JSON files; a unique filename is generated per process |
| `SNAPSHOT_REPORT_OUTPUT` | Explicit full path for the output JSON |
| `SNAPSHOT_REPORT_NAME` | Report name embedded in the JSON |
| `SRCROOT` | Fallback root; output defaults to `$SRCROOT/.artifacts/snapshot-runs/` |
| `SCHEME_NAME`, `GIT_BRANCH`, `TEST_PLAN_NAME`, `TARGET_NAME` | Auto-populated into report metadata |

## GitLab CI Example

Use `snapshot-report inspect --gitlab` to generate a tailored snippet, or start from this template:

```yaml
snapshot-tests:
  stage: test
  script:
    - xcodebuild test
        -project MyApp.xcodeproj
        -scheme MyApp
        -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
        SNAPSHOT_REPORT_OUTPUT_DIR=$CI_PROJECT_DIR/.artifacts/snapshot-runs
        SRCROOT=$CI_PROJECT_DIR
        GIT_BRANCH=$CI_COMMIT_REF_NAME
        SCHEME_NAME=MyApp
    - swift run snapshot-report
        --input-dir .artifacts/snapshot-runs
        --output .artifacts/snapshot-report
        --format json,junit,html
  artifacts:
    paths:
      - .artifacts/snapshot-runs/
      - .artifacts/snapshot-report/
    reports:
      junit: .artifacts/snapshot-report/report.junit.xml
  only:
    - schedules
```

Schedule this pipeline in GitLab CI → Schedules to run nightly regression checks on your snapshot baselines.
