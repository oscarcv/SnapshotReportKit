# ``SnapshotReportCore``

Core reporting models and reporter abstractions for snapshot test output generation.

## Overview

`SnapshotReportCore` provides:

- A common report model (`SnapshotReport`, `SnapshotSuite`, `SnapshotTestCase`)
- Attachment and failure metadata models
- Reporter protocol abstraction (`SnapshotReporter`)
- Built-in reporter implementations:
  - `JSONSnapshotReporter`
  - `JUnitSnapshotReporter`
  - `HTMLSnapshotReporter`

Use `SnapshotReportWriters.write(_:format:options:)` to emit report artifacts in one of the supported formats.

## Topics

### Common Model

- <doc:CommonModel>

### Reporter Protocol

- ``SnapshotReporter``
- ``SnapshotReportWriters``
- ``OutputFormat``
- ``ReportWriteOptions``

### Built-in Reporters

- ``JSONSnapshotReporter``
- ``JUnitSnapshotReporter``
- ``HTMLSnapshotReporter``
