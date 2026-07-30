import AppKit

enum RichTextMarkdown {
    private struct Style: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var mono = false
        var link: String?

        static let plain = Style()
    }

    /// Converts rich pasteboard / attributed content into Markdown for storage.
    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }

        let full = NSMutableAttributedString(attributedString: attributed)
        full.mutableString.replaceOccurrences(
            of: "\u{00A0}",
            with: " ",
            options: [],
            range: NSRange(location: 0, length: full.length)
        )

        var result = ""
        var current = Style.plain

        full.enumerateAttributes(in: NSRange(location: 0, length: full.length)) { attrs, range, _ in
            let chunk = (full.string as NSString).substring(with: range)
            guard !chunk.isEmpty else { return }

            let next = style(from: attrs)

            if let link = next.link, !link.isEmpty {
                if current != .plain {
                    result += closingMarkers(from: current)
                    current = .plain
                }
                let label = escapeInlineMarkdown(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                if !label.isEmpty {
                    result += "[\(label)](\(link))"
                }
                return
            }

            if next != current {
                result += closingMarkers(from: current)
                result += openingMarkers(for: next)
                current = next
            }

            result += escapeInlineMarkdown(chunk)
        }

        result += closingMarkers(from: current)
        return cleanupMarkdown(result)
    }

    static func markdown(fromRTF data: Data) -> String? {
        guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return nil
        }
        let markdown = markdown(from: attributed)
        return markdown.isEmpty ? nil : markdown
    }

    static func markdown(fromHTML data: Data) -> String? {
        guard let attributed = NSAttributedString(html: data, documentAttributes: nil) else {
            return nil
        }
        let markdown = markdown(from: attributed)
        return markdown.isEmpty ? nil : markdown
    }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSAttributedString(string: "")
        }

        if let attributed = try? AttributedString(
            markdown: trimmed,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            let ns = NSMutableAttributedString(attributed)
            applyBaseFontPreservingTraits(ns, size: 14)
            return ns
        }

        return NSAttributedString(
            string: trimmed,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    /// Writes plain + RTF + HTML in one pasteboard item (reliable for rich paste).
    @discardableResult
    static func writeToPasteboard(_ markdown: String, pasteboard: NSPasteboard = .general) -> Bool {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return writeAttributed(attributedString(fromMarkdown: trimmed), plainFallback: trimmed, pasteboard: pasteboard)
    }

    @discardableResult
    static func writeAttributed(
        _ attributed: NSAttributedString,
        plainFallback: String? = nil,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let plain = (plainFallback ?? attributed.string)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty || attributed.length > 0 else { return false }

        pasteboard.clearContents()
        if attributed.length > 0, pasteboard.writeObjects([attributed]) {
            return true
        }

        // Fallback: explicit RTF + HTML + plain types on one item.
        let item = NSPasteboardItem()
        item.setString(plain.isEmpty ? attributed.string : plain, forType: .string)

        let range = NSRange(location: 0, length: attributed.length)
        if range.length > 0 {
            if let rtf = try? attributed.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                item.setData(rtf, forType: .rtf)
            }
            if let html = try? attributed.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue),
                ]
            ) {
                item.setData(html, forType: .html)
            }
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private static func applyBaseFontPreservingTraits(_ ns: NSMutableAttributedString, size: CGFloat) {
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return }

        ns.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let existing = attrs[.font] as? NSFont
            let traits = existing?.fontDescriptor.symbolicTraits ?? []
            var descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
            if !traits.isEmpty {
                descriptor = descriptor.withSymbolicTraits(traits)
            }
            let font = NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            ns.addAttribute(.font, value: font, range: range)
            if attrs[.foregroundColor] == nil {
                ns.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
    }

    private static func style(from attrs: [NSAttributedString.Key: Any]) -> Style {
        let font = attrs[.font] as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        var bold = traits.contains(.bold)
        var italic = traits.contains(.italic)

        // AttributedString → NSAttributedString may encode weight instead of bold trait.
        if let font, font.fontDescriptor.object(forKey: .face) != nil {
            let weight = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            if let w = weight?[.weight] as? CGFloat, w > 0.3 {
                bold = true
            }
        }
        if let font {
            let name = font.fontName.lowercased()
            if name.contains("bold") || name.contains("semibold") || name.contains("medium") {
                bold = true
            }
            if name.contains("italic") || name.contains("oblique") {
                italic = true
            }
        }

        return Style(
            bold: bold,
            italic: italic,
            strike: attrs[.strikethroughStyle] != nil,
            mono: font?.fontName.lowercased().contains("mono") == true,
            link: (attrs[.link] as? URL)?.absoluteString ?? (attrs[.link] as? String)
        )
    }

    private static func openingMarkers(for style: Style) -> String {
        var markers = ""
        if style.mono { markers += "`" }
        if style.bold && style.italic {
            markers += "***"
        } else if style.bold {
            markers += "**"
        } else if style.italic {
            markers += "*"
        }
        if style.strike { markers += "~~" }
        return markers
    }

    private static func closingMarkers(from style: Style) -> String {
        var markers = ""
        if style.strike { markers += "~~" }
        if style.bold && style.italic {
            markers += "***"
        } else if style.bold {
            markers += "**"
        } else if style.italic {
            markers += "*"
        }
        if style.mono { markers += "`" }
        return markers
    }

    private static func escapeInlineMarkdown(_ text: String) -> String {
        var output = ""
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]":
                output.append("\\")
                output.append(ch)
            default:
                output.append(ch)
            }
        }
        return output
    }

    private static func cleanupMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\*{4,}", with: "**", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
