// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComposeDraft",
    targets: [
        .target(
            name: "ComposeDraft",
            path: "Sources/ComposeDraft"
        ),
        .target(
            name: "LaunchDecisions",
            path: "Sources/LaunchDecisions"
        ),
        .target(
            name: "WidgetRouting",
            path: "Sources/WidgetRouting"
        ),
        .testTarget(
            name: "ComposeDraftTests",
            dependencies: ["ComposeDraft", "LaunchDecisions", "WidgetRouting"],
            path: ".",
            exclude: ["Sources", ".build"],
            sources: ["ComposeDraftStoreTests.swift", "ComposeLaunchDecisionsTests.swift"]
        ),
    ]
)
