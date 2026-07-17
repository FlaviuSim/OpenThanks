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
        let field = UITextField()
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
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = UIColor(Theme.textPrimary)

        if isFocused {
            if !uiView.isFirstResponder {
                // Defer so the field is in the window after the sheet step swap.
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
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
            let digits = String((field.text ?? "").filter(\.isNumber).prefix(parent.maxLength))
            if field.text != digits {
                field.text = digits
            }
            if parent.text != digits {
                parent.text = digits
            }
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            // Allow AutoFill / paste of a full code in one shot.
            let current = textField.text ?? ""
            guard let range = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: range, with: string)
            let digits = String(proposed.filter(\.isNumber).prefix(parent.maxLength))
            textField.text = digits
            if parent.text != digits {
                parent.text = digits
            }
            return false
        }
    }
}

private extension Theme {
    static var otpUIFont: UIFont {
        .systemFont(ofSize: 28, weight: .semibold)
    }
}
