# Common Report Model

The report model is shared across all output reporters.

## Root Report

- ``SnapshotReport``
  - `name`: report label
  - `generatedAt`: ISO-8601 timestamp source
  - `suites`: collection of grouped test suites
  - `metadata`: free-form key/value context (branch, platform, device, CI build id)
  - `summary`: derived totals for all suites/tests

- ``SnapshotSummary``
  - `total`, `passed`, `failed`, `skipped`, `duration`

## Suite and Test Nodes

- ``SnapshotSuite``
  - `name`
  - `tests`

- ``SnapshotTestCase``
  - `id`
  - `name`
  - `className`
  - `status` (`passed`, `failed`, `skipped`)
  - `duration`
  - `failure`
  - `attachments`

- ``SnapshotStatus``

## Failure and Attachments

- ``SnapshotFailure``
  - `message`
  - `file`
  - `line`
  - `diff`

- ``SnapshotAttachment``
  - `name`
  - `type`
  - `path`

- ``SnapshotAttachmentType``
  - `png`
  - `text`
  - `dump`
  - `binary`
