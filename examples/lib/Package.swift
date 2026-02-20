// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnapshotExamplesLib",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "ExampleUIKitScreens", targets: ["ExampleUIKitScreens"]),
        .library(name: "ExampleSwiftUIScreens", targets: ["ExampleSwiftUIScreens"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.6")
    ],
    targets: [
        .target(
            name: "ExampleUIKitScreens",
            dependencies: []
        ),
        .target(
            name: "ExampleSwiftUIScreens",
            dependencies: []
        ),
        .testTarget(
            name: "UIKitSnapshotsTests",
            dependencies: [
                "ExampleUIKitScreens",
                .product(name: "SnapshotReportTesting", package: "SnapshotReportTesting"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        ),
        .testTarget(
            name: "SwiftUISnapshotsTests",
            dependencies: [
                "ExampleSwiftUIScreens",
                .product(name: "SnapshotReportTesting", package: "SnapshotReportTesting"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        )
    ]
)
