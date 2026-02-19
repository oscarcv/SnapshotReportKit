# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-02-19

### Added

- Public `assertReportingSnapshot` and `assertSnapshot` helpers compatible with XCTest and Swift Testing issue recording.
- Device preset configuration with runtime compatibility validation (`SnapshotDevicePreset`), including explicit unsupported-runtime errors.
- Missing-reference policy (`recordOnMissingReference` by default) for automatic first-run recording.
- Success/failure snapshot attachments in runtime records, plus advanced CoreImage-based diff image attachment for image mismatches.
- CLI `--input-dir` support to aggregate all JSON runs recursively (useful for app + local package test-plan runs).

### Changed

- Runtime output strategy now supports `SNAPSHOT_REPORT_OUTPUT_DIR` and per-process run filenames for safer parallel aggregation.
- Runtime flush now merges into existing JSON report files rather than overwriting.

## [0.1.0] - 2026-02-19

### Added

- Protocol-based reporter architecture with one implementation per format (`json`, `junit`, `html`).
- SnapshotTesting extension target for automatic report collection and multi-appearance assertions.
- Swift 6 concurrency-ready runtime and reporter interfaces.
- DocC documentation for the common report model.
- Swift Testing test suite migration (`@Test`, `#expect`).

### Changed

- Reorganized source tree by feature/layer (`Models`, `IO`, `Reporting`, `Reporters`, `Integrations`, `CLI`).
- Updated README with architecture and documentation references.

### Removed

- Unused scaffold target files and generated example output folders.
