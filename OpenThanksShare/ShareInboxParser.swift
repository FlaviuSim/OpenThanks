import Foundation
import UniformTypeIdentifiers
import Contacts

/// Turns share-sheet attachments into a gratitude draft.
enum ShareInboxParser {
    struct Draft {
        var kind: ComposeShareKind = .unknown
        var promptTitle: String = "Thank someone."
        var recipientName: String?
        var message: String?
        var sourceURL: String?
        var imageData: Data?
        var imageExtension: String = "jpg"
    }

    static func parse(extensionItems: [NSExtensionItem]) async -> Draft {
        var draft = Draft()
        var texts: [String] = []
        var urls: [URL] = []

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let contact = await loadContact(from: provider) {
                    applyContact(contact, to: &draft)
                    continue
                }
                if let image = await loadImage(from: provider) {
                    draft.kind = .photo
                    draft.promptTitle = "Thank someone in this memory"
                    draft.imageData = image.data
                    draft.imageExtension = image.ext
                    if draft.message == nil {
                        draft.message = nil // leave blank — photo is the context
                    }
                    continue
                }
                if let ics = await loadCalendarString(from: provider) {
                    applyCalendar(ics, to: &draft)
                    continue
                }
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                    continue
                }
                if let text = await loadText(from: provider) {
                    texts.append(text)
                }
            }
        }

        if draft.kind == .unknown || draft.kind == .text || draft.kind == .url {
            if let url = urls.first {
                applyURL(url, to: &draft)
            }
            if let text = texts.first {
                applyText(text, to: &draft)
            }
        } else if draft.recipientName == nil, let text = texts.first {
            // Contact/calendar may also include a label as text.
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count <= 80, draft.recipientName == nil, looksLikeName(cleaned) {
                draft.recipientName = cleaned
            }
        }

        if draft.kind == .unknown {
            draft.promptTitle = "Thank someone."
        }
        return draft
    }

    // MARK: - Contact

    private static func loadContact(from provider: NSItemProvider) async -> CNContact? {
        let types = [UTType.vCard.identifier, "public.vcard", "com.apple.contact"]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            if let data = await loadData(from: provider, typeIdentifier: type) {
                let contacts = (try? CNContactVCardSerialization.contacts(with: data)) ?? []
                if let first = contacts.first { return first }
            }
        }
        return nil
    }

    private static func applyContact(_ contact: CNContact, to draft: inout Draft) {
        draft.kind = .contact
        draft.promptTitle = "Thank this person."
        let name = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            draft.recipientName = name
        } else if !contact.organizationName.isEmpty {
            draft.recipientName = contact.organizationName
        }
    }

    // MARK: - Calendar

    private static func applyCalendar(_ ics: String, to draft: inout Draft) {
        draft.kind = .calendar
        draft.promptTitle = "Thank someone from this meeting."

        let summary = icsValue("SUMMARY", in: ics)
        let organizer = icsOrganizerName(in: ics)
        let attendees = icsAttendeeNames(in: ics)

        if let organizer, draft.recipientName == nil {
            draft.recipientName = organizer
        } else if let first = attendees.first, draft.recipientName == nil {
            draft.recipientName = first
        }

        if let summary, !summary.isEmpty {
            draft.message = "Thank you for \(summary)."
        }
    }

    private static func icsValue(_ key: String, in ics: String) -> String? {
        for line in ics.components(separatedBy: .newlines) {
            let upper = line.uppercased()
            if upper.hasPrefix("\(key):") || upper.hasPrefix("\(key);") {
                if let idx = line.firstIndex(of: ":") {
                    let value = String(line[line.index(after: idx)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return unescapeICS(value) }
                }
            }
        }
        return nil
    }

    private static func icsOrganizerName(in ics: String) -> String? {
        for line in ics.components(separatedBy: .newlines) {
            guard line.uppercased().hasPrefix("ORGANIZER") else { continue }
            if let cn = icsCNParameter(in: line) { return cn }
        }
        return nil
    }

    private static func icsAttendeeNames(in ics: String) -> [String] {
        var names: [String] = []
        for line in ics.components(separatedBy: .newlines) {
            guard line.uppercased().hasPrefix("ATTENDEE") else { continue }
            if let cn = icsCNParameter(in: line) {
                names.append(cn)
            }
        }
        return names
    }

    private static func icsCNParameter(in line: String) -> String? {
        // ORGANIZER;CN="Alex Kim":mailto:alex@…
        let parts = line.split(separator: ";", omittingEmptySubsequences: false)
        for part in parts {
            let p = String(part)
            if p.uppercased().hasPrefix("CN=") {
                var value = String(p.dropFirst(3))
                if let colon = value.firstIndex(of: ":") {
                    value = String(value[..<colon])
                }
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                value = unescapeICS(value)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func unescapeICS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - URL / text

    private static func applyURL(_ url: URL, to draft: inout Draft) {
        draft.sourceURL = url.absoluteString
        if draft.kind == .unknown { draft.kind = .url }

        let host = (url.host ?? "").lowercased()
        let path = url.path

        if host.contains("linkedin.com"), path.lowercased().contains("/in/") {
            draft.kind = .url
            draft.promptTitle = "Thank this person."
            if draft.recipientName == nil {
                draft.recipientName = linkedInName(from: path)
            }
            if draft.message == nil, let name = draft.recipientName {
                draft.message = "Thank you for connecting, \(name)."
            }
            return
        }

        draft.promptTitle = draft.promptTitle == "Thank someone."
            ? "Thank someone from this page."
            : draft.promptTitle
        if draft.message == nil {
            let hostLabel = host.replacingOccurrences(of: "www.", with: "")
            if !hostLabel.isEmpty {
                draft.message = "Thank you — thinking of you after seeing \(hostLabel)."
            }
        }
    }

    private static func linkedInName(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(where: { $0.lowercased() == "in" }),
              idx + 1 < parts.count
        else { return nil }
        let slug = parts[idx + 1]
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let cleaned = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return nil }
        return cleaned.capitalized
    }

    private static func applyText(_ text: String, to draft: inout Draft) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if draft.kind == .unknown {
            draft.kind = .text
            draft.promptTitle = "Thank someone."
        }

        if cleaned.count <= 60, looksLikeName(cleaned), draft.recipientName == nil {
            draft.recipientName = cleaned
            draft.promptTitle = "Thank this person."
            return
        }

        if draft.message == nil {
            if cleaned.count <= 280 {
                draft.message = cleaned.hasPrefix("Thank") ? cleaned : "Thank you for \(cleaned)."
            } else {
                draft.message = String(cleaned.prefix(400))
            }
        }
    }

    private static func looksLikeName(_ value: String) -> Bool {
        let banned: Set<Character> = ["@", "/", ":", "\n", "#"]
        if value.contains(where: { banned.contains($0) }) { return false }
        if value.contains("http") { return false }
        let words = value.split(separator: " ")
        return (1...4).contains(words.count)
    }

    // MARK: - NSItemProvider helpers

    private static func loadCalendarString(from provider: NSItemProvider) async -> String? {
        let types: [UTType] = [
            .calendarEvent,
            UTType(filenameExtension: "ics") ?? .data,
            UTType("com.apple.ical.ics") ?? .data,
        ]
        for type in types {
            if let string = await loadString(from: provider, type: type) {
                return string
            }
        }
        return nil
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        if let string = await loadString(from: provider, type: .plainText) {
            return string
        }
        return await loadString(from: provider, type: .text)
    }

    private static func loadImage(from provider: NSItemProvider) async -> (data: Data, ext: String)? {
        let candidates: [(UTType, String)] = [
            (.jpeg, "jpg"),
            (.png, "png"),
            (.heic, "heic"),
            (.image, "jpg"),
        ]
        for (type, ext) in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = await loadData(from: provider, typeIdentifier: type.identifier) {
                return (data, ext == "heic" ? "jpg" : ext)
            }
        }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else if let string = item as? String, let url = URL(string: string) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    private static func loadString(from provider: NSItemProvider, type: UTType) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        if let data = await loadData(from: provider, typeIdentifier: type.identifier),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else if let url = item as? URL, let string = try? String(contentsOf: url, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

private extension UTType {
    static var calendarEvent: UTType {
        UTType("public.calendar-event") ?? UTType(filenameExtension: "ics") ?? .data
    }
}
