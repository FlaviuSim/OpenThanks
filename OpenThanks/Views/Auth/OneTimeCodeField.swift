import SwiftUI
import UIKit

/// UIKit-backed OTP field. SwiftUI `TextField` often shows the Messages/Mail
/// QuickType suggestion but silently drops the insert when tapped; a real
/// `UITextField` with `.oneTimeCode` receives it reliably.
struct OneTimeCodeField: UIViewRepresentable {
    @Binding var text: String
    var maxLength: Int = 6
    var isFocused: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = OTPTextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.textAlignment = .center
        field.font = Theme.otpUIFont
        field.textColor = UIColor(Theme.textPrimary)
        field.tintColor = UIColor(Theme.coral)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.spellCheckingType = .no
        // Helps AutoFill treat this as the sole security-code target.
        field.clearButtonMode = .never
        field.attributedPlaceholder = NSAttributedString(
            string: "123456",
            attributes: [
                .foregroundColor: UIColor(Theme.textTertiary),
                .font: Theme.otpUIFont
            ]
        )
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)),
                        for: .editingChanged)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        // Never clobber a longer in-field value while focused — AutoFill can
        // land before the SwiftUI binding catches up, and rewriting here drops it.
        let fieldText = uiView.text ?? ""
        if fieldText != text {
            if uiView.isFirstResponder, fieldText.count > text.count {
                let digits = String(fieldText.filter(\.isNumber).prefix(maxLength))
                if text != digits {
                    DispatchQueue.main.async {
                        context.coordinator.parent.text = digits
                    }
                }
            } else {
                uiView.text = text
            }
        }

        uiView.textColor = UIColor(Theme.textPrimary)
        uiView.textContentType = .oneTimeCode

        if isFocused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard self.isFocused, uiView.window != nil else { return }
                    if !uiView.isFirstResponder {
                        uiView.becomeFirstResponder()
                    }
                    // Nudge the keyboard / QuickType bar to rebind to this field.
                    uiView.reloadInputViews()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OneTimeCodeField
        weak var field: UITextField?

        init(_ parent: OneTimeCodeField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            applyDigits(from: field)
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let range = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: range, with: string)
            let digits = String(proposed.filter(\.isNumber).prefix(parent.maxLength))

            // Let AutoFill insert through the normal path when the result is
            // already clean digits; otherwise sanitize and apply ourselves.
            if proposed == digits {
                return true
            }
            textField.text = digits
            syncBinding(digits)
            return false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Some AutoFill paths update selection without editingChanged.
            applyDigits(from: textField)
        }

        private func applyDigits(from field: UITextField) {
            let digits = String((field.text ?? "").filter(\.isNumber).prefix(parent.maxLength))
            if field.text != digits {
                field.text = digits
            }
            syncBinding(digits)
        }

        private func syncBinding(_ digits: String) {
            if parent.text != digits {
                parent.text = digits
            }
        }
    }
}

/// Slightly taller intrinsic size so the QuickType bar targets this field
/// instead of a collapsed sibling.
private final class OTPTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 36)
    }
}

private extension Theme {
    static var otpUIFont: UIFont {
        .systemFont(ofSize: 28, weight: .semibold)
    }
}
