import SwiftUI
import UIKit

/// Plain-text message editor with a keyboard accessory for Add link (and optional AI).
/// Selection is tracked so “Add link” can wrap highlighted text as `[label](url)`.
struct MessageEditor: UIViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 160
    var isEditable: Bool = true
    var onAddLink: (String, NSRange) -> Void
    var onAI: (() -> Void)?
    var aiTitle: String = "Make it warmer"
    var aiEnabled: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(Theme.textPrimary)
        view.tintColor = UIColor(Theme.coral)
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 6, right: 8)
        view.textContainer.lineFragmentPadding = 4
        view.keyboardDismissMode = .interactive
        view.autocapitalizationType = .sentences
        view.autocorrectionType = .default
        view.isScrollEnabled = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.inputAccessoryView = context.coordinator.makeAccessory()
        view.text = text
        view.isEditable = isEditable
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView
        context.coordinator.reloadAccessory()
        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            let max = (text as NSString).length
            uiView.selectedRange = NSRange(
                location: min(selected.location, max),
                length: min(selected.length, max - min(selected.location, max))
            )
        }
        uiView.isEditable = isEditable
        uiView.textColor = UIColor(Theme.textPrimary)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageEditor
        weak var textView: UITextView?
        private var accessory: UIToolbar?

        init(_ parent: MessageEditor) {
            self.parent = parent
        }

        func makeAccessory() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()
            bar.tintColor = UIColor(Theme.coral)
            accessory = bar
            reloadAccessory()
            return bar
        }

        func reloadAccessory() {
            guard let bar = accessory else { return }
            var items: [UIBarButtonItem] = []

            let addLink = UIBarButtonItem(
                title: "Add link",
                style: .plain,
                target: self,
                action: #selector(addLinkTapped)
            )
            items.append(addLink)

            if parent.onAI != nil {
                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
                let ai = UIBarButtonItem(
                    title: parent.aiTitle,
                    style: .plain,
                    target: self,
                    action: #selector(aiTapped)
                )
                ai.isEnabled = parent.aiEnabled
                items.append(ai)
            } else {
                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }

            bar.items = items
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView
            parent.text = textView.text ?? ""
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            self.textView = textView
        }

        @objc private func addLinkTapped() {
            guard let textView else { return }
            let range = textView.selectedRange
            let full = textView.text ?? ""
            let label: String
            if range.length > 0 {
                label = (full as NSString).substring(with: range)
            } else {
                label = ""
            }
            parent.onAddLink(label, range)
        }

        @objc private func aiTapped() {
            parent.onAI?()
        }
    }
}
