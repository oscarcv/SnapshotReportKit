# SnapshotExamplesLib

`examples/lib` is a standalone package with:

- `ExampleUIKitScreens`: 6 UIKit demo screens.
- `ExampleSwiftUIScreens`: 6 SwiftUI demo screens.
- `UIKitSnapshotsTests`: package snapshot tests for UIKit screens.
- `SwiftUISnapshotsTests`: package snapshot tests for SwiftUI screens.

Both test targets use:

- `SnapshotTesting`
- `SnapshotReportTesting`

Each test target auto-configures snapshot report recording in `setUp()` via `configureSnapshotReport(...)`.
