# SnapshotExamplesApps

Generated from `project.yml` with XcodeGen.

## Structure

- `UIKitExampleApp`: UIKit app consuming `ExampleUIKitScreens` from `examples/lib`.
- `SwiftUIExampleApp`: SwiftUI app consuming `ExampleSwiftUIScreens` from `examples/lib`.
- `UIKitSnapshotsTests`: test target reusing `examples/lib/Tests/UIKitSnapshotsTests`.
- `SwiftUISnapshotsTests`: test target reusing `examples/lib/Tests/SwiftUISnapshotsTests`.
- `TestPlans/UIKitSnapshots.xctestplan`: test plan for UIKit variant.
- `TestPlans/SwiftUISnapshots.xctestplan`: test plan for SwiftUI variant.

## Generate

```bash
./Scripts/generate_project.sh
```

## Run Pass Report End-to-End

```bash
./Scripts/run_pass_report.sh
```

This runs UIKit + SwiftUI test plans with explicit `-resultBundlePath` values and generates:

- `.artifacts/xcresult/*.xcresult`
- `.artifacts/review-report-pass/html/index.html`
