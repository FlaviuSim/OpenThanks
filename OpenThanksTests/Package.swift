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
            name: "PasskeySignIn",
            path: "Sources/PasskeySignIn"
        ),
        .target(
            name: "ReviewPrompt",
            path: "Sources/ReviewPrompt"
        ),
        .target(
            name: "CampaignPush",
            path: "Sources/CampaignPush"
        ),
        .testTarget(
            name: "ComposeDraftTests",
            dependencies: ["ComposeDraft", "PasskeySignIn", "ReviewPrompt", "CampaignPush"],
            path: ".",
            exclude: ["Sources", ".build"],
            sources: [
                "ComposeDraftStoreTests.swift",
                "PasskeySignInTests.swift",
                "AppStoreReviewPromptTests.swift",
                "CampaignPushPermissionTests.swift",
            ]
        ),
    ]
)
