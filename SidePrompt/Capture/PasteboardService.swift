import AppKit

enum PasteboardService {
    @discardableResult
    static func copy(_ string: String) -> Bool {
        RichTextMarkdown.writeToPasteboard(string)
    }

    /// Prefer stored RTF so bold/italic survive without a markdown round-trip.
    @discardableResult
    static func copy(_ item: PromptItem) -> Bool {
        if let rtf = item.bodyRTF,
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil),
           attributed.length > 0 {
            return copy(attributed)
        }
        return copy(item.body)
    }

    @discardableResult
    static func copy(_ attributed: NSAttributedString) -> Bool {
        let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attributed.length > 0 else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Native writer — apps like Notes / Pages / Slack read this reliably.
        if pasteboard.writeObjects([attributed]) {
            return true
        }

        return RichTextMarkdown.writeAttributed(attributed, plainFallback: trimmed, pasteboard: pasteboard)
    }

    /// Copies one item richly, or joins multiple as plain text.
    @discardableResult
    static func copy(items: [PromptItem]) -> Bool {
        guard !items.isEmpty else { return false }
        if items.count == 1 {
            return copy(items[0])
        }
        let joined = items.map(\.body).joined(separator: "\n\n")
        return copy(joined)
    }
}
