#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <version> <arm_sha256> <x86_sha256> <repository>"
  echo "Example: $0 0.1.0 <arm_sha> <x86_sha> oscarcv/SnapshotReportKit"
  exit 1
fi

VERSION="$1"
ARM_SHA="$2"
X86_SHA="$3"
REPOSITORY="$4"
TAG="v${VERSION}"

ARM_URL="https://github.com/${REPOSITORY}/releases/download/${TAG}/snapshot-report-${VERSION}-macos-arm64.tar.gz"
X86_URL="https://github.com/${REPOSITORY}/releases/download/${TAG}/snapshot-report-${VERSION}-macos-x86_64.tar.gz"

cat <<EOF
class SnapshotReport < Formula
  desc "Snapshot report generator for Swift SnapshotTesting"
  homepage "https://github.com/${REPOSITORY}"
  version "${VERSION}"

  on_macos do
    if Hardware::CPU.arm?
      url "${ARM_URL}"
      sha256 "${ARM_SHA}"
    else
      url "${X86_URL}"
      sha256 "${X86_SHA}"
    end
  end

  def install
    bin.install "snapshot-report"
    bin.install "SnapshotReportKit_SnapshotReportCore.bundle"
  end

  test do
    assert_match "snapshot-report", shell_output("\#{bin}/snapshot-report --help")
  end
end
EOF
