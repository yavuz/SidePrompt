import Foundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case note
    case prompt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .note: "Note"
        case .prompt: "Prompt"
        }
    }
}

struct SectionModel: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var order: Int

    init(id: UUID = UUID(), title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

struct PromptItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sectionId: UUID
    var body: String
    var kind: ItemKind
    var isDone: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sectionId: UUID,
        body: String,
        kind: ItemKind = .note,
        isDone: Bool = false,
        order: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sectionId = sectionId
        self.body = body
        self.kind = kind
        self.isDone = isDone
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Empty" }
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(117)) + "..."
    }
}

struct PromptTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var variables: [String] {
        TemplateEngine.variables(in: body)
    }

    var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "..."
    }
}

enum TemplateEngine {
    static func variables(in body: String) -> [String] {
        let pattern = /\{\{\s*([A-Za-z0-9_]+)\s*\}\}/
        var seen = Set<String>()
        var ordered: [String] = []
        for match in body.matches(of: pattern) {
            let name = String(match.1)
            if seen.insert(name).inserted {
                ordered.append(name)
            }
        }
        return ordered
    }

    static func render(_ body: String, values: [String: String]) -> String {
        var result = body
        for (key, value) in values {
            let variants = [
                "{{\(key)}}",
                "{{ \(key) }}",
                "{{\(key) }}",
                "{{ \(key)}}",
            ]
            for token in variants {
                result = result.replacingOccurrences(of: token, with: value)
            }
        }
        return result
    }
}

struct AppStoreData: Codable {
    var sections: [SectionModel]
    var items: [PromptItem]
    var templates: [PromptTemplate]

    static var empty: AppStoreData {
        AppStoreData(
            sections: [SectionModel(title: "Inbox", order: 0)],
            items: [],
            templates: defaultTemplates
        )
    }

    static var defaultTemplates: [PromptTemplate] {
        [
            PromptTemplate(
                title: "Explain simply",
                body: "Explain {{topic}} simply for a {{audience}}."
            ),
            PromptTemplate(
                title: "Rewrite",
                body: "Rewrite the following to be {{tone}}:\n\n{{text}}"
            ),
            PromptTemplate(
                title: "Code review",
                body: "Review this code focusing on {{focus}}:\n\n```\n{{code}}\n```"
            ),
        ]
    }

    init(sections: [SectionModel], items: [PromptItem], templates: [PromptTemplate] = defaultTemplates) {
        self.sections = sections
        self.items = items
        self.templates = templates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decode([SectionModel].self, forKey: .sections)
        items = try container.decode([PromptItem].self, forKey: .items)
        templates = try container.decodeIfPresent([PromptTemplate].self, forKey: .templates) ?? Self.defaultTemplates
    }
}
