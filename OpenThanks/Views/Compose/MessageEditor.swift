import SwiftUI
import UIKit

/// Plain-text message editor with a keyboard accessory for Add link, voice, and optional AI.
/// Selection is tracked so “Add link” can wrap highlighted text as `[label](url)`.
struct MessageEditor: UIViewRepresentable {
    struct PendingInsert: Equatable, Identifiable {
        let id: UUID
        let text: String

        init(text: String, id: UUID = UUID()) {
            self.id = id
            self.text = text
        }
    }

    @Binding var text: String
    var minHeight: CGFloat = 160
    var isEditable: Bool = true
    var onAddLink: (String, NSRange) -> Void
    var showAI: Bool = false
    var aiBusy: Bool = false
    var aiEnabled: Bool = false
    var onAI: ((AppreciationAI.Style) -> Void)?
    var showVoice: Bool = false
    var voiceListening: Bool = false
    /// True while mic permission / engine spin-up or stop cleanup runs.
    var voiceBusy: Bool = false
    var voiceEnabled: Bool = false
    var onToggleVoice: (() -> Void)?
    /// Quick emoji chips on the keyboard accessory (tappable — not under a translucent gap).
    var quickEmojis: [String] = []
    var onInsertEmoji: ((String) -> Void)? = nil
    /// Fired when the UITextView becomes / resigns first responder (drives SwiftUI focus chrome).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// When set, insert at the caret (replacing any selection), move the cursor
    /// after the inserted text, then call `onPendingInsertConsumed`.
    var pendingInsert: PendingInsert? = nil
    var onPendingInsertConsumed: ((UUID) -> Void)? = nil

    /// Keep in sync with ComposeView placeholder padding.
    static let textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)
    static let textInsetsWithVoice = UIEdgeInsets(top: 12, left: 12, bottom: 44, right: 12)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> IntrinsicTextView {
        let view = IntrinsicTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.tintColor = UIColor(Theme.coral)
        applyTypography(to: view)
        view.textContainerInset = showVoice ? Self.textInsetsWithVoice : Self.textInsets
        view.textContainer.lineFragmentPadding = 0
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

        applyTypography(to: uiView)

        if let pending = pendingInsert, !pending.text.isEmpty {
            context.coordinator.applyPendingInsert(pending, in: uiView)
        } else if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            applyTypography(to: uiView)
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

        let insets = showVoice ? Self.textInsetsWithVoice : Self.textInsets
        if uiView.textContainerInset != insets {
            uiView.textContainerInset = insets
            uiView.invalidateIntrinsicContentSize()
        }
        if uiView.textContainer.lineFragmentPadding != 0 {
            uiView.textContainer.lineFragmentPadding = 0
        }

        context.coordinator.syncAccessoryIfNeeded()
    }

    private func applyTypography(to textView: UITextView) {
        let font = Theme.uiBodyFont(size: 16, weight: .regular)
        if textView.font != font {
            textView.font = font
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        if textView.typingAttributes[.font] as? UIFont != font {
            textView.typingAttributes = attrs
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageEditor
        weak var textView: IntrinsicTextView?
        private var accessory: PaddedKeyboardToolbar?
        private var lastAIBusy: Bool?
        private var lastAIEnabled: Bool?
        private var lastShowAI: Bool?
        private var lastShowVoice: Bool?
        private var lastVoiceListening: Bool?
        private var lastVoiceBusy: Bool?
        private var lastVoiceEnabled: Bool?
        private var lastQuickEmojis: [String] = []
        private var lastHandledInsertID: UUID?

        init(_ parent: MessageEditor) {
            self.parent = parent
        }

        func applyPendingInsert(_ pending: PendingInsert, in textView: IntrinsicTextView) {
            guard lastHandledInsertID != pending.id else { return }
            lastHandledInsertID = pending.id

            let finish = {
                DispatchQueue.main.async {
                    self.parent.onPendingInsertConsumed?(pending.id)
                }
            }

            guard textView.isEditable else {
                finish()
                return
            }

            let raw = pending.text
            let ns = (textView.text ?? "") as NSString
            var range = textView.selectedRange
            if range.location == NSNotFound {
                range = NSRange(location: ns.length, length: 0)
            }
            range.location = min(range.location, ns.length)
            range.length = min(range.length, ns.length - range.location)

            // Soft space before the insert when it would otherwise stick to a word.
            var insert = raw
            if range.location > 0, range.length == 0 {
                let prev = ns.substring(with: NSRange(location: range.location - 1, length: 1))
                if prev != " ", prev != "\n", !raw.hasPrefix(" "), !raw.hasPrefix("\n") {
                    insert = " " + raw
                }
            }

            // Soft space after so the next character isn't glued to the emoji —
            // including at end-of-text so typing continues cleanly.
            let afterIndex = range.location + range.length
            if afterIndex < ns.length {
                let nextChar = ns.substring(with: NSRange(location: afterIndex, length: 1))
                if nextChar != " ", nextChar != "\n", !insert.hasSuffix(" "), !insert.hasSuffix("\n") {
                    insert += " "
                }
            } else if !insert.hasSuffix(" "), !insert.hasSuffix("\n") {
                insert += " "
            }

            let next = ns.replacingCharacters(in: range, with: insert)
            textView.text = next
            parent.text = next
            let caret = range.location + (insert as NSString).length
            textView.selectedRange = NSRange(location: min(caret, (next as NSString).length), length: 0)
            textView.becomeFirstResponder()
            textView.invalidateIntrinsicContentSize()
            finish()
        }

        func makeAccessory() -> PaddedKeyboardToolbar {
            let width = textView?.window?.bounds.width
                ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .screen.bounds.width
                ?? UIScreen.main.bounds.width
            let bar = PaddedKeyboardToolbar(
                frame: CGRect(x: 0, y: 0, width: width, height: PaddedKeyboardToolbar.preferredHeight)
            )
            bar.applyOpaqueChrome()
            bar.tintColor = UIColor(Theme.coral)
            accessory = bar
            rebuildAccessory()
            return bar
        }

        func syncAccessoryIfNeeded() {
            guard lastShowAI != parent.showAI
                || lastAIBusy != parent.aiBusy
                || lastAIEnabled != parent.aiEnabled
                || lastShowVoice != parent.showVoice
                || lastVoiceListening != parent.voiceListening
                || lastVoiceBusy != parent.voiceBusy
                || lastVoiceEnabled != parent.voiceEnabled
                || lastQuickEmojis != parent.quickEmojis
            else { return }
            rebuildAccessory()
        }

        private func rebuildAccessory() {
            guard let bar = accessory else { return }
            lastShowAI = parent.showAI
            lastAIBusy = parent.aiBusy
            lastAIEnabled = parent.aiEnabled
            lastShowVoice = parent.showVoice
            lastVoiceListening = parent.voiceListening
            lastVoiceBusy = parent.voiceBusy
            lastVoiceEnabled = parent.voiceEnabled
            lastQuickEmojis = parent.quickEmojis

            var items: [UIBarButtonItem] = [
                UIBarButtonItem(
                    title: "Add link",
                    style: .plain,
                    target: self,
                    action: #selector(addLinkTapped)
                ),
            ]

            if parent.showVoice {
                let symbol: String = {
                    if parent.voiceBusy { return "ellipsis.circle" }
                    return parent.voiceListening ? "mic.fill" : "mic"
                }()
                let mic = UIBarButtonItem(
                    image: UIImage(systemName: symbol),
                    style: .plain,
                    target: self,
                    action: #selector(voiceTapped)
                )
                // Tappable only when idle (start) or listening (stop) — not while busy.
                mic.isEnabled = parent.voiceEnabled && !parent.voiceBusy
                mic.accessibilityLabel = {
                    if parent.voiceBusy {
                        return parent.voiceListening ? "Processing dictation" : "Starting dictation"
                    }
                    return parent.voiceListening ? "Stop dictation" : "Dictate appreciation"
                }()
                items.append(mic)
            }

            if !parent.quickEmojis.isEmpty, parent.onInsertEmoji != nil {
                items.append(UIBarButtonItem(customView: makeEmojiStrip(parent.quickEmojis)))
            }

            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

            if parent.showAI {
                let actions = AppreciationAI.Style.allCases.map { style in
                    UIAction(title: style.buttonTitle) { [weak self] _ in
                        self?.parent.onAI?(style)
                    }
                }
                let ai = UIBarButtonItem(
                    title: parent.aiBusy ? "AI…" : "AI",
                    menu: UIMenu(title: "Let AI help", children: actions)
                )
                ai.isEnabled = parent.aiEnabled
                items.append(ai)
            }

            let done = UIBarButtonItem(
                title: "Done",
                style: .done,
                target: self,
                action: #selector(doneTapped)
            )
            items.append(done)

            bar.items = items
            bar.applyOpaqueChrome()
        }

        private func makeEmojiStrip(_ emojis: [String]) -> UIView {
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 2
            stack.alignment = .center
            for (index, emoji) in emojis.prefix(6).enumerated() {
                let button = UIButton(type: .system)
                button.setTitle(emoji, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 20)
                button.tag = index
                button.addTarget(self, action: #selector(emojiTapped(_:)), for: .touchUpInside)
                button.accessibilityLabel = "Insert \(emoji)"
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                stack.addArrangedSubview(button)
            }
            stack.translatesAutoresizingMaskIntoConstraints = false
            let host = UIView()
            host.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                stack.topAnchor.constraint(equalTo: host.topAnchor),
                stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                host.heightAnchor.constraint(equalToConstant: 36),
            ])
            return host
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView as? IntrinsicTextView
            parent.text = textView.text ?? ""
            (textView as? IntrinsicTextView)?.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
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

        @objc private func voiceTapped() {
            guard !parent.voiceBusy else { return }
            parent.onToggleVoice?()
        }

        @objc private func emojiTapped(_ sender: UIButton) {
            let emojis = parent.quickEmojis
            guard sender.tag >= 0, sender.tag < emojis.count else { return }
            parent.onInsertEmoji?(emojis[sender.tag])
        }

        @objc private func doneTapped() {
            textView?.resignFirstResponder()
        }
    }
}

/// Keyboard accessory toolbar with extra vertical padding so controls aren’t flush to the keys.
final class PaddedKeyboardToolbar: UIToolbar {
    static let preferredHeight: CGFloat = 56

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.preferredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the reported accessory height stable; UIKit sometimes collapses toolbars to 44.
        if abs(bounds.height - Self.preferredHeight) > 0.5 {
            var frame = self.frame
            frame.size.height = Self.preferredHeight
            self.frame = frame
        }
    }

    /// Solid chrome so scroll content (emoji chips) can’t show through the
    /// flexible-space gap and confuse taps over the keyboard.
    func applyOpaqueChrome() {
        isTranslucent = false
        let color = UIColor(Theme.surfaceRaised)
        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = color
        appearance.shadowColor = UIColor.separator
        standardAppearance = appearance
        compactAppearance = appearance
        scrollEdgeAppearance = appearance
        backgroundColor = color
        barTintColor = color
    }
}

/// UITextView that reports a fitting height so it can live inside a SwiftUI ScrollView.
final class IntrinsicTextView: UITextView {
    private var lastMeasuredWidth: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        let fallbackWidth = (window?.bounds.width ?? UIScreen.main.bounds.width) - 64
        let width = bounds.width > 0 ? bounds.width : fallbackWidth
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
