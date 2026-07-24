import SwiftUI
import UIKit

/// Plain-text message editor with a keyboard accessory for Add link (and optional AI).
/// Selection is tracked so “Add link” can wrap highlighted text as `[label](url)`.
struct MessageEditor: UIViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 160
    var isEditable: Bool = true
    var onAddLink: (String, NSRange) -> Void
    var showAI: Bool = false
    var aiTitle: String = "Make it warmer"
    var aiEnabled: Bool = false
    var onAI: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> IntrinsicTextView {
        let view = IntrinsicTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.tintColor = UIColor(Theme.coral)
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 6, right: 8)
        view.textContainer.lineFragmentPadding = 4
        // Nested in a SwiftUI ScrollView — avoid dual scrolling (a common freeze cause).
        view.isScrollEnabled = false
        view.keyboardDismissMode = .interactive
        view.autocapitalizationType = .sentences
        view.autocorrectionType = .default
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.inputAccessoryView = context.coordinator.makeAccessory()
        view.text = text
        view.isEditable = isEditable
        context.coordinator.textView = view
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ uiView: IntrinsicTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView

        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            let maxLen = (text as NSString).length
            let loc = min(selected.location, maxLen)
            uiView.selectedRange = NSRange(
                location: loc,
                length: min(selected.length, maxLen - loc)
            )
            uiView.invalidateIntrinsicContentSize()
        }

        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }

        context.coordinator.syncAccessoryIfNeeded()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageEditor
        weak var textView: IntrinsicTextView?
        private var accessory: UIToolbar?
        private var lastAITitle: String?
        private var lastAIEnabled: Bool?
        private var lastShowAI: Bool?

        init(_ parent: MessageEditor) {
            self.parent = parent
        }

        func makeAccessory() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
            bar.tintColor = UIColor(Theme.coral)
            accessory = bar
            rebuildAccessory()
            return bar
        }

        func syncAccessoryIfNeeded() {
            guard lastShowAI != parent.showAI
                || lastAITitle != parent.aiTitle
                || lastAIEnabled != parent.aiEnabled
            else { return }
            rebuildAccessory()
        }

        private func rebuildAccessory() {
            guard let bar = accessory else { return }
            lastShowAI = parent.showAI
            lastAITitle = parent.aiTitle
            lastAIEnabled = parent.aiEnabled

            var items: [UIBarButtonItem] = [
                UIBarButtonItem(
                    title: "Add link",
                    style: .plain,
                    target: self,
                    action: #selector(addLinkTapped)
                ),
            ]

            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

            if parent.showAI {
                let ai = UIBarButtonItem(
                    title: parent.aiTitle,
                    style: .plain,
                    target: self,
                    action: #selector(aiTapped)
                )
                ai.isEnabled = parent.aiEnabled
                items.append(ai)
            }

            bar.items = items
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView as? IntrinsicTextView
            parent.text = textView.text ?? ""
            (textView as? IntrinsicTextView)?.invalidateIntrinsicContentSize()
        }

        @objc private func addLinkTapped() {
            guard let textView else { return }
            let range = textView.selectedRange
            let full = textView.text ?? ""
            let label = range.length > 0
                ? (full as NSString).substring(with: range)
                : ""
            parent.onAddLink(label, range)
        }

        @objc private func aiTapped() {
            parent.onAI?()
        }
    }
}

/// UITextView that reports a fitting height so it can live inside a SwiftUI ScrollView.
final class IntrinsicTextView: UITextView {
    private var lastMeasuredWidth: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 64
        let fitting = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(160, fitting.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-measure only when width changes — invalidating every layout causes a freeze loop.
        if abs(bounds.width - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}
