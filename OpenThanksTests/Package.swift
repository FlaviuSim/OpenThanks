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
            name: "OAuthCallbackGate",
            path: "Sources/OAuthCallbackGate"
        ),
        .target(
            name: "ReviewPrompt",
            path: "Sources/ReviewPrompt"
        ),
        .target(
            name: "CampaignPush",
            path: "Sources/CampaignPush"
        ),
        .target(
            name: "PostAcceptPrompt",
            path: "Sources/PostAcceptPrompt"
        ),
        .target(
            name: "CampaignPrompt",
            path: "Sources/CampaignPrompt"
        ),
        .target(
            name: "CalendarPrompt",
            path: "Sources/CalendarPrompt"
        ),
        .target(
            name: "FirstThanksPrompt",
            path: "Sources/FirstThanksPrompt"
        ),
        .target(
            name: "StreakMath",
            path: "Sources/StreakMath"
        ),
        .target(
            name: "HeartCountDisplay",
            path: "Sources/HeartCountDisplay"
        ),
        .target(
            name: "AppreciationSubmit",
            path: "Sources/AppreciationSubmit"
        ),
        .target(
            name: "ComposeOpenCopy",
            path: "Sources/ComposeOpenCopy"
        ),
        .target(
            name: "PendingShareInviteCopy",
            path: "Sources/PendingShareInviteCopy"
        ),
        .testTarget(
            name: "ComposeDraftTests",
            dependencies: ["ComposeDraft", "PasskeySignIn", "OAuthCallbackGate", "ReviewPrompt", "CampaignPush", "PostAcceptPrompt", "StreakMath", "CampaignPrompt", "CalendarPrompt", "FirstThanksPrompt", "HeartCountDisplay", "AppreciationSubmit", "ComposeOpenCopy", "PendingShareInviteCopy"],
            path: ".",
            exclude: ["Sources", ".build"],
            sources: [
                "ComposeDraftStoreTests.swift",
                "PasskeySignInTests.swift",
                "OAuthCallbackGateTests.swift",
                "AppStoreReviewPromptTests.swift",
                "CampaignPushPermissionTests.swift",
                "PostAcceptPromptTests.swift",
                "CompetitionConfigTests.swift",
                "CampaignPromptCardTests.swift",
                "CalendarPromptCapTests.swift",
                "FirstThanksPromptTests.swift",
                "HeartCountDisplayTests.swift",
                "AppreciationSubmitTrackingTests.swift",
                "ComposeOpenCopyTests.swift",
                "PendingShareInviteCopyTests.swift",
            ]
        ),
    ]
)
