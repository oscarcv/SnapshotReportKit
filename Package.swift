// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnapshotReportKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SnapshotReportTesting", targets: ["SnapshotReportTesting"]),
        .executable(name: "snapshot-report", targets: ["snapshot-report"])
    ],
    dependencies: [
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.6")
    ],
    targets: [
        .target(
            name: "SnapshotReportCore",
            dependencies: [
                .product(name: "Stencil", package: "Stencil")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SnapshotReportTesting",
            dependencies: [
                "SnapshotReportCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        ),
        .target(
            name: "SnapshotReportOdiff",
            dependencies: [
                "SnapshotReportCore"
            ]
        ),
        .target(
            name: "SnapshotReportCLI",
            dependencies: [
                "SnapshotReportCore"
            ]
        ),
        .executableTarget(
            name: "snapshot-report",
            dependencies: [
                "SnapshotReportCore",
                "SnapshotReportOdiff",
                "SnapshotReportCLI"
            ]
        ),
        .testTarget(
            name: "SnapshotReportCoreTests",
            dependencies: [
                "SnapshotReportCore",
                "SnapshotReportTesting",
                "snapshot-report"
            ]
        )
    ]
)
