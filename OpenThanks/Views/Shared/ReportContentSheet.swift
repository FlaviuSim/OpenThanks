import SwiftUI

/// Sheet to report an appreciation or profile (App Store Guideline 1.2).
struct ReportContentSheet: View {
    let target: ContentReportService.Target
    let title: String
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ContentReportService.Reason = .spam
    @State private var details = ""
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                if didSubmit {
                    Section {
                        Text("Thanks — our team will review this shortly.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textPrimary)
                            .listRowBackground(Theme.surface)
                    }
                } else {
                    Section {
                        Text(title)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    }

                    Section("Why are you reporting this?") {
                        ForEach(ContentReportService.Reason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack {
                                    Text(option.title)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if reason == option {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.coral)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }

                    Section("Details (optional)") {
                        TextField("Add any context that helps us review", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .listRowBackground(Theme.surface)
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(Theme.body(13))
                                .foregroundStyle(.red)
                                .listRowBackground(Theme.surface)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Done" : "Cancel") {
                        if didSubmit { onFinished?() }
                        dismiss()
                    }
                    .foregroundStyle(Theme.coral)
                }
                if !didSubmit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(submitting ? "Sending…" : "Submit") {
                            Task { await submit() }
                        }
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .disabled(submitting)
                    }
                }
            }
            .syncAppAppearance()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func submit() async {
        guard !submitting else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            try await ContentReportService.submit(
                target: target,
                reason: reason,
                details: details
            )
            Analytics.capture("content_reported", [
                "target_type": target.typeKey,
                "reason": reason.rawValue,
            ])
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
