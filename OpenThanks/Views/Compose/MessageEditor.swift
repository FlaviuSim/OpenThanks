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
    /// Drives `becomeFirstResponder` / resign so one tap can steal focus from the recipient field.
    @Binding var isFocused: Bool
    var minHeight: CGFloat = 160
    var isEditable: Bool = true
    var onAddLink: (String, NSRange) -> Void
    /// Keeps Compose’s toolbar Add link in sync with the caret / highlighted range.
    var onSelectionChange: ((NSRange) -> Void)? = nil
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
    /// Kept for API compatibility. Emoji chips stay in ComposeView so the
    /// accessory can keep a visible trailing Done (Jonny / keyboard-dismiss).
    var quickEmojis: [String] = []
    var onInsertEmoji: ((String) -> Void)? = nil
    /// Fired when the UITextView becomes / resigns first responder (drives SwiftUI focus chrome).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// When set, insert at the caret (replacing any selection), move the cursor
    /// after the inserted text, then call `onPendingInsertConsumed`.
    var pendingInsert: PendingInsert? = nil
    var onPendingInsertConsumed: ((UUID) -> Void)? = nil
    /// When true, place the caret at the end after syncing text (AI rewrite).
    var pendingCaretAtEnd: Bool = false
    var onPendingCaretAtEndConsumed: (() -> Void)? = nil

    /// Keep in sync with ComposeView placeholder padding.
    /// Mic / link / photo live on the emoji row below — no extra bottom inset.
    static let textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)

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
        view.textContainerInset = Self.textInsets
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
        // No extra tap recognizer — it steals caret placement from UITextView.
        return view
    }

    func updateUIView(_ uiView: IntrinsicTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView

        applyTypography(to: uiView)

        var didPlaceCaretAtEnd = false
        if let pending = pendingInsert, !pending.text.isEmpty {
            context.coordinator.applyPendingInsert(pending, in: uiView)
        } else if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            applyTypography(to: uiView)
            let maxLen = (text as NSString).length
            if pendingCaretAtEnd {
                uiView.selectedRange = NSRange(location: maxLen, length: 0)
                didPlaceCaretAtEnd = true
            } else {
                let loc = min(selected.location, maxLen)
                uiView.selectedRange = NSRange(
                    location: loc,
                    length: min(selected.length, maxLen - loc)
                )
            }
            uiView.invalidateIntrinsicContentSize()
            context.coordinator.publishSelection(uiView.selectedRange)
        } else if pendingCaretAtEnd {
            let maxLen = (uiView.text as NSString).length
            uiView.selectedRange = NSRange(location: maxLen, length: 0)
            context.coordinator.publishSelection(uiView.selectedRange)
            didPlaceCaretAtEnd = true
        }

        if pendingCaretAtEnd, didPlaceCaretAtEnd || uiView.text == text {
            DispatchQueue.main.async {
                self.onPendingCaretAtEndConsumed?()
            }
        }

        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }

        if uiView.textContainerInset != Self.textInsets {
            uiView.textContainerInset = Self.textInsets
            uiView.invalidateIntrinsicContentSize()
        }
        if uiView.textContainer.lineFragmentPadding != 0 {
            uiView.textContainer.lineFragmentPadding = 0
        }

        context.coordinator.syncAccessoryIfNeeded()
        context.coordinator.syncFocusIfNeeded(uiView)
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
        private var lastHandledInsertID: UUID?

        init(_ parent: MessageEditor) {
            self.parent = parent
        }

        func syncFocusIfNeeded(_ textView: IntrinsicTextView) {
            if parent.isFocused {
                guard textView.isEditable else { return }
                guard !textView.isFirstResponder else { return }
                // Never become/resign inside updateUIView synchronously — that
                // re-enters SwiftUI and has frozen compose on focus flips.
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard self.parent.isFocused, textView.isEditable, !textView.isFirstResponder else { return }
                    _ = textView.becomeFirstResponder()
                }
            } else if textView.isFirstResponder {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard !self.parent.isFocused, textView.isFirstResponder else { return }
                    textView.resignFirstResponder()
                }
            }
        }

        private func publishFocus(_ focused: Bool) {
            DispatchQueue.main.async {
                guard self.parent.isFocused != focused else { return }
                self.parent.isFocused = focused
                self.parent.onFocusChange?(focused)
            }
        }

        func publishSelection(_ range: NSRange) {
            // Selection is stored outside @State — safe to call frequently.
            parent.onSelectionChange?(range)
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
            textView.invalidateIntrinsicContentSize()
            publishSelection(textView.selectedRange)
            // Focus after updateUIView returns — beginEditing publishes isFocused.
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                if !textView.isFirstResponder {
                    _ = textView.becomeFirstResponder()
                }
            }
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

            // Keep this bar short so trailing Done never collapses into “…”.
            // Emojis live in ComposeView; AI chips stay in the form when available.
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

            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

            let done = UIBarButtonItem(
                title: "Done",
                style: .done,
                target: self,
                action: #selector(doneTapped)
            )
            done.accessibilityLabel = "Dismiss keyboard"
            items.append(done)

            bar.items = items
            bar.applyOpaqueChrome()
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView as? IntrinsicTextView
            parent.text = textView.text ?? ""
            (textView as? IntrinsicTextView)?.invalidateIntrinsicContentSize()
            publishSelection(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publishSelection(textView.selectedRange)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            publishSelection(textView.selectedRange)
            publishFocus(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Snapshot before the toolbar link button runs — resigning first
            // responder must not lose the highlighted range for Add link.
            publishSelection(textView.selectedRange)
            publishFocus(false)
        }

        @objc private func addLinkTapped() {
            guard let textView else { return }
            let range = textView.selectedRange
            let full = textView.text ?? ""
            let label = range.length > 0
                ? (full as NSString).substring(with: range)
                : ""
            publishSelection(range)
            parent.onAddLink(label, range)
        }

        @objc private func voiceTapped() {
            guard !parent.voiceBusy else { return }
            parent.onToggleVoice?()
        }

        @objc private func doneTapped() {
            publishFocus(false)
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

    // Height is owned by intrinsicContentSize / sizeThatFits only.
    // Mutating `frame` here fights UIKit’s keyboard placeholder constraints
    // (accessoryView.bottom vs inputView.top) and floods the console on iPad.

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
        let screenWidth = window?.bounds.width ?? UIScreen.main.bounds.width
        let fallbackWidth = max((screenWidth.isFinite ? screenWidth : 320) - 64, 120)
        let width = bounds.width > 1 ? bounds.width : fallbackWidth
        guard width.isFinite, width > 1 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 160)
        }
        let fitting = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let measured = fitting.height
        let height = (measured.isFinite && measured > 0) ? max(160, measured) : 160
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
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
