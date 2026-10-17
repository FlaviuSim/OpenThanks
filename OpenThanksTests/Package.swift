// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComposeDraft",
    targets: [
        .target(
            name: "ComposeDraft",
            path: "Sources/ComposeDraft"
        ),
        .testTarget(
            name: "ComposeDraftTests",
            dependencies: ["ComposeDraft"],
            path: ".",
            exclude: ["Sources", ".build"],
            sources: ["ComposeDraftStoreTests.swift"]
        ),
    ]
)
